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
	"uniclient/utils"
)

const (
	ActionSend         = "send"
	ActionEdit         = "edit"
	ActionDelete       = "delete"
	ActionReact        = "react"
	ActionForward      = "forward"
	ActionForwardBatch = "forward_batch"
	ActionSendContact  = "send_contact"
	ActionResendAsOwn  = "resend_as_own"
	ActionResendAlbum  = "resend_album"
)

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
	NoWebpage       bool               `json:"no_webpage,omitempty"`
}

type editPayload struct {
	MsgID        string `json:"msg_id"`
	NewText      string `json:"new_text"`
	EntitiesJSON string `json:"entities_json,omitempty"`
}

type deletePayload struct {
	MsgID  string `json:"msg_id"`
	Revoke bool   `json:"revoke"`
}

type reactPayload struct {
	MsgID  string   `json:"msg_id"`
	Emoji  string   `json:"emoji,omitempty"`
	Emojis []string `json:"emojis,omitempty"`
}

type forwardPayload struct {
	MsgID        string `json:"msg_id"`
	ToChatID     string `json:"to_chat_id"`
	DropAuthor   bool   `json:"drop_author,omitempty"`
	DropCaptions bool   `json:"drop_captions,omitempty"`
	Silent       bool   `json:"silent,omitempty"`
	ScheduleDate int64  `json:"schedule_date,omitempty"`
}

type forwardBatchPayload struct {
	MsgIDs       []string `json:"msg_ids"`
	ToChatID     string   `json:"to_chat_id"`
	DropAuthor   bool     `json:"drop_author,omitempty"`
	DropCaptions bool     `json:"drop_captions,omitempty"`
	Silent       bool     `json:"silent,omitempty"`
	ScheduleDate int64    `json:"schedule_date,omitempty"`
}

type resendAsOwnPayload struct {
	MsgID        string `json:"msg_id"`
	SourceChatID string `json:"source_chat_id"`
	ToChatID     string `json:"to_chat_id"`
	Silent       bool   `json:"silent,omitempty"`
	ScheduleDate int64  `json:"schedule_date,omitempty"`
	DropCaptions bool   `json:"drop_captions,omitempty"`
}

type resendAlbumPayload struct {
	MsgIDs       []string `json:"msg_ids"`
	SourceChatID string   `json:"source_chat_id"`
	ToChatID     string   `json:"to_chat_id"`
	Silent       bool     `json:"silent,omitempty"`
	ScheduleDate int64    `json:"schedule_date,omitempty"`
	DropCaptions bool     `json:"drop_captions,omitempty"`
}

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

func generateLocalID() string {
	b := make([]byte, 8)
	rand.Read(b)
	return "local_" + hex.EncodeToString(b)
}

