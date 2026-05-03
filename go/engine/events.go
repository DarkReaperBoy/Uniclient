package engine

import (
	"encoding/json"
	"strconv"
	"sync"
	"time"

	"uniclient/cores"
)

// --- Engine event types ---

const (
	EventAuthState       = "auth_state"
	EventConnState       = "conn_state"
	EventAccountList     = "account_list"
	EventChatSnapshot    = "chat_snapshot"
	EventChatUpdated     = "chat_updated"
	EventChatRemoved     = "chat_removed"
	EventMsgReceived     = "msg_received"
	EventMsgEdited       = "msg_edited"
	EventMsgDeleted      = "msg_deleted"
	EventMsgStatus       = "msg_status"
	EventTyping          = "typing"
	EventUserStatus      = "user_status"
	EventDownloadProgress = "download_progress"
	EventDownloadComplete = "download_complete"
	EventIncomingCall    = "incoming_call"
	EventCallState       = "call_state"
	EventGroupCallState  = "group_call_state"
)

// EngineEvent is the envelope for all events pushed to Dart.
type EngineEvent struct {
	Type      string `json:"type"`
	AccountID string `json:"account_id,omitempty"`
	Timestamp int64  `json:"timestamp_ms"`
	Data      any    `json:"data"`
}

// --- Event data types ---

type AuthStateEvent struct {
	State   string `json:"state"`
	Prompt  string `json:"prompt,omitempty"`
	Error   string `json:"error,omitempty"`
}

type ConnStateEvent struct {
	State string `json:"state"` // "disconnected", "connecting", "connected", "unstable", "auth_required"
	Error string `json:"error,omitempty"`
}

type ChatSnapshotEvent struct {
	Chats []ChatInfo `json:"chats"`
}

type ChatUpdatedEvent struct {
	Chat ChatInfo `json:"chat"`
}

type ChatRemovedEvent struct {
	ChatID string `json:"chat_id"`
}

type MsgReceivedEvent struct {
	AccountID string `json:"account_id"`
	ChatID    string `json:"chat_id"`
	Message   CachedMessage `json:"message"`
}

type MsgEditedEvent struct {
	AccountID  string          `json:"account_id"`
	ChatID     string          `json:"chat_id"`
	MsgID      string          `json:"msg_id"`
	NewText    string          `json:"new_text"`
	EditedAt   int64           `json:"edited_at"`
	ContentRaw json.RawMessage `json:"content_raw,omitempty"`
}

type MsgDeletedEvent struct {
	AccountID   string `json:"account_id"`
	ChatID      string `json:"chat_id"`
	MsgID       string `json:"msg_id"`
	SenderIsBot bool   `json:"sender_is_bot"`
}

type MsgStatusEvent struct {
	AccountID string `json:"account_id"`
	ChatID    string `json:"chat_id"`
	MsgID     string `json:"msg_id"`
	LocalID   string `json:"local_id,omitempty"`
	Status    int    `json:"status"`
}

type TypingEvent struct {
	ChatID   string `json:"chat_id"`
	UserID   string `json:"user_id"`
	UserName string `json:"user_name,omitempty"`
}

type UserStatusEvent struct {
	UserID       string `json:"user_id"`
	IsOnline     bool   `json:"is_online"`
	// LastSeenKind: "online", "recently", "within_week", "within_month",
	// "long_ago", "exact", "hidden". When "exact", LastSeen holds the UTC timestamp.
	LastSeenKind string `json:"last_seen_kind,omitempty"`
	LastSeen     int64  `json:"last_seen,omitempty"` // Unix millis, only set for "exact" kind
}

type DownloadProgressEvent struct {
	AccountID string `json:"account_id"`
	ChatID    string `json:"chat_id"`
	MsgID     string `json:"msg_id"`
	Seq       int    `json:"seq"`
	BytesRecv int64  `json:"bytes_recv"`
	BytesTotal int64 `json:"bytes_total"`
}

type DownloadCompleteEvent struct {
	AccountID string `json:"account_id"`
	ChatID    string `json:"chat_id"`
	MsgID     string `json:"msg_id"`
	Seq       int    `json:"seq"`
	LocalPath string `json:"local_path"`
}

