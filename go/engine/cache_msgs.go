package engine

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"uniclient/cores"
)

// AdminRankProvider is optionally implemented by cores that can provide
// admin/creator rank info for chat members (e.g. "admin", "owner", custom titles).
type AdminRankProvider interface {
	GetAdminRanks(chatID string) (map[string]string, error) // senderID → rank
}

// CachedMessage is the message data returned to the UI from cache.
type CachedMessage struct {
	AccountID    string `json:"account_id"`
	ChatID       string `json:"chat_id"`
	MsgID        string `json:"msg_id"`
	LocalID      string `json:"local_id,omitempty"`
	SenderID      string `json:"sender_id,omitempty"`
	SenderName    string `json:"sender_name,omitempty"`
	SenderRank    string `json:"sender_rank,omitempty"`
	SenderColorID int    `json:"sender_color_id,omitempty"`
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
	IsService    bool   `json:"is_service"`
	HasMedia     bool   `json:"has_media"`
	GroupedID    string `json:"grouped_id,omitempty"`
	NoForwards   bool   `json:"no_forwards"`

	// Anti-recall metadata.
	IsDeleted bool  `json:"is_deleted"`
	DeletedAt int64 `json:"deleted_at,omitempty"`

	// Scheduled message metadata.
	ScheduleDate        int64 `json:"schedule_date,omitempty"`
	IsSilent            bool  `json:"is_silent,omitempty"`
	ScheduleRepeatPeriod int  `json:"schedule_repeat_period,omitempty"`

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
	MediaRemoteRef     string `json:"media_remote_ref,omitempty"`
	MediaExtra         string `json:"media_extra,omitempty"`

	// Derived at read time (not persisted in DB).
	SenderNoForwards bool `json:"sender_no_forwards,omitempty"`
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
			`SELECT account_id, chat_id, msg_id, local_id, sender_id, sender_name, sender_rank, sender_color_id,
			        content_text, content_raw, content_rich, timestamp, edited_at,
			        status, reply_to_id, reply_preview, forward_from, is_pinned, is_outgoing, is_service, has_media, grouped_id, no_forwards, is_deleted, deleted_at
			 FROM messages
			 WHERE account_id = ? AND chat_id = ? AND timestamp < ?
			 ORDER BY timestamp DESC
			 LIMIT ?`, accountID, chatID, beforeMs, limit)
	} else {
		rows, err = e.db.Query(
			`SELECT account_id, chat_id, msg_id, local_id, sender_id, sender_name, sender_rank, sender_color_id,
			        content_text, content_raw, content_rich, timestamp, edited_at,
			        status, reply_to_id, reply_preview, forward_from, is_pinned, is_outgoing, is_service, has_media, grouped_id, no_forwards, is_deleted, deleted_at
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
	e.populateAdminRanks(accountID, chatID, msgs)
	e.populateSenderNoForwards(accountID, msgs)

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
		`SELECT account_id, chat_id, msg_id, local_id, sender_id, sender_name, sender_rank, sender_color_id,
		        content_text, content_raw, content_rich, timestamp, edited_at,
		        status, reply_to_id, reply_preview, forward_from, is_pinned, is_outgoing, is_service, has_media, grouped_id, is_deleted, deleted_at
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
		var localID, senderID, senderName, senderRank, replyToID, replyPreview, forwardFrom, groupedID sql.NullString
		var contentRaw, contentRich []byte
		var editedAt, deletedAt sql.NullInt64
		var isPinned, isOutgoing, isService, hasMedia, noForwards, isDeleted int

		if err := rows.Scan(
			&m.AccountID, &m.ChatID, &m.MsgID, &localID, &senderID, &senderName, &senderRank, &m.SenderColorID,
			&m.ContentText, &contentRaw, &contentRich, &m.Timestamp, &editedAt,
			&m.Status, &replyToID, &replyPreview, &forwardFrom, &isPinned, &isOutgoing, &isService, &hasMedia, &groupedID,
			&noForwards, &isDeleted, &deletedAt,
		); err != nil {
			return msgs, err
		}

		m.LocalID = localID.String
		m.SenderID = senderID.String
		m.SenderName = senderName.String
		m.SenderRank = senderRank.String
		m.GroupedID = groupedID.String
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
		m.IsService = isService == 1
		m.HasMedia = hasMedia == 1
		m.NoForwards = noForwards == 1
		m.IsDeleted = isDeleted == 1
		if deletedAt.Valid {
			m.DeletedAt = deletedAt.Int64
		}

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
		var fileName, mimeType, thumbB64, localPath, remoteRef, extra sql.NullString
		var fileSize, durationMs sql.NullInt64
		var width, height sql.NullInt64
		var downloadState int
		err := e.db.QueryRow(
			`SELECT media_type, file_name, mime_type, file_size, thumb_b64, local_path,
			        width, height, duration_ms, download_state, remote_ref, extra
			 FROM media WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = 0`,
			msgs[i].AccountID, msgs[i].ChatID, msgs[i].MsgID,
		).Scan(&mediaType, &fileName, &mimeType, &fileSize, &thumbB64, &localPath,
			&width, &height, &durationMs, &downloadState, &remoteRef, &extra)
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
		msgs[i].MediaRemoteRef = remoteRef.String
		msgs[i].MediaExtra = extra.String
	}
}