var (
	chatSendMu    sync.Mutex
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

func (e *Engine) SendMessage(accountID, chatID, text, replyToID string, entities []cores.TextEntity, silent bool, scheduleDate int64, topicRootID string, webPageUrl string, forceLargeMedia bool, forceSmallMedia bool, invertMedia bool, webPageOptional bool, noWebpage bool) (string, error) {
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
		NoWebpage:       noWebpage,
	})

	_, err := e.db.Exec(
		`INSERT INTO pending (account_id, chat_id, local_id, action, payload, status, created_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		accountID, chatID, localID, ActionSend, payload, PendingQueued, now)
	if err != nil {
		return "", fmt.Errorf("insert pending: %w", err)
	}

	if scheduleDate <= 0 {
		var senderName string
		if acc.DisplayName != "" {
			senderName = acc.DisplayName
		}

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

		preview := text
		if len(preview) > 100 {
			preview = preview[:100]
		}
		e.updateChatLastMessage(accountID, chatID, localID, preview, senderName, now, true, MsgStatusSending, 0, "")

		e.emitEvent(EventMsgReceived, accountID, MsgReceivedEvent{
			AccountID: accountID,
			ChatID:    chatID,
			Message:   cached,
		})
	}

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

func (e *Engine) UploadFile(accountID, chatID, filePath, caption string) (string, error) {
	return e.UploadFileEx(accountID, chatID, filePath, cores.UploadOptions{Caption: caption})
}

func (e *Engine) SendMediaAlbumFromPaths(accountID, chatID string, paths []string, caption string, silent bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	if len(paths) == 0 {
		return fmt.Errorf("no files to send")
	}

	if len(paths) == 1 {
		_, err := e.UploadFileEx(accountID, chatID, paths[0], cores.UploadOptions{Caption: caption, Silent: silent})
		return err
	}

	sender, hasAlbum := acc.Core.(cores.MediaAlbumSender)
	if !hasAlbum {
		var firstErr error
		for i, p := range paths {
			itemCaption := ""
			if i == 0 {
				itemCaption = caption
			}
			if _, err := e.UploadFileEx(accountID, chatID, p, cores.UploadOptions{Caption: itemCaption, Silent: silent}); err != nil && firstErr == nil {
				firstErr = err
			}
		}
		return firstErr
	}

	var files []*os.File
	defer func() {
		for _, f := range files {
			f.Close()
		}
	}()
	var items []cores.AlbumItem
	for i, p := range paths {
		f, err := os.Open(p)
		if err != nil {
			return fmt.Errorf("open %s: %w", p, err)
		}
		files = append(files, f)
		info, err := f.Stat()
		if err != nil {
			return fmt.Errorf("stat %s: %w", p, err)
		}
		mime := detectMimeType(p)
		itemCaption := ""
		if i == 0 {
			itemCaption = caption
		}
		items = append(items, cores.AlbumItem{
			Upload: cores.FileUpload{
				Name:     filepath.Base(p),
				Size:     info.Size(),
				MimeType: mime,
				Reader:   f,
			},
			Caption: itemCaption,
			IsPhoto: guessMediaType(mime, filepath.Base(p)) == MediaImage,
		})
	}

	msgs, err := sender.SendMediaAlbum(chatID, items, silent, 0)
	if err != nil {
		return err
	}
	for _, m := range msgs {
		if m != nil {
			cached := e.cacheMessage(accountID, chatID, m)
			e.emitEvent(EventMsgReceived, accountID, MsgReceivedEvent{
				AccountID: accountID,
				ChatID:    chatID,
				Message:   cached,
			})
		}
	}
	return nil
}

func (e *Engine) UploadFileEx(accountID, chatID, filePath string, opts cores.UploadOptions) (string, error) {
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

	var msg *cores.Message
	if sup, ok := acc.Core.(cores.UploadWithOptionsSupporter); ok {
		msg, err = sup.UploadFileWithOptions(chatID, upload, opts, nil)
	} else {
		msg, err = acc.Core.UploadFile(chatID, upload, nil)
	}
	if err != nil {
		return "", err
	}

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

func (e *Engine) EditMessage(accountID, chatID, msgID, newText, entitiesJSON string) error {
	localID := generateLocalID()
	now := time.Now().UnixMilli()

	payload, _ := json.Marshal(editPayload{MsgID: msgID, NewText: newText, EntitiesJSON: entitiesJSON})

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

func (e *Engine) DeleteMessage(accountID, chatID, msgID string, revoke bool) error {
	localID := generateLocalID()
	now := time.Now().UnixMilli()

	payload, _ := json.Marshal(deletePayload{MsgID: msgID, Revoke: revoke})

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

func (e *Engine) ForwardMessages(accountID, chatID string, msgIDs []string, toChatID string, dropAuthor, dropCaptions, silent bool, scheduleDate int64) error {
	if len(msgIDs) == 0 {
		return nil
	}
	localID := generateLocalID()
	now := time.Now().UnixMilli()

	payload, _ := json.Marshal(forwardBatchPayload{
		MsgIDs: msgIDs, ToChatID: toChatID,
		DropAuthor: dropAuthor, DropCaptions: dropCaptions,
		Silent: silent, ScheduleDate: scheduleDate,
	})

	_, err := e.db.Exec(
		`INSERT INTO pending (account_id, chat_id, local_id, action, payload, status, created_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		accountID, chatID, localID, ActionForwardBatch, payload, PendingQueued, now)
	if err != nil {
		return err
	}

	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		e.processPendingItem(accountID, chatID, localID, ActionForwardBatch, payload)
	}()
	return nil
}

