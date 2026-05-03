package engine

import (
	"database/sql"
	"fmt"
	"log"
	"strconv"
	"time"

	"uniclient/cores"
)

// ChatInfo is the cached chat data returned to the UI.
type ChatInfo struct {
	AccountID    string `json:"account_id"`
	ChatID       string `json:"chat_id"`
	Type         int    `json:"type"`
	Title        string `json:"title"`
	AvatarPath   string `json:"avatar_path,omitempty"`
	LastMsgID    string `json:"last_msg_id,omitempty"`
	LastMsgText  string `json:"last_msg_text,omitempty"`
	LastMsgTime  int64  `json:"last_msg_time,omitempty"`
	LastMsgSender     string `json:"last_msg_sender,omitempty"`
	LastMsgIsOutgoing bool   `json:"last_msg_is_outgoing,omitempty"`
	LastMsgStatus     int    `json:"last_msg_status,omitempty"`
	LastMsgMediaType  int    `json:"last_msg_media_type,omitempty"`
	LastMsgThumbB64   string `json:"last_msg_thumb_b64,omitempty"`
	UnreadCount       int    `json:"unread_count"`
	IsMuted      bool   `json:"is_muted"`
	IsPinned     bool   `json:"is_pinned"`
	IsArchived   bool   `json:"is_archived"`
	DraftText    string `json:"draft_text,omitempty"`
	MemberCount  int    `json:"member_count,omitempty"`
	ParentID     string `json:"parent_id,omitempty"`
	IsBot               bool `json:"is_bot"`
	IsContact           bool `json:"is_contact"`
	IsBlocked           bool `json:"is_blocked"`
	UnreadMark          bool `json:"unread_mark"`
	UnreadMentionCount  int  `json:"unread_mention_count"`
	UnreadReactionCount int  `json:"unread_reaction_count"`
	IsVerified           bool  `json:"is_verified"`
	IsScam               bool  `json:"is_scam"`
	IsFake               bool  `json:"is_fake"`
	SlowmodeSeconds      int    `json:"slowmode_seconds,omitempty"`
	SlowmodeNextSendDate int64  `json:"slowmode_next_send_date,omitempty"`
	StarsToSend          int    `json:"stars_to_send,omitempty"`
	TtlPeriod            int    `json:"ttl_period,omitempty"`
	EmojiStatusID        string `json:"emoji_status_id,omitempty"`
	StoryCount           int    `json:"story_count,omitempty"`
	HasUnreadStory       bool   `json:"has_unread_story,omitempty"`
	IsForum              bool   `json:"is_forum,omitempty"`
	WriteRestrictionType int    `json:"write_restriction_type,omitempty"`
	WriteRestrictionText string `json:"write_restriction_text,omitempty"`
	NotJoined            bool   `json:"not_joined,omitempty"`
	JoinRequest          bool   `json:"join_request,omitempty"`
	CanPost              bool   `json:"can_post,omitempty"`
	NoForwards           bool   `json:"no_forwards,omitempty"`
}

// chatTypeToInt converts cores.ChatType to DB integer.
func chatTypeToInt(ct cores.ChatType) int {
	switch ct {
	case cores.ChatTypeDM:
		return ChatTypeDMVal
	case cores.ChatTypeGroup:
		return ChatTypeGroupVal
	case cores.ChatTypeChannel:
		return ChatTypeChanVal
	case cores.ChatTypeTopic:
		return ChatTypeTopicVal
	default:
		return ChatTypeUnspec
	}
}