// populateAdminRanks fills in SenderRank for cached messages by querying the core.
// Only runs once per chat, and only if the core implements AdminRankProvider.
func (e *Engine) populateAdminRanks(accountID, chatID string, msgs []CachedMessage) {
	if len(msgs) == 0 {
		return
	}
	// Only populate for group/channel chats (negative IDs).
	if len(chatID) == 0 || chatID[0] != '-' {
		return
	}
	// Check if any message already has a rank — if so, we've already populated.
	for _, m := range msgs {
		if m.SenderRank != "" {
			return
		}
	}
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return
	}
	provider, ok := acc.Core.(AdminRankProvider)
	if !ok {
		return
	}
	ranks, err := provider.GetAdminRanks(chatID)
	if err != nil {
		return
	}
	if len(ranks) == 0 {
		return
	}
	for i := range msgs {
		if rank, ok := ranks[msgs[i].SenderID]; ok {
			msgs[i].SenderRank = rank
			// Also update the DB so future loads have the rank.
			e.db.Exec(`UPDATE messages SET sender_rank = ? WHERE account_id = ? AND chat_id = ? AND msg_id = ?`,
				rank, msgs[i].AccountID, msgs[i].ChatID, msgs[i].MsgID)
		}
	}
}

// populateSenderNoForwards sets SenderNoForwards on messages whose sender
// has the no_forwards_peer flag enabled in the users table.
func (e *Engine) populateSenderNoForwards(accountID string, msgs []CachedMessage) {
	if len(msgs) == 0 {
		return
	}
	// Collect unique sender IDs.
	senderSet := make(map[string]struct{})
	for _, m := range msgs {
		if m.SenderID != "" {
			senderSet[m.SenderID] = struct{}{}
		}
	}
	if len(senderSet) == 0 {
		return
	}
	// Query the users table for no_forwards_peer.
	noFwdPeers := make(map[string]bool)
	for sid := range senderSet {
		var nfp int
		err := e.db.QueryRow(
			`SELECT no_forwards_peer FROM users WHERE account_id = ? AND user_id = ?`,
			accountID, sid,
		).Scan(&nfp)
		if err == nil && nfp != 0 {
			noFwdPeers[sid] = true
		}
	}
	if len(noFwdPeers) == 0 {
		return
	}
	for i := range msgs {
		if noFwdPeers[msgs[i].SenderID] {
			msgs[i].SenderNoForwards = true
		}
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

	// Serialize rich-text entities to JSON for the content_rich column.
	var richBytes []byte
	if len(msg.Entities) > 0 {
		richBytes, _ = json.Marshal(msg.Entities)
	}

	// Auto-populate reply preview from cache if the core didn't provide one.
	if msg.ReplyToID != "" && msg.ReplyPreview == "" {
		var sn, ct sql.NullString
		e.db.QueryRow(
			`SELECT sender_name, content_text FROM messages WHERE account_id = ? AND chat_id = ? AND msg_id = ? LIMIT 1`,
			accountID, chatID, msg.ReplyToID,
		).Scan(&sn, &ct)
		if ct.Valid && ct.String != "" {
			preview := ct.String
			if len(preview) > 100 {
				preview = preview[:100]
			}
			if sn.Valid && sn.String != "" {
				msg.ReplyPreview = sn.String + "\n" + preview
			} else {
				msg.ReplyPreview = preview
			}
		}
	}

	e.db.Exec(
		`INSERT INTO messages
		 (account_id, chat_id, msg_id, local_id, sender_id, sender_name, sender_rank, sender_color_id,
		  content_raw, content_rich, content_text, timestamp, edited_at,
		  status, reply_to_id, reply_preview, forward_from, is_pinned, is_outgoing, is_service, has_media, grouped_id, no_forwards)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		 ON CONFLICT(account_id, chat_id, msg_id) DO UPDATE SET
		  local_id=excluded.local_id, sender_id=excluded.sender_id, sender_name=excluded.sender_name,
		  sender_rank=excluded.sender_rank, sender_color_id=excluded.sender_color_id,
		  content_raw=excluded.content_raw, content_rich=excluded.content_rich, content_text=excluded.content_text,
		  timestamp=excluded.timestamp, edited_at=excluded.edited_at, status=excluded.status,
		  reply_to_id=excluded.reply_to_id, reply_preview=excluded.reply_preview, forward_from=excluded.forward_from,
		  is_pinned=excluded.is_pinned, is_outgoing=excluded.is_outgoing, is_service=excluded.is_service,
		  has_media=excluded.has_media, grouped_id=excluded.grouped_id, no_forwards=excluded.no_forwards`,
		accountID, chatID, msg.ID, nil, msg.SenderID, msg.SenderName, nullStr(msg.SenderRank), msg.SenderColorID,
		rawBytes, richBytes, msg.Text, ts, editedAt,
		status, nullStr(msg.ReplyToID), nullStr(msg.ReplyPreview),
		nullStr(msg.ForwardFrom), boolToInt(msg.IsPinned), boolToInt(msg.IsOutgoing), boolToInt(msg.IsService), boolToInt(hasMedia), nullStr(msg.GroupedID), boolToInt(msg.NoForwards))

	// Cache media references.
	for i, att := range msg.Attachments {
		e.cacheMediaRef(accountID, chatID, msg.ID, i, att)
	}

	cached := CachedMessage{
		AccountID:     accountID,
		ChatID:        chatID,
		MsgID:         msg.ID,
		SenderID:      msg.SenderID,
		SenderName:    msg.SenderName,
		SenderRank:    msg.SenderRank,
		SenderColorID: msg.SenderColorID,
		ContentText:   msg.Text,
		ContentRaw:   rawBytes,
		ContentRich:  richBytes,
		Timestamp:    ts,
		EditedAt:     editedAt.Int64,
		Status:       status,
		ReplyToID:    msg.ReplyToID,
		ReplyPreview: msg.ReplyPreview,
		ForwardFrom:  msg.ForwardFrom,
		IsPinned:     msg.IsPinned,
		IsOutgoing:   msg.IsOutgoing,
		IsService:    msg.IsService,
		HasMedia:     hasMedia,
		GroupedID:    msg.GroupedID,
		NoForwards:   msg.NoForwards,
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

type SharedMediaCountItem struct {
	MediaType string `json:"media_type"`
	Count     int    `json:"count"`
}

func (e *Engine) GetSharedMediaCounts(accountID, chatID string) ([]SharedMediaCountItem, error) {
	query := `
		SELECT m.media_type, COUNT(*) as cnt
		FROM media m
		WHERE m.account_id = ? AND m.chat_id = ? AND m.seq = 0
		GROUP BY m.media_type
		ORDER BY m.media_type`

	rows, err := e.db.Query(query, accountID, chatID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	typeLabel := map[int]string{
		MediaImage:     "photo",
		MediaVideo:     "video",
		MediaAudio:     "audio",
		MediaVoice:     "voice",
		MediaVideoNote: "videonote",
		MediaSticker:   "sticker",
		MediaGIF:       "gif",
		MediaFile:      "file",
	}

	var result []SharedMediaCountItem
	for rows.Next() {
		var mt, cnt int
		if err := rows.Scan(&mt, &cnt); err != nil {
			return result, err
		}
		label, ok := typeLabel[mt]
		if !ok {
			label = fmt.Sprintf("type_%d", mt)
		}
		result = append(result, SharedMediaCountItem{MediaType: label, Count: cnt})
	}
	return result, rows.Err()
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
	case MediaPoll:
		return "📊", "Poll"
	case MediaLocation:
		return "📍", "Location"
	case MediaContact:
		return "👤", "Contact"
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
	case mime == "application/x-location":
		return MediaLocation
	case mime == "application/x-contact":
		return MediaContact
	case mime == "application/x-poll":
		return MediaPoll
	case mime == "application/x-invoice":
		return MediaInvoice
	case mime == "image/gif":
		return MediaGIF
	case mime == "image/webp":
		return MediaSticker
	case mime == "application/x-tgsticker":
		return MediaSticker
	case mime == "video/webm+sticker":
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
			SenderRank:  m.SenderRank,
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
// Format: "SenderName\nPreviewText" (newline separates sender from content).
func (e *Engine) populateReplyPreviews(msgs []CachedMessage) {
	type replyInfo struct {
		senderName string
		text       string
	}
	// Index messages in this batch by (chat_id, msg_id) for fast lookup.
	batchIndex := make(map[string]replyInfo, len(msgs))
	for i := range msgs {
		batchIndex[msgs[i].ChatID+"\x00"+msgs[i].MsgID] = replyInfo{
			senderName: msgs[i].SenderName,
			text:       msgs[i].ContentText,
		}
	}

	for i := range msgs {
		if msgs[i].ReplyToID == "" || msgs[i].ReplyPreview != "" {
			continue
		}

		var senderName, previewText string

		// Try in-batch lookup first (replies often point to nearby messages).
		key := msgs[i].ChatID + "\x00" + msgs[i].ReplyToID
		if info, ok := batchIndex[key]; ok && info.text != "" {
			senderName = info.senderName
			previewText = info.text
		} else {
			// Fall back to DB lookup.
			var sn, ct sql.NullString
			e.db.QueryRow(
				`SELECT sender_name, content_text FROM messages WHERE account_id = ? AND chat_id = ? AND msg_id = ? LIMIT 1`,
				msgs[i].AccountID, msgs[i].ChatID, msgs[i].ReplyToID,
			).Scan(&sn, &ct)
			if ct.Valid && ct.String != "" {
				previewText = ct.String
			}
			if sn.Valid {
				senderName = sn.String
			}
		}

		if previewText != "" {
			if len(previewText) > 100 {
				previewText = previewText[:100]
			}
			if senderName != "" {
				msgs[i].ReplyPreview = senderName + "\n" + previewText
			} else {
				msgs[i].ReplyPreview = previewText
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

// StickerSetFetcher is implemented by cores that can retrieve sticker set info.
type StickerSetFetcher interface {
	GetStickerSetInfo(shortName string, setID int64, accessHash int64) (*cores.StickerSetResult, error)
}

// GetStickerSetInfo retrieves sticker set info from the appropriate core.
func (e *Engine) GetStickerSetInfo(accountID, shortName string, setID, accessHash int64) (*cores.StickerSetResult, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(StickerSetFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support sticker sets")
	}
	return fetcher.GetStickerSetInfo(shortName, setID, accessHash)
}

type StickerSuggestionsFetcher interface {
	GetStickerSuggestions(emoji string) ([]cores.StickerInfo, error)
}

func (e *Engine) GetStickerSuggestions(accountID, emoji string) ([]cores.StickerInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(StickerSuggestionsFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support sticker suggestions")
	}
	return fetcher.GetStickerSuggestions(emoji)
}

type InstalledEmojiSetsFetcher interface {
	GetInstalledEmojiSets() ([]cores.EmojiSetSummary, error)
}

func (e *Engine) GetInstalledEmojiSets(accountID string) ([]cores.EmojiSetSummary, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(InstalledEmojiSetsFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support custom emoji sets")
	}
	return fetcher.GetInstalledEmojiSets()
}

type CustomEmojiThumbsFetcher interface {
	GetCustomEmojiThumbs(documentIDs []int64) ([]cores.CustomEmojiThumb, error)
}

func (e *Engine) GetCustomEmojiThumbs(accountID string, documentIDs []int64) ([]cores.CustomEmojiThumb, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(CustomEmojiThumbsFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support custom emoji")
	}
	return fetcher.GetCustomEmojiThumbs(documentIDs)
}

type CustomEmojiFilesFetcher interface {
	GetCustomEmojiFiles(documentIDs []int64) ([]cores.CustomEmojiFile, error)
}

func (e *Engine) GetCustomEmojiFiles(accountID string, documentIDs []int64) ([]cores.CustomEmojiFile, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(CustomEmojiFilesFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support custom emoji files")
	}
	return fetcher.GetCustomEmojiFiles(documentIDs)
}

type CustomEmojiSetInfoFetcher interface {
	GetCustomEmojiSetInfo(documentID int64) (setID int64, accessHash int64, title string, shortName string, count int32, found bool, err error)
}

func (e *Engine) GetCustomEmojiSetInfo(accountID string, documentID int64) (int64, int64, string, string, int32, bool, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return 0, 0, "", "", 0, false, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return 0, 0, "", "", 0, false, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(CustomEmojiSetInfoFetcher)
	if !ok {
		return 0, 0, "", "", 0, false, fmt.Errorf("platform does not support custom emoji set info")
	}
	return fetcher.GetCustomEmojiSetInfo(documentID)
}

type InstalledStickerPacksFetcher interface {
	GetInstalledStickerPacks() ([]cores.StickerPackSummary, error)
}

func (e *Engine) GetInstalledStickerPacks(accountID string) ([]cores.StickerPackSummary, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(InstalledStickerPacksFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support sticker packs")
	}
	return fetcher.GetInstalledStickerPacks()
}

type SavedGifsFetcher interface {
	GetSavedGifs() ([]cores.GifInfo, error)
}

func (e *Engine) GetSavedGifs(accountID string) ([]cores.GifInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(SavedGifsFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support saved GIFs")
	}
	return fetcher.GetSavedGifs()
}

type SavedSublistsFetcher interface {
	GetSavedSublists(limit, offsetDate, offsetID int, excludePinned bool) ([]cores.SavedSublistInfo, int, error)
}

func (e *Engine) GetSavedSublists(accountID string, limit, offsetDate, offsetID int, excludePinned bool) ([]cores.SavedSublistInfo, int, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, 0, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, 0, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(SavedSublistsFetcher)
	if !ok {
		return nil, 0, fmt.Errorf("platform does not support saved sublists")
	}
	return fetcher.GetSavedSublists(limit, offsetDate, offsetID, excludePinned)
}

type PinnedSavedSublistsFetcher interface {
	GetPinnedSavedSublists() ([]cores.SavedSublistInfo, int, error)
}

func (e *Engine) GetPinnedSavedSublists(accountID string) ([]cores.SavedSublistInfo, int, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, 0, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, 0, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(PinnedSavedSublistsFetcher)
	if !ok {
		return nil, 0, fmt.Errorf("platform does not support pinned saved sublists")
	}
	return fetcher.GetPinnedSavedSublists()
}

type SavedReactionTagsFetcher interface {
	GetSavedReactionTags(sublistPeerID string) ([]cores.SavedReactionTagInfo, error)
}

func (e *Engine) GetSavedReactionTags(accountID, sublistPeerID string) ([]cores.SavedReactionTagInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(SavedReactionTagsFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support saved reaction tags")
	}
	return fetcher.GetSavedReactionTags(sublistPeerID)
}

type SavedReactionTagRenamer interface {
	RenameSavedReactionTag(emoji string, customID int64, title string) error
}

func (e *Engine) RenameSavedReactionTag(accountID, emoji string, customID int64, title string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	renamer, ok := acc.Core.(SavedReactionTagRenamer)
	if !ok {
		return fmt.Errorf("platform does not support reaction tag rename")
	}
	return renamer.RenameSavedReactionTag(emoji, customID, title)
}

type SavedReactionTagRemover interface {
	RemoveSavedReactionTag(emoji string, customID int64) error
}

func (e *Engine) RemoveSavedReactionTag(accountID, emoji string, customID int64) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if remover, ok := acc.Core.(SavedReactionTagRemover); ok {
		return remover.RemoveSavedReactionTag(emoji, customID)
	}
	return fmt.Errorf("platform does not support reaction tag removal")
}

type RecentStickersFetcher interface {
	GetRecentStickers() ([]cores.StickerInfo, error)
}

func (e *Engine) GetRecentStickers(accountID string) ([]cores.StickerInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(RecentStickersFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support recent stickers")
	}
	return fetcher.GetRecentStickers()
}

type StickerFaver interface {
	FaveSticker(fileID int64, extra string, unfave bool) error
}

func (e *Engine) FaveSticker(accountID string, fileID int64, extra string, unfave bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	faver, ok := acc.Core.(StickerFaver)
	if !ok {
		return fmt.Errorf("platform does not support sticker favorites")
	}
	if extra == "" {
		extra = e.lookupMediaExtra(accountID, fileID)
	}
	return faver.FaveSticker(fileID, extra, unfave)
}

type FeaturedStickerPacksFetcher interface {
	GetFeaturedStickerPacks() ([]cores.StickerPackSummary, error)
}

func (e *Engine) GetFeaturedStickerPacks(accountID string) ([]cores.StickerPackSummary, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(FeaturedStickerPacksFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support featured sticker packs")
	}
	return fetcher.GetFeaturedStickerPacks()
}

type StickerSetSearcher interface {
	SearchStickerSets(query string) ([]cores.StickerPackSummary, error)
}

func (e *Engine) SearchStickerSets(accountID string, query string) ([]cores.StickerPackSummary, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	searcher, ok := acc.Core.(StickerSetSearcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support sticker search")
	}
	return searcher.SearchStickerSets(query)
}

type StickerSetInstaller interface {
	InstallStickerSet(setID, accessHash int64) error
}

func (e *Engine) InstallStickerSet(accountID string, setID, accessHash int64) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	installer, ok := acc.Core.(StickerSetInstaller)
	if !ok {
		return fmt.Errorf("platform does not support sticker set install")
	}
	return installer.InstallStickerSet(setID, accessHash)
}

type GifSaver interface {
	SaveGif(fileID int64, extra string, unsave bool) error
}

func (e *Engine) SaveGif(accountID string, fileID int64, extra string, unsave bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	saver, ok := acc.Core.(GifSaver)
	if !ok {
		return fmt.Errorf("platform does not support GIF saving")
	}
	if extra == "" {
		extra = e.lookupMediaExtra(accountID, fileID)
	}
	return saver.SaveGif(fileID, extra, unsave)
}

func (e *Engine) lookupMediaExtra(accountID string, fileID int64) string {
	ref := strconv.FormatInt(fileID, 10)
	var extra sql.NullString
	e.db.QueryRow(
		"SELECT extra FROM media WHERE account_id = ? AND remote_ref = ? LIMIT 1",
		accountID, ref).Scan(&extra)
	return extra.String
}

type VoiceTranscriber interface {
	TranscribeAudio(chatID, msgID string) (pending bool, transcriptionID int64, text string, err error)
}

type TextTranslator interface {
	TranslateText(chatID, msgID, toLang string) (string, error)
}

type FreeTextTranslator interface {
	TranslateFreeText(text, toLang string) (string, error)
}

func (e *Engine) TranslateText(accountID, chatID, msgID, toLang, text string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return "", fmt.Errorf("account not connected: %s", accountID)
	}
	if text != "" {
		ft, ok := acc.Core.(FreeTextTranslator)
		if !ok {
			return "", fmt.Errorf("platform does not support freeform text translation")
		}
		return ft.TranslateFreeText(text, toLang)
	}
	translator, ok := acc.Core.(TextTranslator)
	if !ok {
		return "", fmt.Errorf("platform does not support translation")
	}
	return translator.TranslateText(chatID, msgID, toLang)
}

func (e *Engine) TranscribeAudio(accountID, chatID, msgID string) (bool, int64, string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return false, 0, "", fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return false, 0, "", fmt.Errorf("account not connected: %s", accountID)
	}
	transcriber, ok := acc.Core.(VoiceTranscriber)
	if !ok {
		return false, 0, "", fmt.Errorf("platform does not support voice transcription")
	}
	return transcriber.TranscribeAudio(chatID, msgID)
}

type MessageContentsReader interface {
	MessagesReadMessageContents(id []int) (interface{}, error)
}

func (e *Engine) ReadMessageContents(accountID, msgID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	reader, ok := acc.Core.(MessageContentsReader)
	if !ok {
		return fmt.Errorf("platform does not support ReadMessageContents")
	}
	id, err := strconv.Atoi(msgID)
	if err != nil {
		return fmt.Errorf("invalid message ID: %s", msgID)
	}
	_, err = reader.MessagesReadMessageContents([]int{id})
	return err
}

type PollVoter interface {
	VotePoll(chatID string, msgID string, optionIndex int) error
}

type PollVoteRetracter interface {
	RetractPollVote(chatID string, msgID string) error
}

type PollStopper interface {
	StopPoll(chatID string, msgID string) error
}

func (e *Engine) VotePoll(accountID, chatID, msgID string, optionIndex int) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	voter, ok := acc.Core.(PollVoter)
	if !ok {
		return fmt.Errorf("platform does not support poll voting")
	}
	err := voter.VotePoll(chatID, msgID, optionIndex)
	if err != nil {
		return err
	}
	e.ghostAutoRead(accountID, chatID, msgID)
	return nil
}

func (e *Engine) RetractPollVote(accountID, chatID, msgID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	retracter, ok := acc.Core.(PollVoteRetracter)
	if !ok {
		return fmt.Errorf("platform does not support vote retraction")
	}
	return retracter.RetractPollVote(chatID, msgID)
}

func (e *Engine) StopPoll(accountID, chatID, msgID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	stopper, ok := acc.Core.(PollStopper)
	if !ok {
		return fmt.Errorf("platform does not support stopping polls")
	}
	return stopper.StopPoll(chatID, msgID)
}

type StarGiftsFetcher interface {
	GetStarGifts() (*cores.StarGiftsResult, error)
}

func (e *Engine) GetStarGifts(accountID string) (*cores.StarGiftsResult, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(StarGiftsFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support star gifts")
	}
	return fetcher.GetStarGifts()
}

type PinnedGiftsFetcher interface {
	GetPinnedStarGifts(chatID string) (*cores.PinnedGiftsResult, error)
}

func (e *Engine) GetPinnedStarGifts(accountID, chatID string) (*cores.PinnedGiftsResult, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(PinnedGiftsFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support pinned gifts")
	}
	return fetcher.GetPinnedStarGifts(chatID)
}

type AttachMenuBotsFetcher interface {
	GetAttachMenuBots() ([]cores.AttachMenuBotInfo, error)
}

func (e *Engine) GetAttachMenuBots(accountID string) ([]cores.AttachMenuBotInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(AttachMenuBotsFetcher)
	if !ok {
		return nil, nil
	}
	return fetcher.GetAttachMenuBots()
}

type BotCallbackAnswerer interface {
	GetBotCallbackAnswer(chatID string, msgID string, data []byte) (string, error)
}

func (e *Engine) BotCallback(accountID, chatID, msgID, data string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return "", fmt.Errorf("account not connected: %s", accountID)
	}
	answerer, ok := acc.Core.(BotCallbackAnswerer)
	if !ok {
		return "", fmt.Errorf("platform does not support bot callbacks")
	}
	return answerer.GetBotCallbackAnswer(chatID, msgID, []byte(data))
}

type URLAuthRequester interface {
	RequestURLAuth(chatID string, msgID string, buttonID int) (map[string]interface{}, error)
}

func (e *Engine) RequestURLAuth(accountID, chatID, msgID string, buttonID int) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	requester, ok := acc.Core.(URLAuthRequester)
	if !ok {
		return nil, fmt.Errorf("platform does not support URL auth")
	}
	return requester.RequestURLAuth(chatID, msgID, buttonID)
}

type URLAuthAccepter interface {
	AcceptURLAuth(chatID string, msgID string, buttonID int, writeAllowed bool, sharePhone bool) (string, error)
}

func (e *Engine) AcceptURLAuth(accountID, chatID, msgID string, buttonID int, writeAllowed, sharePhone bool) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return "", fmt.Errorf("account not connected: %s", accountID)
	}
	accepter, ok := acc.Core.(URLAuthAccepter)
	if !ok {
		return "", fmt.Errorf("platform does not support URL auth")
	}
	return accepter.AcceptURLAuth(chatID, msgID, buttonID, writeAllowed, sharePhone)
}

