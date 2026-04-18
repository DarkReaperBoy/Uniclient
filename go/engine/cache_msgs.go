package engine

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"uniclient/cores"
)

// CachedMessage is the message data returned to the UI from cache.
type CachedMessage struct {
	AccountID    string `json:"account_id"`
	ChatID       string `json:"chat_id"`
	MsgID        string `json:"msg_id"`
	LocalID      string `json:"local_id,omitempty"`
	SenderID     string `json:"sender_id,omitempty"`
	SenderName   string `json:"sender_name,omitempty"`
	ContentText  string `json:"content_text,omitempty"`
	ContentRaw   []byte `json:"content_raw,omitempty"`
	ContentRich  []byte `json:"content_rich,omitempty"`
	Timestamp    int64  `json:"timestamp"`
	EditedAt     int64  `json:"edited_at,omitempty"`
	Status       int    `json:"status"`
	ReplyToID    string `json:"reply_to_id,omitempty"`
	ReplyPreview string `json:"reply_preview,omitempty"`
	ForwardFrom  string `json:"forward_from,omitempty"`
	IsPinned     bool   `json:"is_pinned"`
	IsOutgoing   bool   `json:"is_outgoing"`
	HasMedia     bool   `json:"has_media"`

	// Media metadata (populated from media table join).
	MediaType          int    `json:"media_type,omitempty"`
	MediaFileName      string `json:"media_file_name,omitempty"`
	MediaMimeType      string `json:"media_mime_type,omitempty"`
	MediaFileSize      int64  `json:"media_file_size,omitempty"`
	MediaThumbB64      string `json:"media_thumb_b64,omitempty"`
	MediaLocalPath     string `json:"media_local_path,omitempty"`
	MediaWidth         int    `json:"media_width,omitempty"`
	MediaHeight        int    `json:"media_height,omitempty"`
	MediaDuration      int    `json:"media_duration,omitempty"`
	MediaDownloadState int    `json:"media_download_state,omitempty"`
}