// GetUnifiedChatList returns chats from all accounts, sorted by pinned then time.
func (e *Engine) GetUnifiedChatList(limit, offset int) ([]ChatInfo, error) {
	if limit <= 0 {
		limit = 50
	}
	rows, err := e.db.Query(
		`SELECT c.account_id, c.chat_id, c.type, c.title, c.avatar_path,
		        c.last_msg_id, c.last_msg_text, c.last_msg_time, c.last_msg_sender,
		        c.last_msg_is_outgoing, c.last_msg_status, c.last_msg_media_type, c.last_msg_thumb_b64,
		        c.unread_count, c.is_muted, c.is_pinned, c.is_archived,
		        c.draft_text, c.member_count, c.parent_id,
		        COALESCE(u.is_bot, 0), COALESCE(u.is_contact, 0), COALESCE(u.is_blocked, 0),
		        c.unread_mark, c.unread_mention_count, c.unread_reaction_count,
		        c.is_verified, c.is_scam, c.is_fake,
		        c.slowmode_seconds, c.slowmode_next_send_date,
		        c.stars_to_send, c.ttl_period, c.emoji_status_id,
		        c.story_count, c.has_unread_story, c.is_forum,
		        c.write_restriction_type, c.write_restriction_text,
		        c.not_joined, c.join_request, c.can_post, c.no_forwards
		 FROM chats c
		 LEFT JOIN users u ON c.account_id = u.account_id AND c.chat_id = u.user_id AND c.type = 1
		 ORDER BY c.is_archived ASC, c.is_pinned DESC, c.last_msg_time DESC
		 LIMIT ? OFFSET ?`, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanChats(rows)
}

// GetChatList returns chats for a single account.
func (e *Engine) GetChatList(accountID string, archived bool, limit, offset int) ([]ChatInfo, error) {
	if limit <= 0 {
		limit = 50
	}
	archivedInt := 0
	if archived {
		archivedInt = 1
	}
	rows, err := e.db.Query(
		`SELECT c.account_id, c.chat_id, c.type, c.title, c.avatar_path,
		        c.last_msg_id, c.last_msg_text, c.last_msg_time, c.last_msg_sender,
		        c.last_msg_is_outgoing, c.last_msg_status, c.last_msg_media_type, c.last_msg_thumb_b64,
		        c.unread_count, c.is_muted, c.is_pinned, c.is_archived,
		        c.draft_text, c.member_count, c.parent_id,
		        COALESCE(u.is_bot, 0), COALESCE(u.is_contact, 0), COALESCE(u.is_blocked, 0),
		        c.unread_mark, c.unread_mention_count, c.unread_reaction_count,
		        c.is_verified, c.is_scam, c.is_fake,
		        c.slowmode_seconds, c.slowmode_next_send_date,
		        c.stars_to_send, c.ttl_period, c.emoji_status_id,
		        c.story_count, c.has_unread_story, c.is_forum,
		        c.write_restriction_type, c.write_restriction_text,
		        c.not_joined, c.join_request, c.can_post, c.no_forwards
		 FROM chats c
		 LEFT JOIN users u ON c.account_id = u.account_id AND c.chat_id = u.user_id AND c.type = 1
		 WHERE c.account_id = ? AND c.is_archived = ?
		 ORDER BY c.is_pinned DESC, c.last_msg_time DESC
		 LIMIT ? OFFSET ?`, accountID, archivedInt, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanChats(rows)
}

func scanChats(rows *sql.Rows) ([]ChatInfo, error) {
	var chats []ChatInfo
	for rows.Next() {
		var c ChatInfo
		var avatarPath, lastMsgID, lastMsgText, lastMsgSender, draftText, parentID sql.NullString
		var lastMsgThumbB64, emojiStatusID sql.NullString
		var lastMsgTime sql.NullInt64
		var memberCount sql.NullInt64
		var isMuted, isPinned, isArchived, lastMsgIsOutgoing, isBot int
		var isContact, isBlocked int
		var unreadMark, isVerified, isScam, isFake int

		var hasUnreadStory, isForumInt int
		var notJoined, joinRequestInt, canPostInt, noForwardsInt int
		var writeRestrictionText sql.NullString
		if err := rows.Scan(
			&c.AccountID, &c.ChatID, &c.Type, &c.Title, &avatarPath,
			&lastMsgID, &lastMsgText, &lastMsgTime, &lastMsgSender,
			&lastMsgIsOutgoing, &c.LastMsgStatus, &c.LastMsgMediaType, &lastMsgThumbB64,
			&c.UnreadCount, &isMuted, &isPinned, &isArchived,
			&draftText, &memberCount, &parentID, &isBot, &isContact, &isBlocked,
			&unreadMark, &c.UnreadMentionCount, &c.UnreadReactionCount,
			&isVerified, &isScam, &isFake,
			&c.SlowmodeSeconds, &c.SlowmodeNextSendDate,
			&c.StarsToSend, &c.TtlPeriod, &emojiStatusID,
			&c.StoryCount, &hasUnreadStory, &isForumInt,
			&c.WriteRestrictionType, &writeRestrictionText,
			&notJoined, &joinRequestInt, &canPostInt, &noForwardsInt,
		); err != nil {
			return chats, err
		}

		c.AvatarPath = avatarPath.String
		c.LastMsgID = lastMsgID.String
		c.LastMsgText = lastMsgText.String
		if lastMsgTime.Valid {
			c.LastMsgTime = lastMsgTime.Int64
		}
		c.LastMsgSender = lastMsgSender.String
		c.LastMsgIsOutgoing = lastMsgIsOutgoing == 1
		c.LastMsgThumbB64 = lastMsgThumbB64.String
		c.IsMuted = isMuted == 1
		c.IsPinned = isPinned == 1
		c.IsArchived = isArchived == 1
		c.DraftText = draftText.String
		if memberCount.Valid {
			c.MemberCount = int(memberCount.Int64)
		}
		c.ParentID = parentID.String
		c.IsBot = isBot == 1
		c.IsContact = isContact == 1
		c.IsBlocked = isBlocked == 1
		c.UnreadMark = unreadMark == 1
		c.IsVerified = isVerified == 1
		c.IsScam = isScam == 1
		c.IsFake = isFake == 1
		c.EmojiStatusID = emojiStatusID.String
		c.HasUnreadStory = hasUnreadStory == 1
		c.IsForum = isForumInt == 1
		c.WriteRestrictionText = writeRestrictionText.String
		c.NotJoined = notJoined == 1
		c.JoinRequest = joinRequestInt == 1
		c.CanPost = canPostInt == 1
		c.NoForwards = noForwardsInt == 1

		chats = append(chats, c)
	}
	return chats, rows.Err()
}

// UpsertChat inserts or updates a chat in the cache.
func (e *Engine) UpsertChat(accountID string, d cores.Dialog) error {
	now := time.Now().UnixMilli()
	chatType := chatTypeToInt(d.Type)

	var lastMsgText, lastMsgSender string
	var lastMsgTime int64
	var lastMsgID string
	var lastMsgIsOutgoing int
	var lastMsgStatus int
	var lastMsgMediaType int
	var lastMsgThumbB64 string
	if d.LastMessage != nil {
		lastMsgID = d.LastMessage.ID
		lastMsgText = msgPreviewText(d.LastMessage)
		lastMsgSender = d.LastMessage.SenderName
		lastMsgTime = d.LastMessage.Timestamp.UnixMilli()
		if d.LastMessage.IsOutgoing {
			lastMsgIsOutgoing = 1
		}
		lastMsgStatus = msgStatusFromCore(d.LastMessage.Status)
		if len(d.LastMessage.Attachments) > 0 {
			att := d.LastMessage.Attachments[0]
			lastMsgMediaType = guessMediaType(att.MimeType, att.Name)
			lastMsgThumbB64 = att.ThumbB64
		}
	}

	_, err := e.db.Exec(
		`INSERT INTO chats (account_id, chat_id, type, title, last_msg_id, last_msg_text,
		                     last_msg_time, last_msg_sender, last_msg_is_outgoing,
		                     last_msg_status, last_msg_media_type, last_msg_thumb_b64,
		                     unread_count, is_muted, is_pinned,
		                     is_archived, member_count, parent_id,
		                     unread_mark, unread_mention_count, unread_reaction_count,
		                     is_verified, is_scam, is_fake,
		                     slowmode_seconds, slowmode_next_send_date, stars_to_send, ttl_period,
		                     emoji_status_id, story_count, has_unread_story, is_forum,
		                     write_restriction_type, write_restriction_text,
		                     not_joined, join_request, can_post, no_forwards, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		 ON CONFLICT(account_id, chat_id) DO UPDATE SET
		     type = excluded.type,
		     title = excluded.title,
		     last_msg_id = COALESCE(excluded.last_msg_id, chats.last_msg_id),
		     last_msg_text = COALESCE(excluded.last_msg_text, chats.last_msg_text),
		     last_msg_time = MAX(COALESCE(excluded.last_msg_time, 0), COALESCE(chats.last_msg_time, 0)),
		     last_msg_sender = COALESCE(excluded.last_msg_sender, chats.last_msg_sender),
		     last_msg_is_outgoing = CASE WHEN excluded.last_msg_time > COALESCE(chats.last_msg_time, 0) THEN excluded.last_msg_is_outgoing ELSE chats.last_msg_is_outgoing END,
		     last_msg_status = CASE WHEN excluded.last_msg_time > COALESCE(chats.last_msg_time, 0) THEN excluded.last_msg_status ELSE chats.last_msg_status END,
		     last_msg_media_type = CASE WHEN excluded.last_msg_time > COALESCE(chats.last_msg_time, 0) THEN excluded.last_msg_media_type ELSE chats.last_msg_media_type END,
		     last_msg_thumb_b64 = CASE WHEN excluded.last_msg_time > COALESCE(chats.last_msg_time, 0) THEN excluded.last_msg_thumb_b64 ELSE chats.last_msg_thumb_b64 END,
		     unread_count = excluded.unread_count,
		     is_muted = excluded.is_muted,
		     is_pinned = excluded.is_pinned,
		     is_archived = excluded.is_archived,
		     member_count = excluded.member_count,
		     parent_id = excluded.parent_id,
		     unread_mark = excluded.unread_mark,
		     unread_mention_count = excluded.unread_mention_count,
		     unread_reaction_count = excluded.unread_reaction_count,
		     is_verified = excluded.is_verified,
		     is_scam = excluded.is_scam,
		     is_fake = excluded.is_fake,
		     slowmode_seconds = excluded.slowmode_seconds,
		     slowmode_next_send_date = excluded.slowmode_next_send_date,
		     stars_to_send = excluded.stars_to_send,
		     ttl_period = excluded.ttl_period,
		     emoji_status_id = excluded.emoji_status_id,
		     story_count = excluded.story_count,
		     has_unread_story = excluded.has_unread_story,
		     is_forum = excluded.is_forum,
		     write_restriction_type = excluded.write_restriction_type,
		     write_restriction_text = excluded.write_restriction_text,
		     not_joined = excluded.not_joined,
		     join_request = excluded.join_request,
		     can_post = excluded.can_post,
		     no_forwards = excluded.no_forwards,
		     updated_at = excluded.updated_at`,
		accountID, d.ID, chatType, d.Title, lastMsgID, lastMsgText,
		lastMsgTime, lastMsgSender, lastMsgIsOutgoing, lastMsgStatus, lastMsgMediaType, lastMsgThumbB64,
		d.UnreadCount, boolToInt(d.IsMuted), boolToInt(d.IsPinned),
		boolToInt(d.IsArchived), d.MemberCount, d.ParentID,
		boolToInt(d.UnreadMark), d.UnreadMentionCount, d.UnreadReactionCount,
		boolToInt(d.IsVerified), boolToInt(d.IsScam), boolToInt(d.IsFake),
		d.SlowmodeSeconds, d.SlowmodeNextSendDate, d.StarsToSend, d.TtlPeriod,
		d.EmojiStatusID, d.StoryCount, boolToInt(d.HasUnreadStory), boolToInt(d.IsForum),
		d.WriteRestrictionType, d.WriteRestrictionText,
		boolToInt(d.NotJoined), boolToInt(d.JoinRequest), boolToInt(d.CanPost), boolToInt(d.NoForwards), now)
	if err != nil {
		return err
	}

	// Mark that this chat has a photo available for download.
	if d.AvatarURL != "" {
		e.markAvatarAvailable(accountID, d.ID)
	}

	return nil
}

// SyncChats diffs network dialogs against cache and emits appropriate events.
func (e *Engine) SyncChats(accountID string, dialogs []cores.Dialog) error {
	for _, d := range dialogs {
		if err := e.UpsertChat(accountID, d); err != nil {
			return err
		}
	}
	// Emit snapshot for this account.
	chats, err := e.GetChatList(accountID, false, 200, 0)
	if err != nil {
		return err
	}
	e.emitEvent(EventChatSnapshot, accountID, ChatSnapshotEvent{Chats: chats})

	// Download avatars in background.
	go e.DownloadPendingAvatars(accountID)

	return nil
}

// ensureChatExists creates a minimal chat entry if it doesn't exist yet.
// Called when a message arrives for a chat not in the initial sync.
func (e *Engine) ensureChatExists(accountID, chatID string, msg *cores.Message) {
	var exists int
	e.db.QueryRow("SELECT 1 FROM chats WHERE account_id = ? AND chat_id = ?", accountID, chatID).Scan(&exists)
	if exists == 1 {
		return
	}

	// Create minimal chat entry — title will be the sender name for DMs.
	chatType := ChatTypeDMVal
	title := msg.SenderName
	if title == "" {
		title = chatID
	}
	now := time.Now().UnixMilli()
	var msgMediaType int
	var msgThumbB64 string
	if len(msg.Attachments) > 0 {
		att := msg.Attachments[0]
		msgMediaType = guessMediaType(att.MimeType, att.Name)
		msgThumbB64 = att.ThumbB64
	}
	e.db.Exec(
		`INSERT OR IGNORE INTO chats
		 (account_id, chat_id, type, title, avatar_path,
		  last_msg_id, last_msg_text, last_msg_sender, last_msg_time, last_msg_is_outgoing,
		  last_msg_status, last_msg_media_type, last_msg_thumb_b64,
		  unread_count, is_muted, is_pinned, is_archived,
		  draft_text, member_count, parent_id, updated_at)
		 VALUES (?, ?, ?, ?, '', ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, 0, '', 0, '', ?)`,
		accountID, chatID, chatType, title,
		msg.ID, msgPreviewText(msg), msg.SenderName, msg.Timestamp.UnixMilli(), boolToInt(msg.IsOutgoing),
		msgStatusFromCore(msg.Status), msgMediaType, msgThumbB64, now)

	// Try to get proper chat info from core in background.
	go func() {
		acc, ok := e.getAccount(accountID)
		if !ok || acc.Core == nil {
			return
		}
		info, err := acc.Core.GetChatInfo(chatID)
		if err != nil || info == nil {
			return
		}
		cType := chatTypeToInt(info.Type)
		e.db.Exec(
			`UPDATE chats SET type = ?, title = ?, member_count = ? WHERE account_id = ? AND chat_id = ?`,
			cType, info.Title, info.MemberCount, accountID, chatID)
		e.emitChatUpdate(accountID, chatID)
	}()

	log.Printf("[engine] ensureChatExists(%s, %s): created new chat entry for %q", accountID, chatID, title)
}

// updateChatLastMessage updates the preview fields for a chat.
func (e *Engine) updateChatLastMessage(accountID, chatID, msgID, text, sender string, timeMs int64, isOutgoing bool, status int, mediaType int, thumbB64 string) {
	outgoing := 0
	if isOutgoing {
		outgoing = 1
	}
	e.db.Exec(
		`UPDATE chats SET last_msg_id = ?, last_msg_text = ?, last_msg_sender = ?,
		                  last_msg_time = ?, last_msg_is_outgoing = ?,
		                  last_msg_status = ?,
		                  last_msg_media_type = ?, last_msg_thumb_b64 = ?,
		                  updated_at = ?
		 WHERE account_id = ? AND chat_id = ? AND (last_msg_time IS NULL OR last_msg_time <= ?)`,
		msgID, text, sender, timeMs, outgoing, status, mediaType, thumbB64,
		time.Now().UnixMilli(), accountID, chatID, timeMs)
	e.emitChatUpdate(accountID, chatID)
}

// incrementUnread bumps the unread count for a chat.
func (e *Engine) incrementUnread(accountID, chatID string) {
	e.db.Exec(
		"UPDATE chats SET unread_count = unread_count + 1 WHERE account_id = ? AND chat_id = ?",
		accountID, chatID)
}

// MarkChatRead resets unread count to 0 and optionally calls core.MarkAsRead.
// Ghost mode: when SendReadReceipts is false, only the local unread count
// is cleared — the server-side read receipt (messages.readHistory) is suppressed.
func (e *Engine) MarkChatRead(accountID, chatID, upToMsgID string) error {
	e.db.Exec(
		"UPDATE chats SET unread_count = 0 WHERE account_id = ? AND chat_id = ?",
		accountID, chatID)

	cfg := e.GetConfig()
	if cfg.SendReadReceipts {
		if acc, ok := e.getAccount(accountID); ok && acc.Core != nil && upToMsgID != "" {
			acc.Core.MarkAsRead(chatID, upToMsgID)
		}
	}

	e.emitChatUpdate(accountID, chatID)
	return nil
}

// SaveDraft persists draft text for a chat.
func (e *Engine) SaveDraft(accountID, chatID, text string) error {
	_, err := e.db.Exec(
		"UPDATE chats SET draft_text = ? WHERE account_id = ? AND chat_id = ?",
		text, accountID, chatID)
	return err
}

// MuteChat sets the muted state for a chat.
// If durationSeconds > 0, mutes for that duration (only supported on some platforms).
// If durationSeconds == 0 and muted == true, mutes forever.
// If muted == false, unmutes regardless of durationSeconds.
func (e *Engine) MuteChat(accountID, chatID string, muted bool, durationSeconds int32) error {
	_, err := e.db.Exec(
		"UPDATE chats SET is_muted = ? WHERE account_id = ? AND chat_id = ?",
		boolToInt(muted), accountID, chatID)
	if err != nil {
		return err
	}

	if acc, ok := e.getAccount(accountID); ok && acc.Core != nil {
		if durationSeconds > 0 {
			type timedMuter interface {
				MuteChatFor(chatID string, durationSeconds int32) error
			}
			if tm, ok := acc.Core.(timedMuter); ok {
				tm.MuteChatFor(chatID, durationSeconds)
			} else {
				acc.Core.MuteChat(chatID, muted)
			}
		} else {
			acc.Core.MuteChat(chatID, muted)
		}
	}

	e.emitChatUpdate(accountID, chatID)
	return nil
}

// SetHistoryTTL sets the auto-delete timer for a chat and updates the cache.
func (e *Engine) SetHistoryTTL(accountID, chatID string, period int) error {
	if acc, ok := e.getAccount(accountID); ok && acc.Core != nil {
		type ttlSetter interface {
			SetHistoryTTL(chatID string, period int) error
		}
		if ts, ok := acc.Core.(ttlSetter); ok {
			if err := ts.SetHistoryTTL(chatID, period); err != nil {
				return err
			}
		}
	}
	_, err := e.db.Exec(
		"UPDATE chats SET ttl_period = ? WHERE account_id = ? AND chat_id = ?",
		period, accountID, chatID)
	if err != nil {
		return err
	}
	e.emitChatUpdate(accountID, chatID)
	return nil
}

// GetDefaultHistoryTTL returns the global auto-delete timer for new chats.
func (e *Engine) GetDefaultHistoryTTL(accountID string) (int, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return 0, fmt.Errorf("account not found: %s", accountID)
	}
	type globalTTLGetter interface {
		GetDefaultHistoryTTL() (int, error)
	}
	g, ok := acc.Core.(globalTTLGetter)
	if !ok {
		return 0, fmt.Errorf("platform does not support global TTL")
	}
	return g.GetDefaultHistoryTTL()
}

// SetDefaultHistoryTTL sets the global auto-delete timer for new chats.
func (e *Engine) SetDefaultHistoryTTL(accountID string, period int) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	type globalTTLSetter interface {
		MessagesSetDefaultHistoryTTL(period int) (bool, error)
	}
	s, ok := acc.Core.(globalTTLSetter)
	if !ok {
		return fmt.Errorf("platform does not support global TTL")
	}
	_, err := s.MessagesSetDefaultHistoryTTL(period)
	return err
}