type BotWebViewRequester interface {
	RequestBotWebView(chatID string, botID string) (string, error)
}

func (e *Engine) RequestBotWebView(accountID, chatID, botID string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return "", fmt.Errorf("account not connected: %s", accountID)
	}
	requester, ok := acc.Core.(BotWebViewRequester)
	if !ok {
		return "", fmt.Errorf("platform does not support bot web views")
	}
	return requester.RequestBotWebView(chatID, botID)
}

type InlineBotQuerier interface {
	GetInlineBotResultsFull(botID string, query string, offset string, chatID string) (*cores.InlineBotResults, error)
}

func (e *Engine) GetInlineBotResultsFull(accountID, botID, query, offset, chatID string) (*cores.InlineBotResults, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	querier, ok := acc.Core.(InlineBotQuerier)
	if !ok {
		return nil, fmt.Errorf("platform does not support inline bots")
	}
	return querier.GetInlineBotResultsFull(botID, query, offset, chatID)
}

type UsernameResolver interface {
	ResolveUsername(username string) (string, error)
}

func (e *Engine) ResolveUsername(accountID, username string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return "", fmt.Errorf("account not connected: %s", accountID)
	}
	resolver, ok := acc.Core.(UsernameResolver)
	if !ok {
		return "", fmt.Errorf("platform does not support username resolution")
	}
	return resolver.ResolveUsername(username)
}