// --- Event dispatch ---

// emitEvent serializes and pushes an event to Dart.
func (e *Engine) emitEvent(eventType, accountID string, data any) {
	evt := EngineEvent{
		Type:      eventType,
		AccountID: accountID,
		Timestamp: time.Now().UnixMilli(),
		Data:      data,
	}
	b, err := json.Marshal(evt)
	if err != nil {
		return
	}
	e.pushEvent(b)
}

// emitConnState pushes a connection state change event.
func (e *Engine) emitConnState(accountID string, state ConnState, errMsg string) {
	stateStr := "disconnected"
	switch state {
	case ConnConnecting:
		stateStr = "connecting"
	case ConnConnected:
		stateStr = "connected"
	case ConnUnstable:
		stateStr = "unstable"
	}
	e.emitEvent(EventConnState, accountID, ConnStateEvent{
		State: stateStr,
		Error: errMsg,
	})
}

// emitAccountList pushes the full account list to Dart.
func (e *Engine) emitAccountList() {
	e.emitEvent(EventAccountList, "", e.ListAccounts())
}

// --- Typing dedup ---

type typingKey struct {
	accountID string
	chatID    string
	userID    string
}

var (
	typingMu    sync.Mutex
	typingCache = make(map[typingKey]time.Time)
)

// shouldEmitTyping deduplicates typing events — at most once per 5s per user+chat.
func shouldEmitTyping(accountID, chatID, userID string) bool {
	key := typingKey{accountID, chatID, userID}
	typingMu.Lock()
	defer typingMu.Unlock()

	if last, ok := typingCache[key]; ok && time.Since(last) < 5*time.Second {
		return false
	}
	typingCache[key] = time.Now()
	return true
}

// --- Core update handler ---

// handleUpdate processes a real-time update from a core.
// It caches the data, deduplicates, and emits events to Dart.
func (e *Engine) handleUpdate(accountID string, u cores.Update) {
	// Update last event time for heartbeat monitoring.
	e.accountsMu.Lock()
	if acc, ok := e.accounts[accountID]; ok {
		acc.lastEvent = time.Now()
	}
	e.accountsMu.Unlock()

	switch u.Type {
	case cores.UpdateNewMessage:
		if u.Message == nil {
			return
		}
		e.handleNewMessage(accountID, u.ChatID, u.Message)

	case cores.UpdateEditMessage:
		if u.Message == nil {
			return
		}
		e.handleEditMessage(accountID, u.ChatID, u.Message)

	case cores.UpdateDeleteMessage:
		e.handleDeleteMessage(accountID, u.ChatID, u.MessageID)

	case cores.UpdateReadState:
		if u.ReadState != nil {
			e.handleReadState(accountID, u.ChatID, u.ReadState)
		}

	case cores.UpdateTyping:
		if shouldEmitTyping(accountID, u.ChatID, u.UserID) {
			e.emitEvent(EventTyping, accountID, TypingEvent{
				ChatID: u.ChatID,
				UserID: u.UserID,
			})
		}

	case cores.UpdateUserStatus:
		if u.IsOnline != nil {
			var lastSeenMs int64
			if u.LastSeen != nil {
				lastSeenMs = u.LastSeen.UnixMilli()
			}
			e.handleUserStatus(accountID, u.UserID, *u.IsOnline, u.LastSeenKind, lastSeenMs)
		}

	case cores.UpdateCallState:
		if u.Call != nil {
			e.handleCallUpdate(accountID, u.Call)
		}

	case cores.UpdateConnectivity:
		e.handleConnectivity(accountID, u.ConnState)
	}
}