func (e *Engine) GetAccountTTL(accountID string) (int, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return 0, fmt.Errorf("account not found: %s", accountID)
	}
	type accountTTLGetter interface {
		GetAccountTTL() (int, error)
	}
	g, ok := acc.Core.(accountTTLGetter)
	if !ok {
		return 0, fmt.Errorf("platform does not support account TTL")
	}
	return g.GetAccountTTL()
}

func (e *Engine) SetAccountTTL(accountID string, days int) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	type accountTTLSetter interface {
		SetAccountTTL(days int) error
	}
	s, ok := acc.Core.(accountTTLSetter)
	if !ok {
		return fmt.Errorf("platform does not support account TTL")
	}
	return s.SetAccountTTL(days)
}

func (e *Engine) GetTopPeersEnabled(accountID string) (bool, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return false, fmt.Errorf("account not found: %s", accountID)
	}
	type topPeersGetter interface {
		GetTopPeersCount() (int, error)
	}
	g, ok := acc.Core.(topPeersGetter)
	if !ok {
		return false, fmt.Errorf("platform does not support top peers")
	}
	count, err := g.GetTopPeersCount()
	if err != nil {
		return false, err
	}
	return count >= 0, nil
}

func (e *Engine) ToggleTopPeers(accountID string, enabled bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	type topPeersToggler interface {
		ContactsToggleTopPeers(enabled bool) (bool, error)
	}
	t, ok := acc.Core.(topPeersToggler)
	if !ok {
		return fmt.Errorf("platform does not support top peers")
	}
	_, err := t.ContactsToggleTopPeers(enabled)
	return err
}