type InlineBotResultSender interface {
	SendInlineBotResult(chatID string, queryID int64, resultID string) (int, error)
}

func (e *Engine) SendInlineBotResult(accountID, chatID string, queryID int64, resultID string) (int, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return 0, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return 0, fmt.Errorf("account not connected: %s", accountID)
	}
	sender, ok := acc.Core.(InlineBotResultSender)
	if !ok {
		return 0, fmt.Errorf("platform does not support inline bot results")
	}
	return sender.SendInlineBotResult(chatID, queryID, resultID)
}

func (e *Engine) SendSticker(accountID, chatID, stickerID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	_, err := acc.Core.SendSticker(chatID, stickerID)
	return err
}

func (e *Engine) CreatePoll(accountID, chatID, question string, options []string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return "", fmt.Errorf("account not connected: %s", accountID)
	}
	msg, err := acc.Core.CreatePoll(chatID, question, options)
	if err != nil {
		return "", err
	}
	if msg != nil {
		return msg.ID, nil
	}
	return "", nil
}

type MessageReporter interface {
	ReportMessage(chatID string, msgIDs []int, option []byte, message string) (*cores.ReportResult, error)
}

func (e *Engine) ReportMessage(accountID, chatID string, msgIDs []int, option []byte, message string) (*cores.ReportResult, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	reporter, ok := acc.Core.(MessageReporter)
	if !ok {
		return nil, fmt.Errorf("platform does not support message reporting")
	}
	return reporter.ReportMessage(chatID, msgIDs, option, message)
}

