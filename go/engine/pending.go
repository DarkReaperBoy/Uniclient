package engine

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"uniclient/cores"
)

// PendingAction represents the type of outbound operation.
const (
	ActionSend    = "send"
	ActionEdit    = "edit"
	ActionDelete  = "delete"
	ActionReact   = "react"
	ActionForward = "forward"
)

// sendPayload is the serialized payload for a "send" action.
type sendPayload struct {
	Text      string `json:"text"`
	ReplyToID string `json:"reply_to_id,omitempty"`
}

// editPayload is the serialized payload for an "edit" action.
type editPayload struct {
	MsgID   string `json:"msg_id"`
	NewText string `json:"new_text"`
}

// deletePayload is the serialized payload for a "delete" action.
type deletePayload struct {
	MsgID string `json:"msg_id"`
}

// reactPayload is the serialized payload for a "react" action.
type reactPayload struct {
	MsgID string `json:"msg_id"`
	Emoji string `json:"emoji"`
}

// forwardPayload is the serialized payload for a "forward" action.
type forwardPayload struct {
	MsgID    string `json:"msg_id"`
	ToChatID string `json:"to_chat_id"`
}

// pendingItem represents a row in the pending table.
type pendingItem struct {
	ID         int64
	AccountID  string
	ChatID     string
	LocalID    string
	Action     string
	Payload    []byte
	Status     int
	RetryCount int
	ErrorMsg   string
	CreatedAt  int64
}

// generateLocalID creates a unique local message ID.
func generateLocalID() string {
	b := make([]byte, 8)
	rand.Read(b)
	return "local_" + hex.EncodeToString(b)
}

// Per-chat send locks ensure message ordering within a chat.
var (
	chatSendMu sync.Mutex
	chatSendLocks = make(map[string]*sync.Mutex)
)

func getChatLock(accountID, chatID string) *sync.Mutex {
	key := accountID + ":" + chatID
	chatSendMu.Lock()
	defer chatSendMu.Unlock()
	if m, ok := chatSendLocks[key]; ok {
		return m
	}
	m := &sync.Mutex{}
	chatSendLocks[key] = m
	return m
}