// PinChat sets the pinned state for a chat.
func (e *Engine) PinChat(accountID, chatID string, pinned bool) error {
	_, err := e.db.Exec(
		"UPDATE chats SET is_pinned = ? WHERE account_id = ? AND chat_id = ?",
		boolToInt(pinned), accountID, chatID)
	if err != nil {
		return err
	}
	e.emitChatUpdate(accountID, chatID)
	return nil
}

// ArchiveChat sets the archived state for a chat.
func (e *Engine) ArchiveChat(accountID, chatID string, archived bool) error {
	_, err := e.db.Exec(
		"UPDATE chats SET is_archived = ? WHERE account_id = ? AND chat_id = ?",
		boolToInt(archived), accountID, chatID)
	if err != nil {
		return err
	}

	// Also call core.
	if acc, ok := e.getAccount(accountID); ok && acc.Core != nil {
		acc.Core.ArchiveChat(chatID, archived)
	}

	e.emitChatUpdate(accountID, chatID)
	return nil
}

// GetForumTopics fetches forum topics for a chat from the core.
// Returns the full ForumTopic data model with capability flags.
func (e *Engine) GetForumTopics(accountID, chatID string) ([]cores.ForumTopic, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}

	type forumTopicGetter interface {
		GetForumTopics(chatID string, limit int) ([]cores.ForumTopic, error)
	}
	ftg, ok := acc.Core.(forumTopicGetter)
	if !ok {
		return nil, nil
	}

	topics, err := ftg.GetForumTopics(chatID, 100)
	if err != nil {
		return nil, err
	}

	for _, t := range topics {
		ci := cores.Dialog{
			ID: t.ID, Type: cores.ChatTypeTopic, Title: t.Title,
			UnreadCount: t.UnreadCount, IsPinned: t.IsPinned,
			ParentID: t.ParentID, UnreadMentionCount: t.UnreadMentions,
			UnreadReactionCount: t.UnreadReactions,
		}
		if err := e.UpsertChat(accountID, ci); err != nil {
			log.Printf("[engine] GetForumTopics: failed to cache topic %s: %v", t.ID, err)
		}
	}

	return topics, nil
}