// GetMessages returns cached messages for a chat, paginated by timestamp.
// If beforeMs is 0, returns the most recent messages.
// Falls back to fetching from the core if cache is empty on initial load.
func (e *Engine) GetMessages(accountID, chatID string, beforeMs int64, limit int) ([]CachedMessage, error) {
	if limit <= 0 {
		limit = 50
	}

	var rows *sql.Rows
	var err error
	if beforeMs > 0 {
		rows, err = e.db.Query(
			`SELECT account_id, chat_id, msg_id, local_id, sender_id, sender_name,
			        content_text, content_raw, content_rich, timestamp, edited_at,
			        status, reply_to_id, reply_preview, forward_from, is_pinned, is_outgoing, has_media
			 FROM messages
			 WHERE account_id = ? AND chat_id = ? AND timestamp < ?
			 ORDER BY timestamp DESC
			 LIMIT ?`, accountID, chatID, beforeMs, limit)
	} else {
		rows, err = e.db.Query(
			`SELECT account_id, chat_id, msg_id, local_id, sender_id, sender_name,
			        content_text, content_raw, content_rich, timestamp, edited_at,
			        status, reply_to_id, reply_preview, forward_from, is_pinned, is_outgoing, has_media
			 FROM messages
			 WHERE account_id = ? AND chat_id = ?
			 ORDER BY timestamp DESC
			 LIMIT ?`, accountID, chatID, limit)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	msgs, err := scanMessages(rows)
	if err != nil {
		return msgs, err
	}
	e.populateMediaMetadata(msgs)
	e.populateReplyPreviews(msgs)

	// If cache has fewer messages than requested on initial load, fetch from
	// core and cache. A few messages may have trickled in via the event stream
	// but that doesn't mean we have the full history page.
	if len(msgs) < limit && beforeMs == 0 {
		if acc, ok := e.getAccount(accountID); ok && acc.Core != nil {
			log.Printf("[engine] GetMessages(%s, %s): cache empty, fetching live from core...", accountID, chatID)
			live, liveErr := acc.Core.GetMessages(chatID, cores.PaginationOpts{Limit: limit})
			if liveErr != nil {
				log.Printf("[engine] GetMessages(%s, %s): core fetch failed: %v", accountID, chatID, liveErr)
			} else if len(live) > 0 {
				log.Printf("[engine] GetMessages(%s, %s): got %d live messages, caching...", accountID, chatID, len(live))
				result := make([]CachedMessage, 0, len(live))
				for _, m := range live {
					cached := e.cacheMessage(accountID, chatID, &m)
					result = append(result, cached)
				}
				return result, nil
			} else {
				log.Printf("[engine] GetMessages(%s, %s): core returned 0 messages", accountID, chatID)
			}
		} else {
			log.Printf("[engine] GetMessages(%s, %s): account not found or no core", accountID, chatID)
		}
	}

	return msgs, nil
}

// GetPinnedMessages returns all pinned messages for a chat, ordered by timestamp descending.
// Falls back to fetching from the core if the cache has none.
func (e *Engine) GetPinnedMessages(accountID, chatID string) ([]CachedMessage, error) {
	rows, err := e.db.Query(
		`SELECT account_id, chat_id, msg_id, local_id, sender_id, sender_name,
		        content_text, content_raw, content_rich, timestamp, edited_at,
		        status, reply_to_id, reply_preview, forward_from, is_pinned, is_outgoing, has_media
		 FROM messages
		 WHERE account_id = ? AND chat_id = ? AND is_pinned = 1
		 ORDER BY timestamp DESC`, accountID, chatID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	cached, err := scanMessages(rows)
	if err != nil {
		return nil, err
	}
	if len(cached) > 0 {
		return cached, nil
	}

	// Cache empty — try fetching pinned messages from the core.
	type pinnedFetcher interface {
		GetPinnedMessages(chatID string) ([]cores.Message, error)
	}
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, nil
	}
	pf, ok := acc.Core.(pinnedFetcher)
	if !ok {
		return nil, nil
	}
	live, err := pf.GetPinnedMessages(chatID)
	if err != nil {
		log.Printf("[engine] GetPinnedMessages(%s, %s): core fetch failed: %v", accountID, chatID, err)
		return nil, nil
	}
	result := make([]CachedMessage, 0, len(live))
	for _, m := range live {
		c := e.cacheMessage(accountID, chatID, &m)
		result = append(result, c)
	}
	return result, nil
}

func scanMessages(rows *sql.Rows) ([]CachedMessage, error) {
	var msgs []CachedMessage
	for rows.Next() {
		var m CachedMessage
		var localID, senderID, senderName, replyToID, replyPreview, forwardFrom sql.NullString
		var contentRaw, contentRich []byte
		var editedAt sql.NullInt64
		var isPinned, isOutgoing, hasMedia int

		if err := rows.Scan(
			&m.AccountID, &m.ChatID, &m.MsgID, &localID, &senderID, &senderName,
			&m.ContentText, &contentRaw, &contentRich, &m.Timestamp, &editedAt,
			&m.Status, &replyToID, &replyPreview, &forwardFrom, &isPinned, &isOutgoing, &hasMedia,
		); err != nil {
			return msgs, err
		}

		m.LocalID = localID.String
		m.SenderID = senderID.String
		m.SenderName = senderName.String
		m.ContentRaw = contentRaw
		m.ContentRich = contentRich
		if editedAt.Valid {
			m.EditedAt = editedAt.Int64
		}
		m.ReplyToID = replyToID.String
		m.ReplyPreview = replyPreview.String
		m.ForwardFrom = forwardFrom.String
		m.IsPinned = isPinned == 1
		m.IsOutgoing = isOutgoing == 1
		m.HasMedia = hasMedia == 1

		msgs = append(msgs, m)
	}
	return msgs, rows.Err()
}

// populateMediaMetadata fetches media info from the media table for messages that have media.
func (e *Engine) populateMediaMetadata(msgs []CachedMessage) {
	for i := range msgs {
		if !msgs[i].HasMedia {
			continue
		}
		var mediaType int
		var fileName, mimeType, thumbB64, localPath sql.NullString
		var fileSize, durationMs sql.NullInt64
		var width, height sql.NullInt64
		var downloadState int
		err := e.db.QueryRow(
			`SELECT media_type, file_name, mime_type, file_size, thumb_b64, local_path,
			        width, height, duration_ms, download_state
			 FROM media WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = 0`,
			msgs[i].AccountID, msgs[i].ChatID, msgs[i].MsgID,
		).Scan(&mediaType, &fileName, &mimeType, &fileSize, &thumbB64, &localPath,
			&width, &height, &durationMs, &downloadState)
		if err != nil {
			continue
		}
		msgs[i].MediaType = mediaType
		msgs[i].MediaFileName = fileName.String
		msgs[i].MediaMimeType = mimeType.String
		if fileSize.Valid {
			msgs[i].MediaFileSize = fileSize.Int64
		}
		msgs[i].MediaThumbB64 = thumbB64.String
		msgs[i].MediaLocalPath = localPath.String
		if width.Valid {
			msgs[i].MediaWidth = int(width.Int64)
		}
		if height.Valid {
			msgs[i].MediaHeight = int(height.Int64)
		}
		if durationMs.Valid {
			msgs[i].MediaDuration = int(durationMs.Int64 / 1000) // DB stores ms, struct uses seconds
		}
		msgs[i].MediaDownloadState = downloadState
	}
}

// cacheMessage inserts a cores.Message into the cache and returns the cached form.
func (e *Engine) cacheMessage(accountID, chatID string, msg *cores.Message) CachedMessage {
	now := time.Now().UnixMilli()
	var ts int64
	if msg.Timestamp.IsZero() {
		ts = now
	} else {
		ts = msg.Timestamp.UnixMilli()
	}

	var editedAt sql.NullInt64
	if msg.EditedAt != nil {
		editedAt = sql.NullInt64{Int64: msg.EditedAt.UnixMilli(), Valid: true}
	}

	status := msgStatusFromCore(msg.Status)
	hasMedia := len(msg.Attachments) > 0

	// Store raw as JSON for round-trip editing.
	rawBytes, _ := json.Marshal(msg)

	// Auto-populate reply preview from cache if the core didn't provide one.
	if msg.ReplyToID != "" && msg.ReplyPreview == "" {
		var replyText sql.NullString
		e.db.QueryRow(
			`SELECT content_text FROM messages WHERE account_id = ? AND chat_id = ? AND msg_id = ? LIMIT 1`,
			accountID, chatID, msg.ReplyToID,
		).Scan(&replyText)
		if replyText.Valid && replyText.String != "" {
			preview := replyText.String
			if len(preview) > 100 {
				preview = preview[:100]
			}
			msg.ReplyPreview = preview
		}
	}

	e.db.Exec(
		`INSERT OR REPLACE INTO messages
		 (account_id, chat_id, msg_id, local_id, sender_id, sender_name,
		  content_raw, content_text, timestamp, edited_at,
		  status, reply_to_id, reply_preview, forward_from, is_pinned, is_outgoing, has_media)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		accountID, chatID, msg.ID, nil, msg.SenderID, msg.SenderName,
		rawBytes, msg.Text, ts, editedAt,
		status, nullStr(msg.ReplyToID), nullStr(msg.ReplyPreview),
		nullStr(msg.ForwardFrom), boolToInt(msg.IsPinned), boolToInt(msg.IsOutgoing), boolToInt(hasMedia))

	// Cache media references.
	for i, att := range msg.Attachments {
		e.cacheMediaRef(accountID, chatID, msg.ID, i, att)
	}

	cached := CachedMessage{
		AccountID:    accountID,
		ChatID:       chatID,
		MsgID:        msg.ID,
		SenderID:     msg.SenderID,
		SenderName:   msg.SenderName,
		ContentText:  msg.Text,
		ContentRaw:   rawBytes,
		Timestamp:    ts,
		EditedAt:     editedAt.Int64,
		Status:       status,
		ReplyToID:    msg.ReplyToID,
		ReplyPreview: msg.ReplyPreview,
		ForwardFrom:  msg.ForwardFrom,
		IsPinned:     msg.IsPinned,
		IsOutgoing:   msg.IsOutgoing,
		HasMedia:     hasMedia,
	}

	// Populate media metadata from what we just cached so the returned
	// struct has all media fields filled (not just HasMedia=true).
	if hasMedia {
		single := []CachedMessage{cached}
		e.populateMediaMetadata(single)
		cached = single[0]
	}

	return cached
}

// InsertPendingMessage inserts a locally-created message (before server confirms).
func (e *Engine) InsertPendingMessage(accountID, chatID, localID, text, senderID, senderName, replyToID string) CachedMessage {
	now := time.Now().UnixMilli()

	e.db.Exec(
		`INSERT INTO messages
		 (account_id, chat_id, msg_id, local_id, sender_id, sender_name,
		  content_text, timestamp, status, reply_to_id, is_outgoing, has_media)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		accountID, chatID, localID, localID, senderID, senderName,
		text, now, MsgStatusSending, replyToID, 1, 0)

	return CachedMessage{
		AccountID:   accountID,
		ChatID:      chatID,
		MsgID:       localID,
		LocalID:     localID,
		SenderID:    senderID,
		SenderName:  senderName,
		ContentText: text,
		Timestamp:   now,
		ReplyToID:   replyToID,
		Status:      MsgStatusSending,
		IsOutgoing:  true,
	}
}

// ConfirmMessage replaces a local_id message with the server-confirmed version.
func (e *Engine) ConfirmMessage(accountID, chatID, localID, serverMsgID string) {
	e.db.Exec(
		`UPDATE messages SET msg_id = ?, local_id = NULL, status = ?
		 WHERE account_id = ? AND chat_id = ? AND msg_id = ?`,
		serverMsgID, MsgStatusSent, accountID, chatID, localID)

	e.emitEvent(EventMsgStatus, accountID, MsgStatusEvent{
		AccountID: accountID,
		ChatID:    chatID,
		MsgID:     serverMsgID,
		LocalID:   localID,
		Status:    MsgStatusSent,
	})
}

// FailMessage marks a pending message as failed.
func (e *Engine) FailMessage(accountID, chatID, localID string) {
	e.db.Exec(
		"UPDATE messages SET status = ? WHERE account_id = ? AND chat_id = ? AND msg_id = ?",
		MsgStatusFailed, accountID, chatID, localID)

	e.emitEvent(EventMsgStatus, accountID, MsgStatusEvent{
		AccountID: accountID,
		ChatID:    chatID,
		MsgID:     localID,
		LocalID:   localID,
		Status:    MsgStatusFailed,
	})
}

// GetMessageRaw retrieves the raw content of a message for editing.
func (e *Engine) GetMessageRaw(accountID, chatID, msgID string) ([]byte, error) {
	var raw []byte
	err := e.db.QueryRow(
		"SELECT content_raw FROM messages WHERE account_id = ? AND chat_id = ? AND msg_id = ?",
		accountID, chatID, msgID).Scan(&raw)
	return raw, err
}

// cacheMediaRef stores a media attachment reference.
func (e *Engine) cacheMediaRef(accountID, chatID, msgID string, seq int, att cores.FileRef) {
	mediaType := guessMediaType(att.MimeType, att.Name)

	var durationMs sql.NullInt64
	if att.Duration > 0 {
		durationMs = sql.NullInt64{Int64: int64(att.Duration) * 1000, Valid: true}
	}
	var width, height sql.NullInt64
	if att.Width > 0 {
		width = sql.NullInt64{Int64: int64(att.Width), Valid: true}
	}
	if att.Height > 0 {
		height = sql.NullInt64{Int64: int64(att.Height), Valid: true}
	}

	e.db.Exec(
		`INSERT OR REPLACE INTO media
		 (account_id, chat_id, msg_id, seq, media_type, remote_ref, thumb_b64,
		  file_name, mime_type, file_size, width, height, duration_ms,
		  download_state, last_accessed, extra)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		accountID, chatID, msgID, seq, mediaType, att.ID, att.ThumbB64,
		att.Name, att.MimeType, att.Size, width, height, durationMs,
		DownloadNone, time.Now().UnixMilli(), att.Extra)
}

// PruneOldMessages removes messages older than the hot tier limit.
// Keeps the most recent `keep` messages per chat.
func (e *Engine) PruneOldMessages(keep int) error {
	if keep <= 0 {
		keep = 200
	}
	_, err := e.db.Exec(`
		DELETE FROM messages WHERE rowid IN (
			SELECT m.rowid FROM messages m
			WHERE (
				SELECT COUNT(*) FROM messages m2
				WHERE m2.account_id = m.account_id
				  AND m2.chat_id = m.chat_id
				  AND m2.timestamp >= m.timestamp
			) > ?
		)`, keep)
	return err
}

// SharedMediaItem is a media entry returned for the right-panel gallery.
type SharedMediaItem struct {
	MsgID     string `json:"msg_id"`
	Timestamp int64  `json:"timestamp"`
	MediaType int    `json:"media_type"`
	FileName  string `json:"file_name"`
	MimeType  string `json:"mime_type"`
	FileSize  int64  `json:"file_size"`
	ThumbB64  string `json:"thumb_b64"`
	LocalPath string `json:"local_path"`
	Width     int    `json:"width"`
	Height    int    `json:"height"`
	Duration  int    `json:"duration"` // seconds
}

// GetSharedMedia queries the media table for all media in a chat, optionally
// filtered by type ("image", "video", "audio", "file", "" for all).
// Joins messages table to get timestamps. Returns newest first.
func (e *Engine) GetSharedMedia(accountID, chatID, mediaType string, limit, offset int) ([]SharedMediaItem, error) {
	if limit <= 0 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}

	// Map string filter to media_type integers.
	var typeFilter string
	switch mediaType {
	case "image":
		// image + gif + sticker
		typeFilter = fmt.Sprintf("AND m.media_type IN (%d, %d, %d)", MediaImage, MediaGIF, MediaSticker)
	case "video":
		// video + videonote
		typeFilter = fmt.Sprintf("AND m.media_type IN (%d, %d)", MediaVideo, MediaVideoNote)
	case "audio":
		// audio + voice
		typeFilter = fmt.Sprintf("AND m.media_type IN (%d, %d)", MediaAudio, MediaVoice)
	case "file":
		typeFilter = fmt.Sprintf("AND m.media_type = %d", MediaFile)
	default:
		// no filter — all media
		typeFilter = ""
	}

	query := fmt.Sprintf(`
		SELECT m.msg_id, COALESCE(msg.timestamp, 0), m.media_type,
		       m.file_name, m.mime_type, m.file_size, m.thumb_b64,
		       m.local_path, m.width, m.height, m.duration_ms
		FROM media m
		LEFT JOIN messages msg ON msg.account_id = m.account_id
		                       AND msg.chat_id = m.chat_id
		                       AND msg.msg_id = m.msg_id
		WHERE m.account_id = ? AND m.chat_id = ? AND m.seq = 0
		%s
		ORDER BY COALESCE(msg.timestamp, 0) DESC
		LIMIT ? OFFSET ?`, typeFilter)

	rows, err := e.db.Query(query, accountID, chatID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []SharedMediaItem
	for rows.Next() {
		var item SharedMediaItem
		var fileName, mimeType, thumbB64, localPath sql.NullString
		var fileSize, durationMs sql.NullInt64
		var width, height sql.NullInt64

		if err := rows.Scan(
			&item.MsgID, &item.Timestamp, &item.MediaType,
			&fileName, &mimeType, &fileSize, &thumbB64,
			&localPath, &width, &height, &durationMs,
		); err != nil {
			return items, err
		}

		item.FileName = fileName.String
		item.MimeType = mimeType.String
		if fileSize.Valid {
			item.FileSize = fileSize.Int64
		}
		item.ThumbB64 = thumbB64.String
		item.LocalPath = localPath.String
		if width.Valid {
			item.Width = int(width.Int64)
		}
		if height.Valid {
			item.Height = int(height.Int64)
		}
		if durationMs.Valid {
			item.Duration = int(durationMs.Int64 / 1000)
		}

		items = append(items, item)
	}
	return items, rows.Err()
}

// --- Helpers ---

func msgStatusFromCore(s cores.MessageStatus) int {
	switch s {
	case cores.MessageStatusSending:
		return MsgStatusSending
	case cores.MessageStatusSent:
		return MsgStatusSent
	case cores.MessageStatusDelivered:
		return MsgStatusDelivered
	case cores.MessageStatusRead:
		return MsgStatusRead
	case cores.MessageStatusFailed:
		return MsgStatusFailed
	default:
		return 0 // unknown/received — only outgoing messages have explicit status
	}
}

func nullStr(s string) sql.NullString {
	if s == "" {
		return sql.NullString{}
	}
	return sql.NullString{String: s, Valid: true}
}

// msgPreviewText returns the chat-list preview for a message.
// - Non-empty text → truncated to 100 chars (optionally prefixed with a media emoji
//   for media-with-caption messages, e.g. "📷 look at this").
// - Media-only (text empty, attachments present) → emoji + media-type label
//   (e.g. "📷 Photo", "🎙 Voice message", "📎 filename.pdf").
// - No text, no attachments → "".
func msgPreviewText(msg *cores.Message) string {
	text := msg.Text
	if len(msg.Attachments) == 0 {
		if len(text) > 100 {
			return text[:100]
		}
		return text
	}
	att := msg.Attachments[0]
	emoji, label := mediaPreviewLabel(att)
	if text != "" {
		prefix := emoji + " "
		// Budget: 100 chars total including prefix.
		if len(prefix)+len(text) > 100 {
			text = text[:100-len(prefix)]
		}
		return prefix + text
	}
	// Media-only.
	if label == "" {
		return emoji + " Attachment"
	}
	return emoji + " " + label
}

// mediaPreviewLabel returns (emoji, label) for a FileRef.
// For generic files, label is the filename (truncated) so "📎 report.pdf" renders.
func mediaPreviewLabel(att cores.FileRef) (emoji, label string) {
	switch guessMediaType(att.MimeType, att.Name) {
	case MediaImage:
		return "📷", "Photo"
	case MediaVideo:
		return "🎥", "Video"
	case MediaAudio:
		return "🎵", "Audio"
	case MediaVoice:
		return "🎙", "Voice message"
	case MediaVideoNote:
		return "📹", "Video message"
	case MediaSticker:
		return "🖼", "Sticker"
	case MediaGIF:
		return "🎞", "GIF"
	case MediaFile:
		name := att.Name
		if name == "" {
			return "📎", "File"
		}
		if len(name) > 80 {
			name = name[:80]
		}
		return "📎", name
	default:
		return "📎", "Attachment"
	}
}

func guessMediaType(mime, name string) int {
	if mime == "" {
		return MediaFile
	}
	switch {
	case mime == "image/gif":
		return MediaGIF
	case mime == "image/webp":
		// Telegram/Bale stickers are delivered as image/webp documents.
		// Non-sticker webp is vanishingly rare in chat, so classify as sticker
		// so the UI renders without a bubble background (§5 sticker treatment).
		return MediaSticker
	case len(mime) > 6 && mime[:6] == "image/":
		return MediaImage
	case len(mime) > 6 && mime[:6] == "video/":
		return MediaVideo
	case len(mime) > 6 && mime[:6] == "audio/":
		if mime == "audio/ogg" || mime == "audio/opus" {
			return MediaVoice
		}
		return MediaAudio
	default:
		return MediaFile
	}
}

// FetchLiveMessages calls the core's GetMessages directly (not cache).
// Used for reading OTP codes and other live data from connected accounts.
func (e *Engine) FetchLiveMessages(accountID, chatID string, limit int) ([]CachedMessage, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account %q not found", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account %q not connected", accountID)
	}

	msgs, err := acc.Core.GetMessages(chatID, cores.PaginationOpts{Limit: limit})
	if err != nil {
		return nil, err
	}

	result := make([]CachedMessage, len(msgs))
	for i, m := range msgs {
		hasMedia := len(m.Attachments) > 0
		result[i] = CachedMessage{
			AccountID:   accountID,
			ChatID:      chatID,
			MsgID:       m.ID,
			SenderID:    m.SenderID,
			SenderName:  m.SenderName,
			ContentText: m.Text,
			Timestamp:   m.Timestamp.UnixMilli(),
			HasMedia:    hasMedia,
		}
		// Populate media metadata from first attachment.
		if hasMedia {
			att := m.Attachments[0]
			result[i].MediaType = guessMediaType(att.MimeType, att.Name)
			result[i].MediaFileName = att.Name
			result[i].MediaMimeType = att.MimeType
			result[i].MediaFileSize = att.Size
			result[i].MediaThumbB64 = att.ThumbB64
			result[i].MediaWidth = att.Width
			result[i].MediaHeight = att.Height
			result[i].MediaDuration = att.Duration
		}
	}
	return result, nil
}

// populateReplyPreviews fills in empty ReplyPreview fields by looking up
// replied-to messages — first in the same batch, then in the DB cache.
func (e *Engine) populateReplyPreviews(msgs []CachedMessage) {
	// Index messages in this batch by (chat_id, msg_id) for fast lookup.
	batchIndex := make(map[string]string, len(msgs))
	for i := range msgs {
		batchIndex[msgs[i].ChatID+"\x00"+msgs[i].MsgID] = msgs[i].ContentText
	}

	for i := range msgs {
		if msgs[i].ReplyToID == "" || msgs[i].ReplyPreview != "" {
			continue
		}

		// Try in-batch lookup first (replies often point to nearby messages).
		key := msgs[i].ChatID + "\x00" + msgs[i].ReplyToID
		if text, ok := batchIndex[key]; ok && text != "" {
			preview := text
			if len(preview) > 100 {
				preview = preview[:100]
			}
			msgs[i].ReplyPreview = preview
		} else {
			// Fall back to DB lookup.
			var replyText sql.NullString
			e.db.QueryRow(
				`SELECT content_text FROM messages WHERE account_id = ? AND chat_id = ? AND msg_id = ? LIMIT 1`,
				msgs[i].AccountID, msgs[i].ChatID, msgs[i].ReplyToID,
			).Scan(&replyText)
			if replyText.Valid && replyText.String != "" {
				preview := replyText.String
				if len(preview) > 100 {
					preview = preview[:100]
				}
				msgs[i].ReplyPreview = preview
			}
		}

		// Persist back to DB so future queries don't need the lookup.
		if msgs[i].ReplyPreview != "" {
			e.db.Exec(
				`UPDATE messages SET reply_preview = ? WHERE account_id = ? AND chat_id = ? AND msg_id = ?`,
				msgs[i].ReplyPreview, msgs[i].AccountID, msgs[i].ChatID, msgs[i].MsgID,
			)
		}
	}
}