func (e *Engine) ResendAsOwn(accountID, sourceChatID, msgID, toChatID string, silent bool, scheduleDate int64, dropCaptions bool) error {
	localID := generateLocalID()
	now := time.Now().UnixMilli()

	payload, _ := json.Marshal(resendAsOwnPayload{
		MsgID: msgID, SourceChatID: sourceChatID, ToChatID: toChatID,
		Silent: silent, ScheduleDate: scheduleDate, DropCaptions: dropCaptions,
	})

	_, err := e.db.Exec(
		`INSERT INTO pending (account_id, chat_id, local_id, action, payload, status, created_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		accountID, toChatID, localID, ActionResendAsOwn, payload, PendingQueued, now)
	if err != nil {
		return err
	}

	e.wg.Add(1)
	defer e.wg.Done()
	return e.processPendingItem(accountID, toChatID, localID, ActionResendAsOwn, payload)
}

func (e *Engine) ResendAlbumAsOwn(accountID, sourceChatID string, msgIDs []string, toChatID string, silent bool, scheduleDate int64, dropCaptions bool) error {
	localID := generateLocalID()
	now := time.Now().UnixMilli()

	payload, _ := json.Marshal(resendAlbumPayload{
		MsgIDs: msgIDs, SourceChatID: sourceChatID, ToChatID: toChatID,
		Silent: silent, ScheduleDate: scheduleDate, DropCaptions: dropCaptions,
	})

	_, err := e.db.Exec(
		`INSERT INTO pending (account_id, chat_id, local_id, action, payload, status, created_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		accountID, toChatID, localID, ActionResendAlbum, payload, PendingQueued, now)
	if err != nil {
		return err
	}

	e.wg.Add(1)
	defer e.wg.Done()
	return e.processPendingItem(accountID, toChatID, localID, ActionResendAlbum, payload)
}

func (e *Engine) PreloadResendMedia(accountID, sourceChatID string, msgIDs []string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not connected", accountID)
	}

	e.wg.Add(1)
	defer e.wg.Done()

	tmpDir, err := resendTmpDir()
	if err != nil {
		return fmt.Errorf("resend dir: %w", err)
	}

	for _, msgID := range msgIDs {
		var remoteRef, fileName, mimeType, extraStr sql.NullString
		var mediaType int
		var expectedSize int64
		err := e.db.QueryRow(
			`SELECT media_type, remote_ref, file_name, mime_type, extra, file_size
                         FROM media
                         WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = 0`,
			acc.ID, sourceChatID, msgID,
		).Scan(&mediaType, &remoteRef, &fileName, &mimeType, &extraStr, &expectedSize)
		if err != nil || remoteRef.String == "" {
			continue
		}
		if !isMediaDownloadable(mediaType) {
			continue
		}

		ext := filepath.Ext(fileName.String)
		if ext == "" {
			ext = ".bin"
		}
		tmpPath := filepath.Join(tmpDir, safePathSegment(msgID)+ext)

		if info, statErr := os.Stat(tmpPath); statErr == nil {
			if expectedSize <= 0 || info.Size() >= expectedSize {
				continue
			}
			os.Remove(tmpPath)
		}

		ref := cores.FileRef{
			ID:       remoteRef.String,
			Name:     fileName.String,
			MimeType: mimeType.String,
			Extra:    extraStr.String,
			Size:     expectedSize,
		}
		if err := acc.Core.DownloadFile(ref, tmpPath, nil); err != nil {
			log.Printf("preload resend media: download %s failed (non-fatal): %v", msgID, err)
			continue
		}
	}
	return nil
}