// SendMessage queues a message for sending through the pending queue.
// Returns the local_id for optimistic UI display.
func (e *Engine) SendMessage(accountID, chatID, text, replyToID string) (string, error) {
	log.Printf("[engine] SendMessage(%s, %s): text=%q replyToID=%q", accountID, chatID, text, replyToID)
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", fmt.Errorf("account %q not found", accountID)
	}

	localID := generateLocalID()
	now := time.Now().UnixMilli()

	payload, _ := json.Marshal(sendPayload{
		Text:      text,
		ReplyToID: replyToID,
	})

	// Write to pending table.
	_, err := e.db.Exec(
		`INSERT INTO pending (account_id, chat_id, local_id, action, payload, status, created_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		accountID, chatID, localID, ActionSend, payload, PendingQueued, now)
	if err != nil {
		return "", fmt.Errorf("insert pending: %w", err)
	}

	// Insert optimistic message into cache.
	var senderName string
	if acc.DisplayName != "" {
		senderName = acc.DisplayName
	}

	// Look up reply preview if replying.
	var replyPreview string
	if replyToID != "" {
		var sn, ct sql.NullString
		e.db.QueryRow(
			"SELECT sender_name, content_text FROM messages WHERE account_id = ? AND chat_id = ? AND msg_id = ?",
			accountID, chatID, replyToID).Scan(&sn, &ct)
		if sn.Valid && sn.String != "" {
			replyPreview = sn.String + ": " + ct.String
		} else if ct.Valid {
			replyPreview = ct.String
		}
	}
	cached := e.InsertPendingMessage(accountID, chatID, localID, text, "", senderName, replyToID)
	if replyPreview != "" {
		cached.ReplyPreview = replyPreview
		e.db.Exec("UPDATE messages SET reply_preview = ? WHERE account_id = ? AND chat_id = ? AND msg_id = ?",
			replyPreview, accountID, chatID, localID)
	}

	// Update chat preview.
	preview := text
	if len(preview) > 100 {
		preview = preview[:100]
	}
	e.updateChatLastMessage(accountID, chatID, localID, preview, senderName, now, true, MsgStatusSending, 0, "")

	// Emit message event.
	e.emitEvent(EventMsgReceived, accountID, MsgReceivedEvent{
		AccountID: accountID,
		ChatID:    chatID,
		Message:   cached,
	})

	// Process in background.
	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		e.processPendingItem(accountID, chatID, localID, ActionSend, payload)
	}()

	return localID, nil
}

// UploadFile sends a file from the local filesystem to a chat.
func (e *Engine) UploadFile(accountID, chatID, filePath, caption string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", fmt.Errorf("account %q not found", accountID)
	}
	if acc.Core == nil {
		return "", fmt.Errorf("account %q not connected", accountID)
	}

	f, err := os.Open(filePath)
	if err != nil {
		return "", fmt.Errorf("open file: %w", err)
	}
	defer f.Close()

	info, err := f.Stat()
	if err != nil {
		return "", fmt.Errorf("stat file: %w", err)
	}

	upload := cores.FileUpload{
		Name:     info.Name(),
		Size:     info.Size(),
		MimeType: detectMimeType(filePath),
		Reader:   f,
	}

	msg, err := acc.Core.UploadFile(chatID, upload, nil)
	if err != nil {
		return "", err
	}

	// Cache the sent message.
	if msg != nil {
		cached := e.cacheMessage(accountID, chatID, msg)
		e.emitEvent(EventMsgReceived, accountID, MsgReceivedEvent{
			AccountID: accountID,
			ChatID:    chatID,
			Message:   cached,
		})
		return msg.ID, nil
	}
	return "", nil
}

// detectMimeType guesses MIME type from file extension.
func detectMimeType(path string) string {
	ext := strings.ToLower(filepath.Ext(path))
	switch ext {
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".png":
		return "image/png"
	case ".gif":
		return "image/gif"
	case ".webp":
		return "image/webp"
	case ".mp4":
		return "video/mp4"
	case ".webm":
		return "video/webm"
	case ".mp3":
		return "audio/mpeg"
	case ".ogg":
		return "audio/ogg"
	case ".opus":
		return "audio/opus"
	case ".pdf":
		return "application/pdf"
	case ".zip":
		return "application/zip"
	case ".txt":
		return "text/plain"
	default:
		return "application/octet-stream"
	}
}

// EditMessage queues a message edit.
func (e *Engine) EditMessage(accountID, chatID, msgID, newText string) error {
	localID := generateLocalID()
	now := time.Now().UnixMilli()

	payload, _ := json.Marshal(editPayload{MsgID: msgID, NewText: newText})

	_, err := e.db.Exec(
		`INSERT INTO pending (account_id, chat_id, local_id, action, payload, status, created_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		accountID, chatID, localID, ActionEdit, payload, PendingQueued, now)
	if err != nil {
		return err
	}

	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		e.processPendingItem(accountID, chatID, localID, ActionEdit, payload)
	}()
	return nil
}

// DeleteMessage queues a message deletion.
func (e *Engine) DeleteMessage(accountID, chatID, msgID string) error {
	localID := generateLocalID()
	now := time.Now().UnixMilli()

	payload, _ := json.Marshal(deletePayload{MsgID: msgID})

	_, err := e.db.Exec(
		`INSERT INTO pending (account_id, chat_id, local_id, action, payload, status, created_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		accountID, chatID, localID, ActionDelete, payload, PendingQueued, now)
	if err != nil {
		return err
	}

	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		e.processPendingItem(accountID, chatID, localID, ActionDelete, payload)
	}()
	return nil
}

// ForwardMessage queues a message forward to another chat.
func (e *Engine) ForwardMessage(accountID, chatID, msgID, toChatID string) error {
	localID := generateLocalID()
	now := time.Now().UnixMilli()

	payload, _ := json.Marshal(forwardPayload{MsgID: msgID, ToChatID: toChatID})

	_, err := e.db.Exec(
		`INSERT INTO pending (account_id, chat_id, local_id, action, payload, status, created_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		accountID, chatID, localID, ActionForward, payload, PendingQueued, now)
	if err != nil {
		return err
	}

	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		e.processPendingItem(accountID, chatID, localID, ActionForward, payload)
	}()
	return nil
}