type StoryFetcher interface {
	FetchPeerStoriesData(peerID string) (string, error)
}

func (e *Engine) FetchPeerStories(accountID, peerID string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return "", fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(StoryFetcher)
	if !ok {
		return "", fmt.Errorf("platform does not support stories")
	}
	storiesJSON, err := fetcher.FetchPeerStoriesData(peerID)
	if err != nil {
		return "", err
	}

	// Download each story's media to local path.
	type storyEntry struct {
		ID      int            `json:"id"`
		FileRef cores.FileRef  `json:"file_ref"`
	}
	var entries []storyEntry
	if err := json.Unmarshal([]byte(storiesJSON), &entries); err != nil {
		return storiesJSON, nil
	}

	dir := filepath.Join(e.mediaDir, accountID, "stories")
	os.MkdirAll(dir, 0o755)

	type storyFull map[string]interface{}
	var items []storyFull
	if err := json.Unmarshal([]byte(storiesJSON), &items); err != nil {
		return storiesJSON, nil
	}

	for i, entry := range entries {
		if entry.FileRef.ID == "" { continue }
		ext := ".jpg"
		if entry.FileRef.MimeType != "" && entry.FileRef.MimeType != "image/jpeg" {
			ext = ".mp4"
		}
		localPath := filepath.Join(dir, fmt.Sprintf("%d%s", entry.ID, ext))
		if _, err := os.Stat(localPath); err == nil {
			items[i]["local_path"] = localPath
			continue
		}
		if err := acc.Core.DownloadFile(entry.FileRef, localPath, nil); err == nil {
			items[i]["local_path"] = localPath
		}
	}

	out, _ := json.Marshal(items)
	return string(out), nil
}