// handleNewMessage deduplicates, caches, updates chat list, and emits event.
func (e *Engine) handleNewMessage(accountID, chatID string, msg *cores.Message) {
	// Dedup: check if message already exists.
	var exists int
	e.db.QueryRow(
		"SELECT 1 FROM messages WHERE account_id = ? AND chat_id = ? AND msg_id = ?",
		accountID, chatID, msg.ID).Scan(&exists)
	if exists == 1 {
		return
	}

	// Cache message.
	cached := e.cacheMessage(accountID, chatID, msg)

	// Update chat list — create chat entry if it doesn't exist yet (new conversation).
	preview := msgPreviewText(msg)
	var mediaType int
	var thumbB64 string
	if len(msg.Attachments) > 0 {
		att := msg.Attachments[0]
		mediaType = guessMediaType(att.MimeType, att.Name)
		thumbB64 = att.ThumbB64
	}
	e.ensureChatExists(accountID, chatID, msg)
	e.updateChatLastMessage(accountID, chatID, msg.ID, preview, msg.SenderName, msg.Timestamp.UnixMilli(), msg.IsOutgoing, msgStatusFromCore(msg.Status), mediaType, thumbB64)

	// Increment unread if not active chat.
	if !e.isActiveChat(accountID, chatID) {
		e.incrementUnread(accountID, chatID)
	}

	// Emit.
	e.emitEvent(EventMsgReceived, accountID, MsgReceivedEvent{
		AccountID: accountID,
		ChatID:    chatID,
		Message:   cached,
	})
}