func (e *Engine) CreateForumTopic(accountID, chatID, title string, colorID int, iconEmojiID int64) (int, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return 0, fmt.Errorf("account not found: %s", accountID)
	}

	type forumTopicCreator interface {
		CreateForumTopic(chatID string, title string) (int, error)
	}
	ftc, ok := acc.Core.(forumTopicCreator)
	if !ok {
		return 0, fmt.Errorf("platform does not support creating forum topics")
	}

	return ftc.CreateForumTopic(chatID, title)
}

func (e *Engine) EditForumTopic(accountID, chatID string, topicID int, title string, iconEmojiId int64) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}

	type forumTopicEditor interface {
		EditForumTopic(chatID string, topicID int, title string, iconEmojiId int64) error
	}
	fte, ok := acc.Core.(forumTopicEditor)
	if !ok {
		return fmt.Errorf("platform does not support editing forum topics")
	}

	return fte.EditForumTopic(chatID, topicID, title, iconEmojiId)
}

func (e *Engine) PinForumTopic(accountID, chatID string, topicID int, pinned bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	type pinner interface {
		PinForumTopic(chatID string, topicID int, pinned bool) error
	}
	p, ok := acc.Core.(pinner)
	if !ok {
		return fmt.Errorf("platform does not support pinning forum topics")
	}
	return p.PinForumTopic(chatID, topicID, pinned)
}

func (e *Engine) ToggleForumTopicClosed(accountID, chatID string, topicID int, closed bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	type closer interface {
		ToggleForumTopicClosed(chatID string, topicID int, closed bool) error
	}
	c, ok := acc.Core.(closer)
	if !ok {
		return fmt.Errorf("platform does not support closing forum topics")
	}
	return c.ToggleForumTopicClosed(chatID, topicID, closed)
}

func (e *Engine) ToggleGeneralTopicHidden(accountID, chatID string, hidden bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	type hider interface {
		ToggleGeneralTopicHidden(chatID string, hidden bool) error
	}
	h, ok := acc.Core.(hider)
	if !ok {
		return fmt.Errorf("platform does not support hiding general topic")
	}
	return h.ToggleGeneralTopicHidden(chatID, hidden)
}