func (e *Engine) ReactToMessageList(accountID, chatID, msgID string, emojis []string) error {
	localID := generateLocalID()
	now := time.Now().UnixMilli()

	payload, _ := json.Marshal(reactPayload{MsgID: msgID, Emojis: emojis})

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

func (e *Engine) processPendingItem(accountID, chatID, localID, action string, payload []byte) error {
	if action == ActionSend || action == ActionForward || action == ActionForwardBatch || action == ActionResendAsOwn || action == ActionResendAlbum {
		lock := getChatLock(accountID, chatID)
		lock.Lock()
		defer lock.Unlock()
	}

	e.db.Exec("UPDATE pending SET status = ? WHERE local_id = ?", PendingSending, localID)

	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		e.markPendingFailed(localID, "account not connected")
		if action == ActionSend {
			e.FailMessage(accountID, chatID, localID)
		}
		return fmt.Errorf("account %q not connected", accountID)
	}

	var err error
	maxRetries := 5
	retryDelays := []time.Duration{0, 2 * time.Second, 5 * time.Second, 15 * time.Second, 30 * time.Second}

	for attempt := 0; attempt <= maxRetries; attempt++ {
		if attempt > 0 {
			var delay time.Duration
			if int(attempt-1) < len(retryDelays) {
				delay = retryDelays[attempt-1]
			} else {
				delay = 30 * time.Second
			}
			time.Sleep(delay)
		}

		err = e.executePending(acc, chatID, localID, action, payload)
		if err == nil {
			e.db.Exec("DELETE FROM pending WHERE local_id = ?", localID)
			if action == ActionReact {
				var p reactPayload
				if json.Unmarshal(payload, &p) == nil {
					e.applyOwnReaction(accountID, chatID, p.MsgID, p.Emoji)
				}
			}
			return nil
		}

		if !isRetryable(err) {
			break
		}

		e.db.Exec(
			"UPDATE pending SET retry_count = retry_count + 1, error_msg = ?, last_attempt = ? WHERE local_id = ?",
			err.Error(), time.Now().UnixMilli(), localID)
	}

	e.markPendingFailed(localID, err.Error())
	if action == ActionSend {
		e.FailMessage(accountID, chatID, localID)
	}
	return err
}

func sendExtras(p sendPayload) map[string]interface{} {
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
	if p.NoWebpage {
		extra["no_webpage"] = true
	}
	return extra
}

func (e *Engine) executePending(acc *Account, chatID, localID, action string, payload []byte) error {
	switch action {
	case ActionSend:
		var p sendPayload
		json.Unmarshal(payload, &p)

		extra := sendExtras(p)
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
		var editErr error
		if editor, ok := acc.Core.(MessageEditorWithEntities); ok && p.EntitiesJSON != "" {
			_, editErr = editor.EditMessageWithEntities(chatID, p.MsgID, p.NewText, p.EntitiesJSON)
		} else {
			_, editErr = acc.Core.EditMessage(chatID, p.MsgID, p.NewText)
		}
		if editErr != nil {
			return editErr
		}
		e.db.Exec(
			"UPDATE messages SET content_text = ?, edited_at = ? WHERE account_id = ? AND chat_id = ? AND msg_id = ?",
			p.NewText, time.Now().UnixMilli(), acc.ID, chatID, p.MsgID)
		return nil

	case ActionDelete:
		var p deletePayload
		json.Unmarshal(payload, &p)
		var err error
		if rd, ok := acc.Core.(cores.RevokableMessageDeleter); ok {
			err = rd.DeleteMessageRevoke(chatID, p.MsgID, p.Revoke)
		} else {
			err = acc.Core.DeleteMessage(chatID, p.MsgID)
		}
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
		if len(p.Emojis) > 0 || p.Emoji == "" {
			if lister, ok := acc.Core.(ReactionListSender); ok {
				return lister.ReactToMessageList(chatID, p.MsgID, p.Emojis)
			}
		}
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

	case ActionForwardBatch:
		var p forwardBatchPayload
		json.Unmarshal(payload, &p)
		type batchForwarder interface {
			ForwardMessagesWithOptions(fromChatID string, msgIDs []string, toChatID string, opts cores.ForwardOptions) error
		}
		if bf, ok := acc.Core.(batchForwarder); ok {
			return bf.ForwardMessagesWithOptions(chatID, p.MsgIDs, p.ToChatID, cores.ForwardOptions{
				DropAuthor: p.DropAuthor, DropCaptions: p.DropCaptions,
				Silent: p.Silent, ScheduleDate: p.ScheduleDate,
			})
		}
		for _, msgID := range p.MsgIDs {
			if fwd, ok := acc.Core.(cores.ForwardWithOptionsSupporter); ok && (p.DropAuthor || p.DropCaptions || p.Silent || p.ScheduleDate > 0) {
				if _, err := fwd.ForwardMessageWithOptions(chatID, msgID, p.ToChatID, cores.ForwardOptions{
					DropAuthor: p.DropAuthor, DropCaptions: p.DropCaptions,
					Silent: p.Silent, ScheduleDate: p.ScheduleDate,
				}); err != nil {
					return err
				}
			} else if _, err := acc.Core.ForwardMessage(chatID, msgID, p.ToChatID); err != nil {
				return err
			}
		}
		return nil

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

func (e *Engine) RetryPending(localID string) error {
	var accountID, chatID, action string
	var payload []byte
	err := e.db.QueryRow(
		"SELECT account_id, chat_id, action, payload FROM pending WHERE local_id = ? AND status = ?",
		localID, PendingFailed).Scan(&accountID, &chatID, &action, &payload)
	if err != nil {
		return fmt.Errorf("pending item not found: %w", err)
	}

	e.db.Exec("UPDATE pending SET status = ?, error_msg = NULL WHERE local_id = ?",
		PendingQueued, localID)

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
			time.Sleep(3 * time.Second)
			e.processPendingItem(item.AccountID, item.ChatID, item.LocalID, item.Action, item.Payload)
		}()
	}
}