// handleEditMessage saves pre-edit text (anti-recall) then updates the cached message.
func (e *Engine) handleEditMessage(accountID, chatID string, msg *cores.Message) {
	now := time.Now().UnixMilli()
	editedAt := now
	if msg.EditedAt != nil {
		editedAt = msg.EditedAt.UnixMilli()
	}

	// Anti-recall: save pre-edit text before applying update.
	var oldText, oldSenderID, oldSenderName string
	var oldRich []byte
	var isOutgoing int
	e.db.QueryRow(
		`SELECT content_text, sender_id, sender_name, content_rich, is_outgoing
		 FROM messages WHERE account_id = ? AND chat_id = ? AND msg_id = ?`,
		accountID, chatID, msg.ID,
	).Scan(&oldText, &oldSenderID, &oldSenderName, &oldRich, &isOutgoing)

	if oldText != "" && oldText != msg.Text && isOutgoing == 0 {
		var entitiesJSON string
		if len(oldRich) > 0 {
			entitiesJSON = string(oldRich)
		}
		e.db.Exec(
			`INSERT INTO edited_messages (account_id, chat_id, msg_id, sender_id, sender_name, content_text, entities_json, timestamp)
			 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
			accountID, chatID, msg.ID, oldSenderID, oldSenderName, oldText, entitiesJSON, now,
		)
	}

	rawBytes, _ := json.Marshal(msg)
	var richBytes []byte
	if len(msg.Entities) > 0 {
		richBytes, _ = json.Marshal(msg.Entities)
	}

	e.db.Exec(
		`UPDATE messages SET content_text = ?, content_raw = ?, content_rich = ?, edited_at = ?
		 WHERE account_id = ? AND chat_id = ? AND msg_id = ?`,
		msg.Text, rawBytes, richBytes, editedAt, accountID, chatID, msg.ID)

	e.emitEvent(EventMsgEdited, accountID, MsgEditedEvent{
		AccountID:  accountID,
		ChatID:     chatID,
		MsgID:      msg.ID,
		NewText:    msg.Text,
		EditedAt:   editedAt,
		ContentRaw: json.RawMessage(rawBytes),
	})
}

// handleDeleteMessage marks message as deleted (anti-recall) and emits event.
func (e *Engine) handleDeleteMessage(accountID, chatID, msgID string) {
	resolvedChatID := chatID
	var senderID string

	if resolvedChatID == "" {
		e.db.QueryRow(
			"SELECT chat_id, sender_id FROM messages WHERE account_id = ? AND msg_id = ? LIMIT 1",
			accountID, msgID,
		).Scan(&resolvedChatID, &senderID)
	} else {
		e.db.QueryRow(
			"SELECT sender_id FROM messages WHERE account_id = ? AND chat_id = ? AND msg_id = ? LIMIT 1",
			accountID, resolvedChatID, msgID,
		).Scan(&senderID)
	}

	var senderIsBot bool
	if senderID != "" {
		var isBot int
		e.db.QueryRow(
			"SELECT is_bot FROM users WHERE account_id = ? AND user_id = ? LIMIT 1",
			accountID, senderID,
		).Scan(&isBot)
		senderIsBot = isBot == 1
	}

	now := time.Now().UnixMilli()
	if resolvedChatID != "" {
		e.db.Exec(
			"UPDATE messages SET is_deleted = 1, deleted_at = ? WHERE account_id = ? AND chat_id = ? AND msg_id = ?",
			now, accountID, resolvedChatID, msgID)
	} else {
		e.db.Exec(
			"UPDATE messages SET is_deleted = 1, deleted_at = ? WHERE account_id = ? AND msg_id = ?",
			now, accountID, msgID)
	}

	e.emitEvent(EventMsgDeleted, accountID, MsgDeletedEvent{
		AccountID:   accountID,
		ChatID:      resolvedChatID,
		MsgID:       msgID,
		SenderIsBot: senderIsBot,
	})
}

// handleReadState updates unread counts.
func (e *Engine) handleReadState(accountID, chatID string, rs *cores.ReadState) {
	if rs.MyLastRead != "" {
		// Mark as read up to this message — set unread_count to 0 if we read everything.
		e.db.Exec(
			"UPDATE chats SET unread_count = 0 WHERE account_id = ? AND chat_id = ?",
			accountID, chatID)
		e.emitChatUpdate(accountID, chatID)
	}
}

// handleUserStatus updates user online state.
func (e *Engine) handleUserStatus(accountID, userID string, online bool, kind string, lastSeenMs int64) {
	now := time.Now().UnixMilli()
	e.db.Exec(
		`INSERT INTO users (account_id, user_id, is_online, updated_at)
		 VALUES (?, ?, ?, ?)
		 ON CONFLICT(account_id, user_id) DO UPDATE SET is_online = ?, updated_at = ?`,
		accountID, userID, boolToInt(online), now, boolToInt(online), now)

	e.emitEvent(EventUserStatus, accountID, UserStatusEvent{
		UserID:       userID,
		IsOnline:     online,
		LastSeenKind: kind,
		LastSeen:     lastSeenMs,
	})
}

// handleCallUpdate emits call state events.
// Group calls get a dedicated event type so the UI can show/hide the group call bar.
func (e *Engine) handleCallUpdate(accountID string, call *cores.CallSession) {
	if call.IsGroup {
		info := GroupCallInfo{
			CallID: call.ID,
			ChatID: call.ChatID,
			Active: call.State != cores.CallStateEnded,
		}
		if title, ok := call.Meta["title"]; ok {
			info.Title = title
		}
		if countStr, ok := call.Meta["participants_count"]; ok {
			if n, err := strconv.Atoi(countStr); err == nil {
				info.ParticipantsCount = n
			}
		}
		for _, p := range call.Participants {
			info.Participants = append(info.Participants, GroupCallParticipant{
				UserID:      p.UserID,
				DisplayName: p.DisplayName,
				IsMuted:     p.IsMuted,
				IsSpeaking:  p.IsSpeaking,
				HasVideo:    p.HasVideo,
			})
		}
		if info.ParticipantsCount == 0 && len(info.Participants) > 0 {
			info.ParticipantsCount = len(info.Participants)
		}
		e.emitEvent(EventGroupCallState, accountID, info)
		return
	}
	if call.State == cores.CallStateRinging {
		e.emitEvent(EventIncomingCall, accountID, call)
	} else {
		e.emitEvent(EventCallState, accountID, call)
	}
}

// handleConnectivity handles core-level connectivity changes.
func (e *Engine) handleConnectivity(accountID, connState string) {
	switch connState {
	case "connected":
		e.setConnState(accountID, ConnConnected)
		e.emitConnState(accountID, ConnConnected, "")
	case "disconnected":
		e.setConnState(accountID, ConnDisconnected)
		e.emitConnState(accountID, ConnDisconnected, "")
	case "reconnecting":
		e.setConnState(accountID, ConnConnecting)
		e.emitConnState(accountID, ConnConnecting, "")
	}
}

func boolToInt(b bool) int {
	if b {
		return 1
	}
	return 0
}
