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
	ActionSend        = "send"
	ActionEdit        = "edit"
	ActionDelete      = "delete"
	ActionReact       = "react"
	ActionForward     = "forward"
	ActionSendContact   = "send_contact"
	ActionResendAsOwn   = "resend_as_own"
	ActionResendAlbum   = "resend_album"
)

// sendPayload is the serialized payload for a "send" action.
type sendPayload struct {
	Text            string             `json:"text"`
	ReplyToID       string             `json:"reply_to_id,omitempty"`
	Entities        []cores.TextEntity `json:"entities,omitempty"`
	Silent          bool               `json:"silent,omitempty"`
	ScheduleDate    int64              `json:"schedule_date,omitempty"`
	TopicRootID     string             `json:"topic_root_id,omitempty"`
	WebPageUrl      string             `json:"web_page_url,omitempty"`
	ForceLargeMedia bool               `json:"force_large_media,omitempty"`
	ForceSmallMedia bool               `json:"force_small_media,omitempty"`
	InvertMedia     bool               `json:"invert_media,omitempty"`
	WebPageOptional bool               `json:"web_page_optional,omitempty"`
}

type sendContactPayload struct {
	Phone     string `json:"phone"`
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
	UserID    string `json:"user_id,omitempty"`
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
	MsgID        string `json:"msg_id"`
	ToChatID     string `json:"to_chat_id"`
	DropAuthor   bool   `json:"drop_author,omitempty"`
	DropCaptions bool   `json:"drop_captions,omitempty"`
	Silent       bool   `json:"silent,omitempty"`
	ScheduleDate int64  `json:"schedule_date,omitempty"`
}

// resendAsOwnPayload is the serialized payload for a "resend_as_own" action.
type resendAsOwnPayload struct {
	MsgID        string `json:"msg_id"`
	SourceChatID string `json:"source_chat_id"`
	ToChatID     string `json:"to_chat_id"`
	Silent       bool   `json:"silent,omitempty"`
	ScheduleDate int64  `json:"schedule_date,omitempty"`
}

// resendAlbumPayload is the serialized payload for a "resend_album" action.
type resendAlbumPayload struct {
	MsgIDs       []string `json:"msg_ids"`
	SourceChatID string   `json:"source_chat_id"`
	ToChatID     string   `json:"to_chat_id"`
	Silent       bool     `json:"silent,omitempty"`
	ScheduleDate int64    `json:"schedule_date,omitempty"`
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
func (e *Engine) SendMessage(accountID, chatID, text, replyToID string, entities []cores.TextEntity, silent bool, scheduleDate int64, topicRootID string, webPageUrl string, forceLargeMedia bool, forceSmallMedia bool, invertMedia bool, webPageOptional bool) (string, error) {
	log.Printf("[engine] SendMessage(%s, %s): text=%q replyToID=%q silent=%v scheduleDate=%d topicRootID=%q", accountID, chatID, text, replyToID, silent, scheduleDate, topicRootID)
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", fmt.Errorf("account %q not found", accountID)
	}

	localID := generateLocalID()
	now := time.Now().UnixMilli()

	payload, _ := json.Marshal(sendPayload{
		Text:            text,
		ReplyToID:       replyToID,
		Entities:        entities,
		Silent:          silent,
		ScheduleDate:    scheduleDate,
		TopicRootID:     topicRootID,
		WebPageUrl:      webPageUrl,
		ForceLargeMedia: forceLargeMedia,
		ForceSmallMedia: forceSmallMedia,
		InvertMedia:     invertMedia,
		WebPageOptional: webPageOptional,
	})

	// Write to pending table.
	_, err := e.db.Exec(
		`INSERT INTO pending (account_id, chat_id, local_id, action, payload, status, created_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		accountID, chatID, localID, ActionSend, payload, PendingQueued, now)
	if err != nil {
		return "", fmt.Errorf("insert pending: %w", err)
	}

	if scheduleDate <= 0 {
		// Insert optimistic message into cache (not for scheduled messages).
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
			if ct.Valid && ct.String != "" {
				preview := ct.String
				if len(preview) > 100 {
					preview = preview[:100]
				}
				if sn.Valid && sn.String != "" {
					replyPreview = sn.String + "\n" + preview
				} else {
					replyPreview = preview
				}
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
	}

	// Process in background.
	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		e.processPendingItem(accountID, chatID, localID, ActionSend, payload)
	}()

	return localID, nil
}

func (e *Engine) SendContact(accountID, toChatID, phone, firstName, lastName, userID string) (string, error) {
	log.Printf("[engine] SendContact(%s, %s): phone=%q name=%q %q", accountID, toChatID, phone, firstName, lastName)
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", fmt.Errorf("account %q not found", accountID)
	}

	type sendContacter interface {
		SendContact(chatID, phone, firstName, lastName, userID string) (*cores.Message, error)
	}
	sc, ok := acc.Core.(sendContacter)
	if !ok {
		return "", fmt.Errorf("core %q does not support SendContact", acc.Platform)
	}

	result, err := sc.SendContact(toChatID, phone, firstName, lastName, userID)
	if err != nil {
		return "", fmt.Errorf("send contact: %w", err)
	}
	if result != nil {
		return result.ID, nil
	}
	return "", nil
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
func (e *Engine) ForwardMessage(accountID, chatID, msgID, toChatID string, dropAuthor, dropCaptions, silent bool, scheduleDate int64) error {
	localID := generateLocalID()
	now := time.Now().UnixMilli()

	payload, _ := json.Marshal(forwardPayload{
		MsgID: msgID, ToChatID: toChatID,
		DropAuthor: dropAuthor, DropCaptions: dropCaptions,
		Silent: silent, ScheduleDate: scheduleDate,
	})

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

// ResendAsOwn downloads a source message's content and resends it as a new
// message (no forward header) to toChatID. Used by AyuForward for restricted
// content that can't be natively forwarded.
func (e *Engine) ResendAsOwn(accountID, sourceChatID, msgID, toChatID string, silent bool, scheduleDate int64) error {
	localID := generateLocalID()
	now := time.Now().UnixMilli()

	payload, _ := json.Marshal(resendAsOwnPayload{
		MsgID: msgID, SourceChatID: sourceChatID, ToChatID: toChatID,
		Silent: silent, ScheduleDate: scheduleDate,
	})

	_, err := e.db.Exec(
		`INSERT INTO pending (account_id, chat_id, local_id, action, payload, status, created_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		accountID, toChatID, localID, ActionResendAsOwn, payload, PendingQueued, now)
	if err != nil {
		return err
	}

	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		e.processPendingItem(accountID, toChatID, localID, ActionResendAsOwn, payload)
	}()
	return nil
}