func isMediaDownloadable(mt int) bool {
	switch mt {
	case MediaPoll, MediaLocation, MediaContact, MediaInvoice:
		return false
	default:
		return true
	}
}

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
	if p.DropCaptions {
		text = ""
	}

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
			stickerExt := filepath.Ext(fileName.String)
			if stickerExt == "" {
				stickerExt = ".bin"
			}
			if rd, derr := resendTmpDir(); derr == nil {
				os.Remove(filepath.Join(rd, safePathSegment(p.MsgID)+stickerExt))
			}
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
		tmpDir, err := resendTmpDir()
		if err != nil {
			return fmt.Errorf("resend dir: %w", err)
		}
		ext := filepath.Ext(fileName.String)
		if ext == "" {
			ext = ".bin"
		}
		tmpPath := filepath.Join(tmpDir, safePathSegment(p.MsgID)+ext)
		defer os.Remove(tmpPath)

		ref := cores.FileRef{
			ID:       remoteRef.String,
			Name:     fileName.String,
			MimeType: mimeType.String,
			Extra:    extraStr.String,
			Size:     expectedSize,
		}
		alreadyDownloaded := false
		if info, statErr := os.Stat(tmpPath); statErr == nil && (expectedSize <= 0 || info.Size() >= expectedSize) {
			alreadyDownloaded = true
		}
		if !alreadyDownloaded {
			if err := acc.Core.DownloadFile(ref, tmpPath, nil); err != nil {
				log.Printf("resend download failed (skipping media): %v", err)
				if text != "" {
					return e.resendText(acc, p.ToChatID, text, p.Silent, p.ScheduleDate)
				}
				return nil
			}
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

func (e *Engine) executeResendAlbum(acc *Account, p resendAlbumPayload) error {
	albumSender, hasAlbumSupport := acc.Core.(cores.MediaAlbumSender)

	tmpDir, err := resendTmpDir()
	if err != nil {
		return fmt.Errorf("resend dir: %w", err)
	}

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
		if p.DropCaptions {
			contentText.String = ""
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
		tmpPath := filepath.Join(tmpDir, safePathSegment(msgID)+ext)

		ref := cores.FileRef{
			ID: remoteRef.String, Name: fName.String,
			MimeType: mime.String, Extra: extra.String, Size: expSize,
		}
		alreadyDownloaded := false
		if info, statErr := os.Stat(tmpPath); statErr == nil && (expSize <= 0 || info.Size() >= expSize) {
			alreadyDownloaded = true
		}
		if !alreadyDownloaded {
			if err := acc.Core.DownloadFile(ref, tmpPath, nil); err != nil {
				log.Printf("resend album: download %s failed, skipping: %v", msgID, err)
				continue
			}
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

func isRetryable(err error) bool {
	return errors.Is(err, cores.ErrNetwork) ||
		errors.Is(err, cores.ErrTimeout) ||
		errors.Is(err, cores.ErrRateLimit) ||
		errors.Is(err, cores.ErrDisconnected)
}

func resendTmpDir() (string, error) {
	return utils.PrivateCacheDir("resend")
}