type StoryAlbumFetcher interface {
	GetStoryAlbums(peerID string) ([]StoryAlbumInfo, error)
	GetAlbumStories(peerID string, albumID int, offset, limit int) (string, int, error)
	CreateStoryAlbum(title string) (int64, string, error)
	ReorderStoryAlbums(albumIDs []int) error
}

type StoryAlbumInfo struct {
	ID    int64  `json:"id"`
	Title string `json:"title"`
	Count int    `json:"count"`
}

func (e *Engine) GetStoryAlbums(accountID string) ([]StoryAlbumInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(StoryAlbumFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support story albums")
	}
	return fetcher.GetStoryAlbums("")
}

func (e *Engine) GetAlbumStories(accountID string, albumID int64, offset, limit int) (string, int, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", 0, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return "", 0, fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(StoryAlbumFetcher)
	if !ok {
		return "", 0, fmt.Errorf("platform does not support story albums")
	}
	return fetcher.GetAlbumStories("", int(albumID), offset, limit)
}

func (e *Engine) CreateStoryAlbum(accountID, title string) (int64, string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return 0, "", fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return 0, "", fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(StoryAlbumFetcher)
	if !ok {
		return 0, "", fmt.Errorf("platform does not support story albums")
	}
	return fetcher.CreateStoryAlbum(title)
}