// ReactToMessage queues a reaction toggle on a message.
func (e *Engine) ReactToMessage(accountID, chatID, msgID, emoji string) error {
	localID := generateLocalID()
	now := time.Now().UnixMilli()

	payload, _ := json.Marshal(reactPayload{MsgID: msgID, Emoji: emoji})

	_, err := e.db.Exec(
		`INSERT INTO pending (account_id, chat_id, local_id, action, payload, status, created_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		accountID, chatID, localID, ActionReact, payload, PendingQueued, now)
	if err != nil {
		return err
	}

	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		e.processPendingItem(accountID, chatID, localID, ActionReact, payload)
	}()
	return nil
}

// PinMessage pins or unpins a message in a chat. On success, the cached
// message row's `is_pinned` flag is updated so UI context menus that read
// from the cache immediately reflect the new state without waiting for a
// server event round-trip.
func (e *Engine) PinMessage(accountID, chatID, msgID string, pinned bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %s not found", accountID)
	}
	var err error
	if pinned {
		err = acc.Core.PinMessage(chatID, msgID)
	} else {
		err = acc.Core.UnpinMessage(chatID, msgID)
	}
	if err == nil {
		flag := 0
		if pinned {
			flag = 1
		}
		e.db.Exec(
			"UPDATE messages SET is_pinned = ? WHERE account_id = ? AND chat_id = ? AND msg_id = ?",
			flag, accountID, chatID, msgID,
		)
	}
	return err
}

// processPendingItem executes a pending operation with retry logic.
func (e *Engine) processPendingItem(accountID, chatID, localID, action string, payload []byte) {
	// Acquire per-chat lock for ordering (sends only).
	if action == ActionSend || action == ActionForward {
		lock := getChatLock(accountID, chatID)
		lock.Lock()
		defer lock.Unlock()
	}

	// Mark as sending.
	e.db.Exec("UPDATE pending SET status = ? WHERE local_id = ?", PendingSending, localID)

	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		e.markPendingFailed(localID, "account not connected")
		if action == ActionSend {
			e.FailMessage(accountID, chatID, localID)
		}
		return
	}

	var err error
	maxRetries := 5
	retryDelays := []time.Duration{0, 2 * time.Second, 5 * time.Second, 15 * time.Second, 30 * time.Second}

	for attempt := 0; attempt <= maxRetries; attempt++ {
		if attempt > 0 {
			delay := retryDelays[attempt-1]
			if int(attempt-1) < len(retryDelays) {
				delay = retryDelays[attempt-1]
			} else {
				delay = 30 * time.Second
			}
			time.Sleep(delay)
		}

		err = e.executePending(acc, chatID, localID, action, payload)
		if err == nil {
			// Success — remove from pending.
			e.db.Exec("DELETE FROM pending WHERE local_id = ?", localID)
			return
		}

		// Check if retryable.
		if !isRetryable(err) {
			break
		}

		e.db.Exec(
			"UPDATE pending SET retry_count = retry_count + 1, error_msg = ?, last_attempt = ? WHERE local_id = ?",
			err.Error(), time.Now().UnixMilli(), localID)
	}

	// Permanently failed.
	e.markPendingFailed(localID, err.Error())
	if action == ActionSend {
		e.FailMessage(accountID, chatID, localID)
	}
}

// executePending dispatches the actual core call.
func (e *Engine) executePending(acc *Account, chatID, localID, action string, payload []byte) error {
	switch action {
	case ActionSend:
		var p sendPayload
		json.Unmarshal(payload, &p)

		msg := cores.OutgoingMessage{Text: p.Text, ReplyToID: p.ReplyToID}
		log.Printf("[engine] executePending SEND: chatID=%s replyToID=%q text=%q", chatID, p.ReplyToID, p.Text)

		var result *cores.Message
		var err error
		if p.ReplyToID != "" {
			log.Printf("[engine] executePending: calling ReplyToMessage(chatID=%s, replyTo=%s)", chatID, p.ReplyToID)
			result, err = acc.Core.ReplyToMessage(chatID, p.ReplyToID, msg)
		} else {
			result, err = acc.Core.SendMessage(chatID, msg)
		}
		if err != nil {
			return err
		}
		if result != nil {
			e.ConfirmMessage(acc.ID, chatID, localID, result.ID)
			rawBytes, _ := json.Marshal(result)
			e.db.Exec(
				`UPDATE messages SET content_raw = ? WHERE account_id = ? AND chat_id = ? AND msg_id = ?`,
				rawBytes, acc.ID, chatID, result.ID)
			if len(result.Extra) > 0 {
				e.emitEvent(EventMsgEdited, acc.ID, MsgEditedEvent{
					AccountID:  acc.ID,
					ChatID:     chatID,
					MsgID:      result.ID,
					NewText:    result.Text,
					ContentRaw: json.RawMessage(rawBytes),
				})
			}
		}
		return nil

	case ActionEdit:
		var p editPayload
		json.Unmarshal(payload, &p)
		_, err := acc.Core.EditMessage(chatID, p.MsgID, p.NewText)
		if err != nil {
			return err
		}
		// Update cache.
		e.db.Exec(
			"UPDATE messages SET content_text = ?, edited_at = ? WHERE account_id = ? AND chat_id = ? AND msg_id = ?",
			p.NewText, time.Now().UnixMilli(), acc.ID, chatID, p.MsgID)
		return nil

	case ActionDelete:
		var p deletePayload
		json.Unmarshal(payload, &p)
		err := acc.Core.DeleteMessage(chatID, p.MsgID)
		if err != nil {
			return err
		}
		e.db.Exec(
			"DELETE FROM messages WHERE account_id = ? AND chat_id = ? AND msg_id = ?",
			acc.ID, chatID, p.MsgID)
		return nil

	case ActionReact:
		var p reactPayload
		json.Unmarshal(payload, &p)
		return acc.Core.ReactToMessage(chatID, p.MsgID, p.Emoji)

	case ActionForward:
		var p forwardPayload
		json.Unmarshal(payload, &p)
		_, err := acc.Core.ForwardMessage(chatID, p.MsgID, p.ToChatID)
		return err

	default:
		return fmt.Errorf("unknown action: %s", action)
	}
}

func (e *Engine) markPendingFailed(localID, errMsg string) {
	e.db.Exec(
		"UPDATE pending SET status = ?, error_msg = ?, last_attempt = ? WHERE local_id = ?",
		PendingFailed, errMsg, time.Now().UnixMilli(), localID)
}

// RetryPending retries a specific failed pending operation.
func (e *Engine) RetryPending(localID string) error {
	var accountID, chatID, action string
	var payload []byte
	err := e.db.QueryRow(
		"SELECT account_id, chat_id, action, payload FROM pending WHERE local_id = ? AND status = ?",
		localID, PendingFailed).Scan(&accountID, &chatID, &action, &payload)
	if err != nil {
		return fmt.Errorf("pending item not found: %w", err)
	}

	// Reset status.
	e.db.Exec("UPDATE pending SET status = ?, error_msg = NULL WHERE local_id = ?",
		PendingQueued, localID)

	// Re-mark message as sending.
	if action == ActionSend {
		e.db.Exec(
			"UPDATE messages SET status = ? WHERE account_id = ? AND chat_id = ? AND msg_id = ?",
			MsgStatusSending, accountID, chatID, localID)
		e.emitEvent(EventMsgStatus, accountID, MsgStatusEvent{
			AccountID: accountID, ChatID: chatID, MsgID: localID, Status: MsgStatusSending,
		})
	}

	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		e.processPendingItem(accountID, chatID, localID, action, payload)
	}()
	return nil
}

// resumePending retries all queued/in-flight items from a previous crash.
func (e *Engine) resumePending() {
	rows, err := e.db.Query(
		`SELECT local_id, account_id, chat_id, action, payload
		 FROM pending WHERE status IN (?, ?) ORDER BY created_at`,
		PendingQueued, PendingSending)
	if err != nil {
		return
	}
	defer rows.Close()

	var items []pendingItem
	for rows.Next() {
		var item pendingItem
		if err := rows.Scan(&item.LocalID, &item.AccountID, &item.ChatID, &item.Action, &item.Payload); err != nil {
			continue
		}
		items = append(items, item)
	}

	for _, item := range items {
		item := item
		e.wg.Add(1)
		go func() {
			defer e.wg.Done()
			// Wait a bit for cores to connect before retrying.
			time.Sleep(3 * time.Second)
			e.processPendingItem(item.AccountID, item.ChatID, item.LocalID, item.Action, item.Payload)
		}()
	}
}

// isRetryable returns true for transient errors that warrant a retry.
func isRetryable(err error) bool {
	return errors.Is(err, cores.ErrNetwork) ||
		errors.Is(err, cores.ErrTimeout) ||
		errors.Is(err, cores.ErrRateLimit) ||
		errors.Is(err, cores.ErrDisconnected)
}