func (e *Engine) DeleteForumTopicHistory(accountID, chatID string, topicID int) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	type deleter interface {
		DeleteTopicHistory(chatID string, topicID int) error
	}
	d, ok := acc.Core.(deleter)
	if !ok {
		return fmt.Errorf("platform does not support deleting forum topic history")
	}
	return d.DeleteTopicHistory(chatID, topicID)
}

// FolderInfo represents a synced folder from the platform (e.g. Telegram folders).
type FolderInfo struct {
	ID              string
	Name            string
	ChatIDs         []string
	ExcludeChatIDs  []string
	PinnedChatIDs   []string
	Contacts        bool
	NonContacts     bool
	Groups          bool
	Channels        bool
	Bots            bool
	ExcludeMuted    bool
	ExcludeRead     bool
	ExcludeArchived bool
	IsChatList      bool
}

// GetFolders returns synced folders from the core, if the core supports them.
// Returns an empty list for cores that don't support folders.
func (e *Engine) GetFolders(accountID string) ([]FolderInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}

	// Check if the core supports folders via type assertion.
	type folderLister interface {
		GetFolders() ([]cores.Folder, error)
	}
	fl, ok := acc.Core.(folderLister)
	if !ok {
		// Core doesn't support folders — return empty list gracefully.
		return nil, nil
	}

	folders, err := fl.GetFolders()
	if err != nil {
		return nil, err
	}

	result := make([]FolderInfo, len(folders))
	for i, f := range folders {
		result[i] = FolderInfo{
			ID:              f.ID,
			Name:            f.Name,
			ChatIDs:         f.ChatIDs,
			ExcludeChatIDs:  f.ExcludeChatIDs,
			PinnedChatIDs:   f.PinnedChatIDs,
			Contacts:        f.Contacts,
			NonContacts:     f.NonContacts,
			Groups:          f.Groups,
			Channels:        f.Channels,
			Bots:            f.Bots,
			ExcludeMuted:    f.ExcludeMuted,
			ExcludeRead:     f.ExcludeRead,
			ExcludeArchived: f.ExcludeArchived,
			IsChatList:      f.IsChatList,
		}
	}
	return result, nil
}

type SuggestedFolderInfo struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	Contacts    bool   `json:"contacts,omitempty"`
	NonContacts bool   `json:"non_contacts,omitempty"`
	Groups      bool   `json:"groups,omitempty"`
	Channels    bool   `json:"channels,omitempty"`
	Bots        bool   `json:"bots,omitempty"`
}

func (e *Engine) GetSuggestedFolders(accountID string) ([]SuggestedFolderInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}

	type suggestedLister interface {
		GetSuggestedFolders() ([]cores.SuggestedFolder, error)
	}
	sl, ok := acc.Core.(suggestedLister)
	if !ok {
		return nil, nil
	}

	suggestions, err := sl.GetSuggestedFolders()
	if err != nil {
		return nil, err
	}

	result := make([]SuggestedFolderInfo, len(suggestions))
	for i, s := range suggestions {
		result[i] = SuggestedFolderInfo{
			Name:        s.Filter.Name,
			Description: s.Description,
			Contacts:    s.Filter.Contacts,
			NonContacts: s.Filter.NonContacts,
			Groups:      s.Filter.Groups,
			Channels:    s.Filter.Channels,
			Bots:        s.Filter.Bots,
		}
	}
	return result, nil
}

// DeleteFolder deletes a chat folder via the underlying core.
func (e *Engine) DeleteFolder(accountID, folderID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}

	// Try string-ID deleter first (Rubika).
	type folderDeleterStr interface {
		DeleteFolder(folderID string) error
	}
	if fd, ok := acc.Core.(folderDeleterStr); ok {
		return fd.DeleteFolder(folderID)
	}

	// Try int-ID deleter (Telegram).
	type folderDeleterInt interface {
		DeleteFolder(filterID int) error
	}
	if fd, ok := acc.Core.(folderDeleterInt); ok {
		id, err := strconv.Atoi(folderID)
		if err != nil {
			return fmt.Errorf("invalid folder ID %q for int-based core: %w", folderID, err)
		}
		return fd.DeleteFolder(id)
	}

	// Try int64-ID deleter (Bale).
	type folderDeleterInt64 interface {
		DeleteFolder(folderID int64) (map[string]interface{}, error)
	}
	if fd, ok := acc.Core.(folderDeleterInt64); ok {
		id, err := strconv.ParseInt(folderID, 10, 64)
		if err != nil {
			return fmt.Errorf("invalid folder ID %q for int64-based core: %w", folderID, err)
		}
		_, err = fd.DeleteFolder(id)
		return err
	}

	return fmt.Errorf("core does not support folder deletion")
}

// CreateFolderOpts contains filter flags for folder creation.
type CreateFolderOpts struct {
	Contacts    bool
	NonContacts bool
	Groups      bool
	Channels    bool
	Bots        bool
}

// CreateFolder creates a new folder via the underlying core.
func (e *Engine) CreateFolder(accountID, name string, chatIDs []string, opts *CreateFolderOpts) (*FolderInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}

	// Try extended creator (supports filter flags) first.
	type folderCreatorEx interface {
		CreateFolderWithFlags(name string, chatIDs []string, contacts, nonContacts, groups, channels, bots bool) (*cores.Folder, error)
	}
	if opts != nil {
		if fc, ok := acc.Core.(folderCreatorEx); ok {
			f, err := fc.CreateFolderWithFlags(name, chatIDs, opts.Contacts, opts.NonContacts, opts.Groups, opts.Channels, opts.Bots)
			if err != nil {
				return nil, err
			}
			return &FolderInfo{
				ID:          f.ID,
				Name:        f.Name,
				ChatIDs:     f.ChatIDs,
				Contacts:    f.Contacts,
				NonContacts: f.NonContacts,
				Groups:      f.Groups,
				Channels:    f.Channels,
				Bots:        f.Bots,
			}, nil
		}
	}

	// Fallback to basic creator.
	type folderCreator interface {
		CreateFolder(name string, chatIDs []string) (*cores.Folder, error)
	}
	fc, ok := acc.Core.(folderCreator)
	if !ok {
		return nil, fmt.Errorf("core does not support folder creation")
	}

	f, err := fc.CreateFolder(name, chatIDs)
	if err != nil {
		return nil, err
	}

	return &FolderInfo{
		ID:      f.ID,
		Name:    f.Name,
		ChatIDs: f.ChatIDs,
	}, nil
}