func (e *Engine) ReorderStoryAlbums(accountID string, albumIDs []int64) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(StoryAlbumFetcher)
	if !ok {
		return fmt.Errorf("platform does not support story albums")
	}
	ids := make([]int, len(albumIDs))
	for i, id := range albumIDs {
		ids[i] = int(id)
	}
	return fetcher.ReorderStoryAlbums(ids)
}

type StorySender interface {
	SendStoryWithPhoto(text string, photoData []byte) (int, error)
}

func (e *Engine) SendStoryWithPhoto(accountID, text string, photoData []byte) (int, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return 0, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return 0, fmt.Errorf("account not connected: %s", accountID)
	}
	sender, ok := acc.Core.(StorySender)
	if !ok {
		return 0, fmt.Errorf("platform does not support sending stories")
	}
	return sender.SendStoryWithPhoto(text, photoData)
}

type EditRevision struct {
	ID           int64  `json:"id"`
	AccountID    string `json:"account_id"`
	ChatID       string `json:"chat_id"`
	MsgID        string `json:"msg_id"`
	SenderID     string `json:"sender_id"`
	SenderName   string `json:"sender_name"`
	ContentText  string `json:"content_text"`
	EntitiesJSON string `json:"entities_json,omitempty"`
	Timestamp    int64  `json:"timestamp"`
}