// ResendAlbumAsOwn downloads a group of messages (album) and resends them as
// a single album with no forward header. Used by AyuForward for grouped media.
func (e *Engine) ResendAlbumAsOwn(accountID, sourceChatID string, msgIDs []string, toChatID string, silent bool, scheduleDate int64) error {
	localID := generateLocalID()
	now := time.Now().UnixMilli()

	payload, _ := json.Marshal(resendAlbumPayload{
		MsgIDs: msgIDs, SourceChatID: sourceChatID, ToChatID: toChatID,
		Silent: silent, ScheduleDate: scheduleDate,
	})

	_, err := e.db.Exec(
		`INSERT INTO pending (account_id, chat_id, local_id, action, payload, status, created_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		accountID, toChatID, localID, ActionResendAlbum, payload, PendingQueued, now)
	if err != nil {
		return err
	}

	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		e.processPendingItem(accountID, toChatID, localID, ActionResendAlbum, payload)
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
	e.ghostAutoRead(accountID, chatID, msgID)
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
	if action == ActionSend || action == ActionForward || action == ActionResendAsOwn || action == ActionResendAlbum {
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

		extra := map[string]interface{}{}
		if p.Silent {
			extra["silent"] = true
		}
		if p.ScheduleDate > 0 {
			extra["schedule_date"] = p.ScheduleDate
		}
		if p.TopicRootID != "" {
			extra["topic_root_id"] = p.TopicRootID
		}
		if p.WebPageUrl != "" {
			extra["web_page_url"] = p.WebPageUrl
		}
		if p.ForceLargeMedia {
			extra["force_large_media"] = true
		}
		if p.ForceSmallMedia {
			extra["force_small_media"] = true
		}
		if p.InvertMedia {
			extra["invert_media"] = true
		}
		if p.WebPageOptional {
			extra["web_page_optional"] = true
		}
		msg := cores.OutgoingMessage{Text: p.Text, ReplyToID: p.ReplyToID, Entities: p.Entities, Extra: extra}
		log.Printf("[engine] executePending SEND: chatID=%s replyToID=%q text=%q silent=%v scheduleDate=%d topicRootID=%q", chatID, p.ReplyToID, p.Text, p.Silent, p.ScheduleDate, p.TopicRootID)

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
			if len(result.Entities) > 0 {
				richBytes, _ := json.Marshal(result.Entities)
				e.db.Exec(
					`UPDATE messages SET content_rich = ? WHERE account_id = ? AND chat_id = ? AND msg_id = ?`,
					richBytes, acc.ID, chatID, result.ID)
			}
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
		if fwd, ok := acc.Core.(cores.ForwardWithOptionsSupporter); ok && (p.DropAuthor || p.DropCaptions || p.Silent || p.ScheduleDate > 0) {
			_, err := fwd.ForwardMessageWithOptions(chatID, p.MsgID, p.ToChatID, cores.ForwardOptions{
				DropAuthor: p.DropAuthor, DropCaptions: p.DropCaptions,
				Silent: p.Silent, ScheduleDate: p.ScheduleDate,
			})
			return err
		}
		_, err := acc.Core.ForwardMessage(chatID, p.MsgID, p.ToChatID)
		return err

	case ActionResendAsOwn:
		var p resendAsOwnPayload
		json.Unmarshal(payload, &p)
		return e.executeResendAsOwn(acc, p)

	case ActionResendAlbum:
		var p resendAlbumPayload
		json.Unmarshal(payload, &p)
		return e.executeResendAlbum(acc, p)

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

// isMediaDownloadable returns true if the media type can be downloaded and re-sent.
// Excludes webpages, polls, games, invoices, locations, contacts (matching spec §53.5).
func isMediaDownloadable(mt int) bool {
	switch mt {
	case MediaPoll, MediaLocation, MediaContact, MediaInvoice:
		return false
	default:
		return true
	}
}

// executeResendAsOwn downloads the source message's media and sends it as a
// new message to the target chat with no forward header.
// Implements spec §53.5: media type filtering, sticker bypass, voice/video note
// detection, download timeouts, incomplete download detection, silent/schedule
// propagation.
func (e *Engine) executeResendAsOwn(acc *Account, p resendAsOwnPayload) error {
	var contentText sql.NullString
	var contentRaw []byte
	err := e.db.QueryRow(
		`SELECT content_text, content_raw FROM messages
		 WHERE account_id = ? AND chat_id = ? AND msg_id = ?`,
		acc.ID, p.SourceChatID, p.MsgID,
	).Scan(&contentText, &contentRaw)
	if err != nil {
		return fmt.Errorf("source message not found: %w", err)
	}

	text := contentText.String

	var remoteRef, fileName, mimeType, extraStr sql.NullString
	var mediaType int
	var expectedSize int64
	var width, height, duration sql.NullInt64
	hasMedia := false
	err = e.db.QueryRow(
		`SELECT media_type, remote_ref, file_name, mime_type, extra, file_size,
		        width, height, duration
		 FROM media
		 WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = 0`,
		acc.ID, p.SourceChatID, p.MsgID,
	).Scan(&mediaType, &remoteRef, &fileName, &mimeType, &extraStr,
		&expectedSize, &width, &height, &duration)
	if err == nil && remoteRef.String != "" {
		hasMedia = true
	}

	if hasMedia && !isMediaDownloadable(mediaType) {
		hasMedia = false
	}

	if hasMedia && mediaType == MediaSticker {
		sentMsg, err := acc.Core.SendSticker(p.ToChatID, remoteRef.String)
		if err != nil {
			log.Printf("resend sticker fallback to download: %v", err)
		} else {
			if sentMsg != nil {
				e.cacheMessage(acc.ID, p.ToChatID, sentMsg)
			}
			if text != "" && (sentMsg == nil || sentMsg.Text != text) {
				e.resendText(acc, p.ToChatID, text, p.Silent, p.ScheduleDate)
			}
			return nil
		}
	}

	if hasMedia {
		tmpDir := filepath.Join(os.TempDir(), "uniclient_resend")
		os.MkdirAll(tmpDir, 0o755)
		ext := filepath.Ext(fileName.String)
		if ext == "" {
			ext = ".bin"
		}
		tmpPath := filepath.Join(tmpDir, p.MsgID+ext)
		defer os.Remove(tmpPath)

		ref := cores.FileRef{
			ID:       remoteRef.String,
			Name:     fileName.String,
			MimeType: mimeType.String,
			Extra:    extraStr.String,
			Size:     expectedSize,
		}
		if err := acc.Core.DownloadFile(ref, tmpPath, nil); err != nil {
			log.Printf("resend download failed (skipping media): %v", err)
			if text != "" {
				return e.resendText(acc, p.ToChatID, text, p.Silent, p.ScheduleDate)
			}
			return nil
		}

		info, err := os.Stat(tmpPath)
		if err != nil || (expectedSize > 0 && info.Size() < expectedSize) {
			log.Printf("resend incomplete download (expected %d, got %d), skipping media",
				expectedSize, info.Size())
			if text != "" {
				return e.resendText(acc, p.ToChatID, text, p.Silent, p.ScheduleDate)
			}
			return nil
		}

		f, err := os.Open(tmpPath)
		if err != nil {
			log.Printf("resend open failed: %v", err)
			if text != "" {
				return e.resendText(acc, p.ToChatID, text, p.Silent, p.ScheduleDate)
			}
			return nil
		}
		defer f.Close()

		upload := cores.FileUpload{
			Name:     fileName.String,
			Size:     info.Size(),
			MimeType: mimeType.String,
			Reader:   f,
		}

		isVoice := mediaType == MediaVoice
		isVideoNote := mediaType == MediaVideoNote

		if uploader, ok := acc.Core.(cores.UploadWithOptionsSupporter); ok {
			opts := cores.UploadOptions{
				Caption:      text,
				Silent:       p.Silent,
				ScheduleDate: p.ScheduleDate,
				IsVoice:      isVoice,
				IsVideoNote:  isVideoNote,
			}
			if width.Valid {
				opts.Width = int(width.Int64)
			}
			if height.Valid {
				opts.Height = int(height.Int64)
			}
			if duration.Valid {
				opts.Duration = int(duration.Int64)
			}
			sentMsg, err := uploader.UploadFileWithOptions(p.ToChatID, upload, opts, nil)
			if err != nil {
				return fmt.Errorf("upload resend: %w", err)
			}
			if sentMsg != nil {
				e.cacheMessage(acc.ID, p.ToChatID, sentMsg)
			}
			return nil
		}

		sentMsg, err := acc.Core.UploadFile(p.ToChatID, upload, nil)
		if err != nil {
			return fmt.Errorf("upload resend: %w", err)
		}
		if sentMsg != nil && text != "" && sentMsg.Text != text {
			e.resendText(acc, p.ToChatID, text, p.Silent, p.ScheduleDate)
		}
		if sentMsg != nil {
			e.cacheMessage(acc.ID, p.ToChatID, sentMsg)
		}
	} else if text != "" {
		return e.resendText(acc, p.ToChatID, text, p.Silent, p.ScheduleDate)
	} else {
		return fmt.Errorf("nothing to resend: no text or media")
	}
	return nil
}

// resendText sends a text message with silent/schedule options.
func (e *Engine) resendText(acc *Account, chatID, text string, silent bool, scheduleDate int64) error {
	extra := map[string]interface{}{}
	if silent {
		extra["silent"] = true
	}
	if scheduleDate > 0 {
		extra["schedule_date"] = scheduleDate
	}
	outMsg := cores.OutgoingMessage{Text: text, Extra: extra}
	sentMsg, err := acc.Core.SendMessage(chatID, outMsg)
	if err != nil {
		return err
	}
	if sentMsg != nil {
		e.cacheMessage(acc.ID, chatID, sentMsg)
	}
	return nil
}

// executeResendAlbum downloads all messages in an album group and sends them
// as a single album to the target chat. Falls back to individual sends if
// the core doesn't support album sending.
func (e *Engine) executeResendAlbum(acc *Account, p resendAlbumPayload) error {
	albumSender, hasAlbumSupport := acc.Core.(cores.MediaAlbumSender)

	tmpDir := filepath.Join(os.TempDir(), "uniclient_resend")
	os.MkdirAll(tmpDir, 0o755)

	type downloadedItem struct {
		tmpPath  string
		fileName string
		mimeType string
		size     int64
		text     string
		isPhoto  bool
	}

	var items []downloadedItem
	var textOnly []string

	for _, msgID := range p.MsgIDs {
		var contentText sql.NullString
		err := e.db.QueryRow(
			`SELECT content_text FROM messages WHERE account_id = ? AND chat_id = ? AND msg_id = ?`,
			acc.ID, p.SourceChatID, msgID,
		).Scan(&contentText)
		if err != nil {
			log.Printf("resend album: source message %s not found, skipping", msgID)
			continue
		}

		var remoteRef, fName, mime, extra sql.NullString
		var mt int
		var expSize int64
		err = e.db.QueryRow(
			`SELECT media_type, remote_ref, file_name, mime_type, extra, file_size
			 FROM media WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = 0`,
			acc.ID, p.SourceChatID, msgID,
		).Scan(&mt, &remoteRef, &fName, &mime, &extra, &expSize)

		if err != nil || remoteRef.String == "" || !isMediaDownloadable(mt) {
			if contentText.String != "" {
				textOnly = append(textOnly, contentText.String)
			}
			continue
		}

		ext := filepath.Ext(fName.String)
		if ext == "" {
			ext = ".bin"
		}
		tmpPath := filepath.Join(tmpDir, msgID+ext)

		ref := cores.FileRef{
			ID: remoteRef.String, Name: fName.String,
			MimeType: mime.String, Extra: extra.String, Size: expSize,
		}
		if err := acc.Core.DownloadFile(ref, tmpPath, nil); err != nil {
			log.Printf("resend album: download %s failed, skipping: %v", msgID, err)
			continue
		}

		info, err := os.Stat(tmpPath)
		if err != nil || (expSize > 0 && info.Size() < expSize) {
			log.Printf("resend album: incomplete download for %s, skipping", msgID)
			os.Remove(tmpPath)
			continue
		}

		isPhoto := mt == MediaImage
		items = append(items, downloadedItem{
			tmpPath: tmpPath, fileName: fName.String,
			mimeType: mime.String, size: info.Size(),
			text: contentText.String, isPhoto: isPhoto,
		})
	}
	defer func() {
		for _, item := range items {
			os.Remove(item.tmpPath)
		}
	}()

	if len(items) == 0 {
		for _, t := range textOnly {
			e.resendText(acc, p.ToChatID, t, p.Silent, p.ScheduleDate)
		}
		return nil
	}

	if hasAlbumSupport && len(items) > 1 {
		var albumItems []cores.AlbumItem
		for _, item := range items {
			f, err := os.Open(item.tmpPath)
			if err != nil {
				log.Printf("resend album: open %s failed, skipping", item.tmpPath)
				continue
			}
			albumItems = append(albumItems, cores.AlbumItem{
				Upload: cores.FileUpload{
					Name: item.fileName, Size: item.size,
					MimeType: item.mimeType, Reader: f,
				},
				Caption: item.text,
				IsPhoto: item.isPhoto,
			})
		}
		msgs, err := albumSender.SendMediaAlbum(p.ToChatID, albumItems, p.Silent, p.ScheduleDate)
		for _, item := range albumItems {
			if rc, ok := item.Upload.Reader.(interface{ Close() error }); ok {
				rc.Close()
			}
		}
		if err != nil {
			log.Printf("resend album: SendMediaAlbum failed, falling back to individual: %v", err)
		} else {
			for _, m := range msgs {
				if m != nil {
					e.cacheMessage(acc.ID, p.ToChatID, m)
				}
			}
			for _, t := range textOnly {
				e.resendText(acc, p.ToChatID, t, p.Silent, p.ScheduleDate)
			}
			return nil
		}
	}

	for _, item := range items {
		f, err := os.Open(item.tmpPath)
		if err != nil {
			continue
		}
		upload := cores.FileUpload{
			Name: item.fileName, Size: item.size,
			MimeType: item.mimeType, Reader: f,
		}
		sentMsg, err := acc.Core.UploadFile(p.ToChatID, upload, nil)
		f.Close()
		if err != nil {
			log.Printf("resend album item: upload failed: %v", err)
			continue
		}
		if sentMsg != nil {
			e.cacheMessage(acc.ID, p.ToChatID, sentMsg)
		}
	}
	for _, t := range textOnly {
		e.resendText(acc, p.ToChatID, t, p.Silent, p.ScheduleDate)
	}
	return nil
}

// isRetryable returns true for transient errors that warrant a retry.
func isRetryable(err error) bool {
	return errors.Is(err, cores.ErrNetwork) ||
		errors.Is(err, cores.ErrTimeout) ||
		errors.Is(err, cores.ErrRateLimit) ||
		errors.Is(err, cores.ErrDisconnected)
}