// GetFolderInviteLinks returns invite links for a chat folder.
func (e *Engine) GetFolderInviteLinks(accountID string, folderID int) ([]cores.ChatlistInviteLink, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	type linkGetter interface {
		GetFolderInviteLinks(folderID int) ([]cores.ChatlistInviteLink, error)
	}
	if lg, ok := acc.Core.(linkGetter); ok {
		return lg.GetFolderInviteLinks(folderID)
	}
	return nil, fmt.Errorf("core does not support folder invite links")
}

// CreateFolderInviteLink creates a shareable invite link for a folder.
func (e *Engine) CreateFolderInviteLink(accountID string, folderID int, title string, peerIDs []string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return "", fmt.Errorf("account not found: %s", accountID)
	}
	type linkCreator interface {
		ExportChatlistInvite(folderID int, title string, peerIDs []string) (string, error)
	}
	if lc, ok := acc.Core.(linkCreator); ok {
		return lc.ExportChatlistInvite(folderID, title, peerIDs)
	}
	return "", fmt.Errorf("core does not support folder invite links")
}

// EditFolderInviteLink modifies which peers are included in a folder invite link.
func (e *Engine) EditFolderInviteLink(accountID string, folderID int, slug string, peerIDs []string) (cores.ChatlistInviteLink, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return cores.ChatlistInviteLink{}, fmt.Errorf("account not found: %s", accountID)
	}
	type linkEditor interface {
		EditChatlistInvite(folderID int, slug string, peerIDs []string) (cores.ChatlistInviteLink, error)
	}
	if le, ok := acc.Core.(linkEditor); ok {
		return le.EditChatlistInvite(folderID, slug, peerIDs)
	}
	return cores.ChatlistInviteLink{}, fmt.Errorf("core does not support folder invite link editing")
}

// DeleteFolderInviteLink deletes a shareable invite link for a folder.
func (e *Engine) DeleteFolderInviteLink(accountID string, folderID int, slug string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	type linkDeleter interface {
		DeleteChatlistInvite(folderID int, slug string) error
	}
	if ld, ok := acc.Core.(linkDeleter); ok {
		return ld.DeleteChatlistInvite(folderID, slug)
	}
	return fmt.Errorf("core does not support folder invite links")
}

// GetLeaveChatlistSuggestions returns peer IDs the server suggests leaving when removing a chatlist folder.
func (e *Engine) GetLeaveChatlistSuggestions(accountID string, folderID int) ([]string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	type suggGetter interface {
		GetLeaveChatlistSuggestions(folderID int) ([]string, error)
	}
	if sg, ok := acc.Core.(suggGetter); ok {
		return sg.GetLeaveChatlistSuggestions(folderID)
	}
	return nil, fmt.Errorf("core does not support chatlist leave suggestions")
}

// LeaveChatlistFolder leaves a chatlist folder, optionally leaving selected peers.
func (e *Engine) LeaveChatlistFolder(accountID string, folderID int, peerIDs []string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	type chatlistLeaver interface {
		LeaveChatlistFolder(folderID int, peerIDs []string) error
	}
	if cl, ok := acc.Core.(chatlistLeaver); ok {
		return cl.LeaveChatlistFolder(folderID, peerIDs)
	}
	return fmt.Errorf("core does not support chatlist leave")
}

// emitChatUpdate reads the current chat state from DB and emits an update event.
func (e *Engine) emitChatUpdate(accountID, chatID string) {
	row := e.db.QueryRow(
		`SELECT c.account_id, c.chat_id, c.type, c.title, c.avatar_path,
		        c.last_msg_id, c.last_msg_text, c.last_msg_time, c.last_msg_sender,
		        c.last_msg_is_outgoing, c.last_msg_status, c.last_msg_media_type, c.last_msg_thumb_b64,
		        c.unread_count, c.is_muted, c.is_pinned, c.is_archived,
		        c.draft_text, c.member_count, c.parent_id,
		        COALESCE(u.is_bot, 0), COALESCE(u.is_contact, 0), COALESCE(u.is_blocked, 0),
		        c.unread_mark, c.unread_mention_count, c.unread_reaction_count,
		        c.is_verified, c.is_scam, c.is_fake
		 FROM chats c
		 LEFT JOIN users u ON c.account_id = u.account_id AND c.chat_id = u.user_id AND c.type = 1
		 WHERE c.account_id = ? AND c.chat_id = ?`, accountID, chatID)

	var c ChatInfo
	var avatarPath, lastMsgID, lastMsgText, lastMsgSender, draftText, parentID sql.NullString
	var lastMsgThumbB64 sql.NullString
	var lastMsgTime, memberCount sql.NullInt64
	var isMuted, isPinned, isArchived, lastMsgIsOutgoing, isBot int
	var isContact, isBlocked int
	var unreadMark, isVerified, isScam, isFake int

	err := row.Scan(
		&c.AccountID, &c.ChatID, &c.Type, &c.Title, &avatarPath,
		&lastMsgID, &lastMsgText, &lastMsgTime, &lastMsgSender,
		&lastMsgIsOutgoing, &c.LastMsgStatus, &c.LastMsgMediaType, &lastMsgThumbB64,
		&c.UnreadCount, &isMuted, &isPinned, &isArchived,
		&draftText, &memberCount, &parentID, &isBot, &isContact, &isBlocked,
		&unreadMark, &c.UnreadMentionCount, &c.UnreadReactionCount,
		&isVerified, &isScam, &isFake,
	)
	if err != nil {
		return
	}

	c.AvatarPath = avatarPath.String
	c.LastMsgID = lastMsgID.String
	c.LastMsgText = lastMsgText.String
	if lastMsgTime.Valid {
		c.LastMsgTime = lastMsgTime.Int64
	}
	c.LastMsgSender = lastMsgSender.String
	c.LastMsgIsOutgoing = lastMsgIsOutgoing == 1
	c.LastMsgThumbB64 = lastMsgThumbB64.String
	c.IsMuted = isMuted == 1
	c.IsPinned = isPinned == 1
	c.IsArchived = isArchived == 1
	c.DraftText = draftText.String
	if memberCount.Valid {
		c.MemberCount = int(memberCount.Int64)
	}
	c.ParentID = parentID.String
	c.IsBot = isBot == 1
	c.IsContact = isContact == 1
	c.IsBlocked = isBlocked == 1
	c.UnreadMark = unreadMark == 1
	c.IsVerified = isVerified == 1
	c.IsScam = isScam == 1
	c.IsFake = isFake == 1

	e.emitEvent(EventChatUpdated, accountID, ChatUpdatedEvent{Chat: c})
}