func (e *Engine) GetEditRevisions(accountID, chatID, msgID string, offset, limit int) ([]EditRevision, error) {
	rows, err := e.db.Query(
		`SELECT id, account_id, chat_id, msg_id, sender_id, sender_name, content_text, entities_json, timestamp
		 FROM edited_messages
		 WHERE account_id = ? AND chat_id = ? AND msg_id = ?
		 ORDER BY id DESC
		 LIMIT ? OFFSET ?`,
		accountID, chatID, msgID, limit, offset,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var revisions []EditRevision
	for rows.Next() {
		var r EditRevision
		var entJSON sql.NullString
		if err := rows.Scan(&r.ID, &r.AccountID, &r.ChatID, &r.MsgID, &r.SenderID, &r.SenderName, &r.ContentText, &entJSON, &r.Timestamp); err != nil {
			return nil, err
		}
		if entJSON.Valid {
			r.EntitiesJSON = entJSON.String
		}
		revisions = append(revisions, r)
	}
	return revisions, nil
}

func (e *Engine) HasEditRevisions(accountID, chatID, msgID string) (bool, error) {
	var count int
	err := e.db.QueryRow(
		`SELECT COUNT(*) FROM edited_messages WHERE account_id = ? AND chat_id = ? AND msg_id = ?`,
		accountID, chatID, msgID,
	).Scan(&count)
	return count > 0, err
}

func (e *Engine) GetDeletedMessages(accountID, chatID string, search string, offset, limit int) ([]CachedMessage, error) {
	var rows *sql.Rows
	var err error
	if search != "" {
		escaped := strings.ReplaceAll(search, "\\", "\\\\")
		escaped = strings.ReplaceAll(escaped, "%", "\\%")
		escaped = strings.ReplaceAll(escaped, "_", "\\_")
		pattern := "%" + escaped + "%"
		rows, err = e.db.Query(
			`SELECT account_id, chat_id, msg_id, local_id, sender_id, sender_name, sender_rank, sender_color_id,
			        content_text, content_raw, content_rich, timestamp, edited_at,
			        status, reply_to_id, reply_preview, forward_from, is_pinned, is_outgoing, is_service, has_media, grouped_id, no_forwards, is_deleted, deleted_at
			 FROM messages
			 WHERE account_id = ? AND chat_id = ? AND is_deleted = 1 AND content_text LIKE ? ESCAPE '\'
			 ORDER BY timestamp DESC
			 LIMIT ? OFFSET ?`, accountID, chatID, pattern, limit, offset)
	} else {
		rows, err = e.db.Query(
			`SELECT account_id, chat_id, msg_id, local_id, sender_id, sender_name, sender_rank, sender_color_id,
			        content_text, content_raw, content_rich, timestamp, edited_at,
			        status, reply_to_id, reply_preview, forward_from, is_pinned, is_outgoing, is_service, has_media, grouped_id, no_forwards, is_deleted, deleted_at
			 FROM messages
			 WHERE account_id = ? AND chat_id = ? AND is_deleted = 1
			 ORDER BY timestamp DESC
			 LIMIT ? OFFSET ?`, accountID, chatID, limit, offset)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	msgs, err := scanMessages(rows)
	if err != nil {
		return nil, err
	}
	e.populateMediaMetadata(msgs)
	return msgs, nil
}
