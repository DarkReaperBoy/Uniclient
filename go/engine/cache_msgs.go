package engine

import (
	"database/sql"
	"encoding/json"
	"fmt"
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
	HasMedia     bool   `json:"has_media"`
}

// GetMessages returns cached messages for a chat, paginated by timestamp.
// If beforeMs is 0, returns the most recent messages.
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
			        status, reply_to_id, reply_preview, forward_from, is_pinned, has_media
			 FROM messages
			 WHERE account_id = ? AND chat_id = ? AND timestamp < ?
			 ORDER BY timestamp DESC
			 LIMIT ?`, accountID, chatID, beforeMs, limit)
	} else {
		rows, err = e.db.Query(
			`SELECT account_id, chat_id, msg_id, local_id, sender_id, sender_name,
			        content_text, content_raw, content_rich, timestamp, edited_at,
			        status, reply_to_id, reply_preview, forward_from, is_pinned, has_media
			 FROM messages
			 WHERE account_id = ? AND chat_id = ?
			 ORDER BY timestamp DESC
			 LIMIT ?`, accountID, chatID, limit)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanMessages(rows)
}

func scanMessages(rows *sql.Rows) ([]CachedMessage, error) {
	var msgs []CachedMessage
	for rows.Next() {
		var m CachedMessage
		var localID, senderID, senderName, replyToID, replyPreview, forwardFrom sql.NullString
		var contentRaw, contentRich []byte
		var editedAt sql.NullInt64
		var isPinned, hasMedia int

		if err := rows.Scan(
			&m.AccountID, &m.ChatID, &m.MsgID, &localID, &senderID, &senderName,
			&m.ContentText, &contentRaw, &contentRich, &m.Timestamp, &editedAt,
			&m.Status, &replyToID, &replyPreview, &forwardFrom, &isPinned, &hasMedia,
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
		m.HasMedia = hasMedia == 1

		msgs = append(msgs, m)
	}
	return msgs, rows.Err()
}

// cacheMessage inserts a cores.Message into the cache and returns the cached form.
func (e *Engine) cacheMessage(accountID, chatID string, msg *cores.Message) CachedMessage {
	now := time.Now().UnixMilli()
	ts := msg.Timestamp.UnixMilli()
	if ts == 0 {
		ts = now
	}

	var editedAt sql.NullInt64
	if msg.EditedAt != nil {
		editedAt = sql.NullInt64{Int64: msg.EditedAt.UnixMilli(), Valid: true}
	}

	status := msgStatusFromCore(msg.Status)
	hasMedia := len(msg.Attachments) > 0

	// Store raw as JSON for round-trip editing.
	rawBytes, _ := json.Marshal(msg)

	e.db.Exec(
		`INSERT OR REPLACE INTO messages
		 (account_id, chat_id, msg_id, local_id, sender_id, sender_name,
		  content_raw, content_text, timestamp, edited_at,
		  status, reply_to_id, reply_preview, forward_from, is_pinned, has_media)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		accountID, chatID, msg.ID, nil, msg.SenderID, msg.SenderName,
		rawBytes, msg.Text, ts, editedAt,
		status, nullStr(msg.ReplyToID), nullStr(msg.ReplyPreview),
		nullStr(msg.ForwardFrom), boolToInt(msg.IsPinned), boolToInt(hasMedia))

	// Cache media references.
	for i, att := range msg.Attachments {
		e.cacheMediaRef(accountID, chatID, msg.ID, i, att)
	}

	return CachedMessage{
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
		HasMedia:     hasMedia,
	}
}

// InsertPendingMessage inserts a locally-created message (before server confirms).
func (e *Engine) InsertPendingMessage(accountID, chatID, localID, text, senderID, senderName string) CachedMessage {
	now := time.Now().UnixMilli()

	e.db.Exec(
		`INSERT INTO messages
		 (account_id, chat_id, msg_id, local_id, sender_id, sender_name,
		  content_text, timestamp, status, has_media)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		accountID, chatID, localID, localID, senderID, senderName,
		text, now, MsgStatusSending, 0)

	return CachedMessage{
		AccountID:   accountID,
		ChatID:      chatID,
		MsgID:       localID,
		LocalID:     localID,
		SenderID:    senderID,
		SenderName:  senderName,
		ContentText: text,
		Timestamp:   now,
		Status:      MsgStatusSending,
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

	e.db.Exec(
		`INSERT OR REPLACE INTO media
		 (account_id, chat_id, msg_id, seq, media_type, remote_ref, thumb_b64,
		  file_name, mime_type, file_size, download_state, last_accessed)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		accountID, chatID, msgID, seq, mediaType, att.ID, att.ThumbB64,
		att.Name, att.MimeType, att.Size, DownloadNone, time.Now().UnixMilli())
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
		return MsgStatusSent
	}
}

func nullStr(s string) sql.NullString {
	if s == "" {
		return sql.NullString{}
	}
	return sql.NullString{String: s, Valid: true}
}

func guessMediaType(mime, name string) int {
	if mime == "" {
		return MediaFile
	}
	switch {
	case mime == "image/gif":
		return MediaGIF
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
		result[i] = CachedMessage{
			AccountID:   accountID,
			ChatID:      chatID,
			MsgID:       m.ID,
			SenderID:    m.SenderID,
			SenderName:  m.SenderName,
			ContentText: m.Text,
			Timestamp:   m.Timestamp.UnixMilli(),
		}
	}
	return result, nil
}