// GroupCallInfo is the group call data returned to the UI.
type GroupCallInfo struct {
	CallID            string                  `json:"call_id"`
	ChatID            string                  `json:"chat_id"`
	Title             string                  `json:"title"`
	ParticipantsCount int                     `json:"participants_count"`
	Participants      []GroupCallParticipant   `json:"participants"`
	Active            bool                    `json:"active"`
}

// GroupCallParticipant is a single participant in a group call.
type GroupCallParticipant struct {
	UserID      string `json:"user_id"`
	DisplayName string `json:"display_name"`
	IsMuted     bool   `json:"is_muted"`
	IsSpeaking  bool   `json:"is_speaking"`
	HasVideo    bool   `json:"has_video"`
	AvatarPath  string `json:"avatar_path,omitempty"`
}

// GetGroupCall checks whether a chat has an active group call and returns its info.
// Returns nil with no error if no group call is active.
func (e *Engine) GetGroupCall(accountID, chatID string) (*GroupCallInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	type groupCaller interface {
		GetGroupCall(chatID string) (*cores.CallSession, error)
	}
	gc, ok := acc.Core.(groupCaller)
	if !ok {
		return nil, nil // platform doesn't support group calls
	}
	cs, err := gc.GetGroupCall(chatID)
	if err != nil {
		return nil, nil // no active group call or error — treat as no call
	}
	if cs == nil || cs.State == cores.CallStateEnded {
		return nil, nil
	}

	info := &GroupCallInfo{
		CallID: cs.ID,
		ChatID: chatID,
		Active: true,
	}
	if title, ok := cs.Meta["title"]; ok {
		info.Title = title
	}
	if countStr, ok := cs.Meta["participants_count"]; ok {
		if n, err := strconv.Atoi(countStr); err == nil {
			info.ParticipantsCount = n
		}
	}
	for _, p := range cs.Participants {
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
	return info, nil
}

func (e *Engine) StartCall(accountID, chatID string, video bool) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return "", fmt.Errorf("account not connected: %s", accountID)
	}
	cs, err := acc.Core.StartCall(chatID, video)
	if err != nil {
		return "", err
	}
	if cs == nil {
		return "", fmt.Errorf("StartCall returned nil session")
	}
	return cs.ID, nil
}

// JoinGroupCall joins the active group call in a chat.
func (e *Engine) JoinGroupCall(accountID, chatID string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return "", fmt.Errorf("account not connected: %s", accountID)
	}
	cs, err := acc.Core.JoinGroupCall(chatID)
	if err != nil {
		return "", err
	}
	return cs.ID, nil
}

func (e *Engine) CreateConferenceCall(accountID string) (string, string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", "", fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return "", "", fmt.Errorf("account not connected: %s", accountID)
	}
	type confCreator interface {
		CreateConferenceCall() (string, string, error)
	}
	cc, ok := acc.Core.(confCreator)
	if !ok {
		return "", "", fmt.Errorf("conference calls not supported by this platform")
	}
	return cc.CreateConferenceCall()
}

func (e *Engine) SendCallRating(accountID, callID string, rating int, comment string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	type callRater interface {
		SendCallRating(callID string, rating int, comment string) error
	}
	cr, ok := acc.Core.(callRater)
	if !ok {
		return nil
	}
	return cr.SendCallRating(callID, rating, comment)
}

func (e *Engine) ClearCallHistory(accountID string, revoke bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	type callHistoryClearer interface {
		ClearCallHistory(revoke bool) error
	}
	cc, ok := acc.Core.(callHistoryClearer)
	if !ok {
		return nil
	}
	return cc.ClearCallHistory(revoke)
}

type CallHistoryEntry = cores.CallHistoryEntry

func (e *Engine) GetCallHistory(accountID string, offsetID int, limit int) ([]CallHistoryEntry, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	type callHistoryGetter interface {
		GetCallHistory(offsetID int, limit int) ([]CallHistoryEntry, error)
	}
	ch, ok := acc.Core.(callHistoryGetter)
	if !ok {
		return nil, nil
	}
	entries, err := ch.GetCallHistory(offsetID, limit)
	if err != nil {
		return nil, err
	}
	for i := range entries {
		if entries[i].PeerID != "" {
			var avatarPath sql.NullString
			_ = e.db.QueryRow(
				`SELECT avatar_path FROM chats WHERE account_id = ? AND chat_id = ?`,
				accountID, entries[i].PeerID,
			).Scan(&avatarPath)
			entries[i].AvatarPath = avatarPath.String
		}
	}
	return entries, nil
}

type BroadcastStatsGetter interface {
	GetBroadcastStats(chatID string) (map[string]interface{}, error)
}

type MegagroupStatsGetter interface {
	GetMegagroupStats(chatID string) (map[string]interface{}, error)
}

func (e *Engine) GetBroadcastStats(accountID, chatID string) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	getter, ok := acc.Core.(BroadcastStatsGetter)
	if !ok {
		return nil, fmt.Errorf("platform does not support broadcast stats")
	}
	return getter.GetBroadcastStats(chatID)
}

func (e *Engine) GetMegagroupStats(accountID, chatID string) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	getter, ok := acc.Core.(MegagroupStatsGetter)
	if !ok {
		return nil, fmt.Errorf("platform does not support megagroup stats")
	}
	return getter.GetMegagroupStats(chatID)
}
