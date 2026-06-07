package engine

import (
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
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
	IsAdmin              bool   `json:"is_admin,omitempty"`
	IsCreator            bool   `json:"is_creator,omitempty"`
	NoForwards           bool   `json:"no_forwards,omitempty"`
	IsSelf               bool   `json:"is_self,omitempty"`
	Username             string `json:"username,omitempty"`
	IsPremium            bool   `json:"is_premium,omitempty"`
	HasActiveCall        bool   `json:"has_active_call,omitempty"`
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
		        c.not_joined, c.join_request, c.can_post, c.is_admin, c.is_creator, c.no_forwards, c.username,
		        0, c.has_active_call
		 FROM chats c
		 LEFT JOIN users u ON c.account_id = u.account_id AND c.chat_id = u.user_id AND c.type = 1
		 ORDER BY c.is_archived ASC, c.is_pinned DESC, c.last_msg_time DESC
		 LIMIT ? OFFSET ?`, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	chats, err := scanChats(rows)
	if err != nil {
		return nil, err
	}
	e.markSelfChats(chats)
	return chats, nil
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
		        c.not_joined, c.join_request, c.can_post, c.is_admin, c.is_creator, c.no_forwards, c.username,
		        0, c.has_active_call
		 FROM chats c
		 LEFT JOIN users u ON c.account_id = u.account_id AND c.chat_id = u.user_id AND c.type = 1
		 WHERE c.account_id = ? AND c.is_archived = ?
		 ORDER BY c.is_pinned DESC, c.last_msg_time DESC
		 LIMIT ? OFFSET ?`, accountID, archivedInt, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	chats, err := scanChats(rows)
	if err != nil {
		return nil, err
	}
	e.markSelfChats(chats)
	return chats, nil
}

// markSelfChats sets IsSelf=true for DM chats where the chatID matches
// the account's own user ID (i.e. "Saved Messages").
func (e *Engine) markSelfChats(chats []ChatInfo) {
	// Build map of accountID → selfUserID.
	selfIDs := make(map[string]string)
	e.accountsMu.RLock()
	for id, acc := range e.accounts {
		if acc.Core == nil {
			continue
		}
		type selfIDer interface{ SelfUserID() string }
		if s, ok := acc.Core.(selfIDer); ok {
			if sid := s.SelfUserID(); sid != "" {
				selfIDs[id] = sid
			}
		}
	}
	e.accountsMu.RUnlock()

	for i := range chats {
		c := &chats[i]
		if c.Type == ChatTypeDMVal && c.ChatID == selfIDs[c.AccountID] {
			c.IsSelf = true
		}
	}
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
		var notJoined, joinRequestInt, canPostInt, isAdminInt, isCreatorInt, noForwardsInt int
		var isPremiumInt int
		var hasActiveCallInt int
		var writeRestrictionText, usernameN sql.NullString
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
			&notJoined, &joinRequestInt, &canPostInt, &isAdminInt, &isCreatorInt, &noForwardsInt,
			&usernameN, &isPremiumInt, &hasActiveCallInt,
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
		c.IsAdmin = isAdminInt == 1
		c.IsCreator = isCreatorInt == 1
		c.NoForwards = noForwardsInt == 1
		c.Username = usernameN.String
		c.IsPremium = isPremiumInt == 1
		c.HasActiveCall = hasActiveCallInt == 1

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
		                     not_joined, join_request, can_post, is_admin, is_creator, no_forwards, username, has_active_call, access_hash, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
		     is_admin = excluded.is_admin,
		     is_creator = excluded.is_creator,
		     no_forwards = excluded.no_forwards,
		     has_active_call = excluded.has_active_call,
		     username = COALESCE(excluded.username, chats.username),
		     access_hash = CASE WHEN excluded.access_hash != 0 THEN excluded.access_hash ELSE chats.access_hash END,
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
		boolToInt(d.NotJoined), boolToInt(d.JoinRequest), boolToInt(d.CanPost), boolToInt(d.IsAdmin), boolToInt(d.IsCreator), boolToInt(d.NoForwards), d.Username, boolToInt(d.HasActiveCall), d.AccessHash, now)
	if err != nil {
		return err
	}

	// Mark that this chat has a photo available for download.
	if d.AvatarURL != "" {
		e.markAvatarAvailable(accountID, d.ID)
	}

	return nil
}

// loadPeerHashes reads access hashes from the chats table and returns them
// split by peer type (channel vs user). Used to pre-populate the core's
// in-memory peer cache at connect time so API calls succeed before GetDialogs.
func (e *Engine) loadPeerHashes(accountID string) (channelHashes map[int64]int64, userHashes map[int64]int64) {
	channelHashes = make(map[int64]int64)
	userHashes = make(map[int64]int64)
	rows, err := e.db.Query("SELECT chat_id, access_hash FROM chats WHERE account_id = ? AND access_hash != 0", accountID)
	if err != nil {
		return
	}
	defer rows.Close()
	for rows.Next() {
		var chatID string
		var hash int64
		if err := rows.Scan(&chatID, &hash); err != nil {
			continue
		}
		id, err := strconv.ParseInt(chatID, 10, 64)
		if err != nil {
			continue
		}
		if id < 0 {
			absID := -id
			if absID > 1000000000000 {
				channelHashes[absID-1000000000000] = hash
			}
		} else if id > 0 {
			userHashes[id] = hash
		}
	}
	return
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

	if e.GhostFor(accountID).SendReadReceipts {
		if acc, ok := e.getAccount(accountID); ok && acc.Core != nil && upToMsgID != "" {
			acc.Core.MarkAsRead(chatID, upToMsgID)
		}
	}

	e.emitChatUpdate(accountID, chatID)
	return nil
}

// MarkAllChatsRead marks every chat with unread messages as read for the account.
// Also clears unread story flags and triggers server-side story read sync.
func (e *Engine) MarkAllChatsRead(accountID string) error {
	rows, err := e.db.Query(
		"SELECT chat_id, last_msg_id FROM chats WHERE account_id = ? AND (unread_count > 0 OR unread_mark = 1)",
		accountID)
	if err != nil {
		return err
	}
	defer rows.Close()

	type chatMsg struct {
		chatID    string
		lastMsgID string
	}
	var chats []chatMsg
	for rows.Next() {
		var cm chatMsg
		if err := rows.Scan(&cm.chatID, &cm.lastMsgID); err != nil {
			continue
		}
		chats = append(chats, cm)
	}

	for _, cm := range chats {
		e.MarkChatRead(accountID, cm.chatID, cm.lastMsgID)
	}

	// Clear unread story flags locally and trigger server-side story read sync.
	e.db.Exec(
		"UPDATE chats SET has_unread_story = 0 WHERE account_id = ? AND has_unread_story = 1",
		accountID)
	type storyReader interface {
		MarkAllStoriesRead() error
	}
	if acc, ok := e.getAccount(accountID); ok && acc.Core != nil {
		if sr, ok := acc.Core.(storyReader); ok {
			sr.MarkAllStoriesRead()
		}
	}
	return nil
}

// OpenSavedMessages ensures the "Saved Messages" chat exists in the local
// cache and emits a chat update so the Dart side can navigate to it.
func (e *Engine) OpenSavedMessages(accountID string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return "", fmt.Errorf("account not found: %s", accountID)
	}
	type selfIDer interface{ SelfUserID() string }
	s, ok := acc.Core.(selfIDer)
	if !ok {
		return "", fmt.Errorf("platform does not support self-user ID")
	}
	selfID := s.SelfUserID()
	if selfID == "" {
		return "", fmt.Errorf("self user ID not available")
	}

	var exists int
	e.db.QueryRow("SELECT COUNT(*) FROM chats WHERE account_id = ? AND chat_id = ?",
		accountID, selfID).Scan(&exists)
	if exists == 0 {
		e.db.Exec(
			`INSERT OR IGNORE INTO chats (account_id, chat_id, type, title, unread_count, is_pinned, is_archived, last_msg_time)
			 VALUES (?, ?, 1, 'Saved Messages', 0, 0, 0, ?)`,
			accountID, selfID, time.Now().UnixMilli())
	}
	e.emitChatUpdate(accountID, selfID)
	return selfID, nil
}

// RemoveBotFromMenu removes a bot from the side/attach menu.
func (e *Engine) RemoveBotFromMenu(accountID string, botID int64) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	type menuRemover interface {
		RemoveBotFromMenu(botID int64) error
	}
	r, ok := acc.Core.(menuRemover)
	if !ok {
		return fmt.Errorf("platform does not support removing bots from menu")
	}
	return r.RemoveBotFromMenu(botID)
}

func (e *Engine) MarkChatUnread(accountID, chatID string) error {
	e.db.Exec(
		"UPDATE chats SET unread_mark = 1 WHERE account_id = ? AND chat_id = ?",
		accountID, chatID)
	if acc, ok := e.getAccount(accountID); ok && acc.Core != nil {
		type unreadMarker interface {
			MarkUnread(chatID string, unread bool) error
		}
		if um, ok := acc.Core.(unreadMarker); ok {
			um.MarkUnread(chatID, true)
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

func (e *Engine) RemoveTopPeer(accountID, peerID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	type topPeerRemover interface {
		RemoveFromTopPeers(peerID string) error
	}
	r, ok := acc.Core.(topPeerRemover)
	if !ok {
		return fmt.Errorf("platform does not support removing top peers")
	}
	return r.RemoveFromTopPeers(peerID)
}

// ToggleSavedDialogPin pins or unpins a saved dialog sublist.
func (e *Engine) ToggleSavedDialogPin(accountID, peerID string, pinned bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	type savedDialogPinner interface {
		ToggleSavedDialogPin(peerID string, pinned bool) error
	}
	p, ok := acc.Core.(savedDialogPinner)
	if !ok {
		return fmt.Errorf("platform does not support saved dialog pinning")
	}
	return p.ToggleSavedDialogPin(peerID, pinned)
}

// MarkSavedSublistRead marks a saved messages sublist as read.
func (e *Engine) MarkSavedSublistRead(accountID, peerID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	return acc.Core.MarkAsRead(peerID, "")
}

// DeleteSavedSublistHistory deletes saved message history for a peer.
func (e *Engine) DeleteSavedSublistHistory(accountID, peerID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	type savedHistoryDeleter interface {
		DeleteSavedHistory(peerID string) error
	}
	d, ok := acc.Core.(savedHistoryDeleter)
	if !ok {
		return fmt.Errorf("platform does not support deleting saved history")
	}
	return d.DeleteSavedHistory(peerID)
}

// ReorderPinnedDialogs changes the display order of pinned chats.
func (e *Engine) ReorderPinnedDialogs(accountID string, chatIDs []string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	type pinnedDialogReorderer interface {
		ReorderPinnedDialogs(chatIDs []string) error
	}
	r, ok := acc.Core.(pinnedDialogReorderer)
	if !ok {
		return fmt.Errorf("platform does not support reordering pinned dialogs")
	}
	return r.ReorderPinnedDialogs(chatIDs)
}

// ReorderDialogFilters changes the display order of chat folders.
func (e *Engine) ReorderDialogFilters(accountID string, filterIDs []int) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	type filterReorderer interface {
		ReorderDialogFilters(ids []int) error
	}
	r, ok := acc.Core.(filterReorderer)
	if !ok {
		return fmt.Errorf("platform does not support reordering dialog filters")
	}
	return r.ReorderDialogFilters(filterIDs)
}

// ToggleDialogFilterTags enables or disables folder tags display (premium).
func (e *Engine) ToggleDialogFilterTags(accountID string, enabled bool) (bool, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return false, fmt.Errorf("account not found: %s", accountID)
	}
	type toggler interface {
		MessagesToggleDialogFilterTags(enabled bool) (bool, error)
	}
	t, ok := acc.Core.(toggler)
	if !ok {
		return false, fmt.Errorf("platform does not support dialog filter tags")
	}
	return t.MessagesToggleDialogFilterTags(enabled)
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

	topics, err := ftg.GetForumTopics(chatID, 20)
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

// GetForumTopicsWithOffset fetches forum topics with pagination offset parameters.
func (e *Engine) GetForumTopicsWithOffset(accountID, chatID string, offsetDate, offsetID, offsetTopic int) ([]cores.ForumTopic, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}

	type forumTopicOffsetGetter interface {
		GetForumTopicsWithOffset(chatID string, limit, offsetDate, offsetID, offsetTopic int) ([]cores.ForumTopic, error)
	}
	ftg, ok := acc.Core.(forumTopicOffsetGetter)
	if !ok {
		return nil, fmt.Errorf("platform does not support paginated forum topics")
	}

	topics, err := ftg.GetForumTopicsWithOffset(chatID, 500, offsetDate, offsetID, offsetTopic)
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
			log.Printf("[engine] GetForumTopicsWithOffset: failed to cache topic %s: %v", t.ID, err)
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
	Emoticon        string
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
			Emoticon:        f.Emoticon,
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

// CreateFolderOpts contains the COMPLETE filter definition for folder
// creation/edit, mirroring AyuGram's Data::ChatFilter collect() result: type
// flags + exclude flags + exclude/pinned peers + tag color + emoticon + static
// title. ColorIndex < 0 means "no tag color".
type CreateFolderOpts struct {
	Contacts        bool
	NonContacts     bool
	Groups          bool
	Channels        bool
	Bots            bool
	ExcludeMuted    bool
	ExcludeRead     bool
	ExcludeArchived bool
	ExcludeChatIDs  []string
	PinnedChatIDs   []string
	IsChatList      bool
	ColorIndex      int
	Emoticon        string
	StaticTitle     bool
}

// folderSaverFull is implemented by cores that can persist the full filter
// definition (include/exclude peers + every flag + color + emoticon) via a
// single updateDialogFilter call. filterID <= 0 creates a new folder.
type folderSaverFull interface {
	UpdateDialogFilterFull(filterID int, isChatList bool, name string,
		includeIDs, excludeIDs, pinnedIDs []string,
		contacts, nonContacts, groups, channels, bots bool,
		excludeMuted, excludeRead, excludeArchived bool,
		colorIndex int, emoticon string, staticTitle bool) (*cores.Folder, error)
}

func folderInfoFromCore(f *cores.Folder) *FolderInfo {
	return &FolderInfo{
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
		Emoticon:        f.Emoticon,
	}
}

// CreateFolder creates a new folder via the underlying core.
func (e *Engine) CreateFolder(accountID, name string, chatIDs []string, opts *CreateFolderOpts) (*FolderInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}

	// Preferred: full saver — persists exclude flags/peers, color and emoticon
	// in one shot (matches AyuGram saving the whole collect() result verbatim).
	if opts != nil {
		if fs, ok := acc.Core.(folderSaverFull); ok {
			f, err := fs.UpdateDialogFilterFull(0, false, name,
				chatIDs, opts.ExcludeChatIDs, opts.PinnedChatIDs,
				opts.Contacts, opts.NonContacts, opts.Groups, opts.Channels, opts.Bots,
				opts.ExcludeMuted, opts.ExcludeRead, opts.ExcludeArchived,
				opts.ColorIndex, opts.Emoticon, opts.StaticTitle)
			if err != nil {
				return nil, err
			}
			return folderInfoFromCore(f), nil
		}
	}

	// Fallback: extended creator (type flags only).
	type folderCreatorEx interface {
		CreateFolderWithFlags(name string, chatIDs []string, contacts, nonContacts, groups, channels, bots bool) (*cores.Folder, error)
	}
	if opts != nil {
		if fc, ok := acc.Core.(folderCreatorEx); ok {
			f, err := fc.CreateFolderWithFlags(name, chatIDs, opts.Contacts, opts.NonContacts, opts.Groups, opts.Channels, opts.Bots)
			if err != nil {
				return nil, err
			}
			return folderInfoFromCore(f), nil
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

// EditFolder overwrites an existing folder with the COMPLETE filter definition,
// mirroring AyuGram EditExistingFilter sending result.tl() via
// messages.updateDialogFilter (edit_filter_box.cpp:991-1003). Uses the same full
// saver as CreateFolder, preserving the existing filter id.
func (e *Engine) EditFolder(accountID, folderID, name string, chatIDs []string, opts *CreateFolderOpts) (*FolderInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	id, err := strconv.Atoi(folderID)
	if err != nil || id <= 0 {
		return nil, fmt.Errorf("invalid folder id: %s", folderID)
	}
	fs, ok := acc.Core.(folderSaverFull)
	if !ok {
		return nil, fmt.Errorf("core does not support folder editing")
	}
	if opts == nil {
		opts = &CreateFolderOpts{ColorIndex: -1}
	}
	f, err := fs.UpdateDialogFilterFull(id, opts.IsChatList, name,
		chatIDs, opts.ExcludeChatIDs, opts.PinnedChatIDs,
		opts.Contacts, opts.NonContacts, opts.Groups, opts.Channels, opts.Bots,
		opts.ExcludeMuted, opts.ExcludeRead, opts.ExcludeArchived,
		opts.ColorIndex, opts.Emoticon, opts.StaticTitle)
	if err != nil {
		return nil, err
	}
	return folderInfoFromCore(f), nil
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

func (e *Engine) AddChatToFolder(accountID, chatID, folderID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not found: %s", accountID)
	}
	type chatToFolderAdder interface {
		AddChatToFolder(chatID string, folderID int) error
	}
	fid, err := strconv.Atoi(folderID)
	if err != nil {
		return fmt.Errorf("invalid folder ID %q: %w", folderID, err)
	}
	if adder, ok := acc.Core.(chatToFolderAdder); ok {
		return adder.AddChatToFolder(chatID, fid)
	}
	return fmt.Errorf("core does not support adding chats to folders")
}

func (e *Engine) GetTopPeers(accountID string, limit int) ([]ChatInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if limit <= 0 {
		limit = 20
	}
	type topPeersLister interface {
		GetTopPeersList(limit int) ([]string, error)
	}
	lister, ok := acc.Core.(topPeersLister)
	if !ok {
		return nil, nil
	}
	peerIDs, err := lister.GetTopPeersList(limit)
	if err != nil {
		return nil, err
	}
	var result []ChatInfo
	for _, pid := range peerIDs {
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
			        c.not_joined, c.join_request, c.can_post, c.is_admin, c.is_creator, c.no_forwards, c.username,
			        0, c.has_active_call
			 FROM chats c
			 LEFT JOIN users u ON c.account_id = u.account_id AND c.chat_id = u.user_id AND c.type = 1
			 WHERE c.account_id = ? AND c.chat_id = ?`, accountID, pid)
		if err != nil {
			continue
		}
		chats, err := scanChats(rows)
		rows.Close()
		if err == nil && len(chats) > 0 {
			result = append(result, chats[0])
		}
	}
	return result, nil
}

// EditFolderInviteLink modifies the peers and/or custom title of a folder invite
// link. A non-empty title renames the link ("Name Link" action).
func (e *Engine) EditFolderInviteLink(accountID string, folderID int, slug string, peerIDs []string, title string) (cores.ChatlistInviteLink, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return cores.ChatlistInviteLink{}, fmt.Errorf("account not found: %s", accountID)
	}
	type linkEditor interface {
		EditChatlistInvite(folderID int, slug string, peerIDs []string, title string) (cores.ChatlistInviteLink, error)
	}
	if le, ok := acc.Core.(linkEditor); ok {
		return le.EditChatlistInvite(folderID, slug, peerIDs, title)
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
		        c.is_verified, c.is_scam, c.is_fake, c.is_admin, c.is_creator
		 FROM chats c
		 LEFT JOIN users u ON c.account_id = u.account_id AND c.chat_id = u.user_id AND c.type = 1
		 WHERE c.account_id = ? AND c.chat_id = ?`, accountID, chatID)

	var c ChatInfo
	var avatarPath, lastMsgID, lastMsgText, lastMsgSender, draftText, parentID sql.NullString
	var lastMsgThumbB64 sql.NullString
	var lastMsgTime, memberCount sql.NullInt64
	var isMuted, isPinned, isArchived, lastMsgIsOutgoing, isBot int
	var isContact, isBlocked int
	var unreadMark, isVerified, isScam, isFake, isAdminInt, isCreatorInt int

	err := row.Scan(
		&c.AccountID, &c.ChatID, &c.Type, &c.Title, &avatarPath,
		&lastMsgID, &lastMsgText, &lastMsgTime, &lastMsgSender,
		&lastMsgIsOutgoing, &c.LastMsgStatus, &c.LastMsgMediaType, &lastMsgThumbB64,
		&c.UnreadCount, &isMuted, &isPinned, &isArchived,
		&draftText, &memberCount, &parentID, &isBot, &isContact, &isBlocked,
		&unreadMark, &c.UnreadMentionCount, &c.UnreadReactionCount,
		&isVerified, &isScam, &isFake, &isAdminInt, &isCreatorInt,
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
	c.IsAdmin = isAdminInt == 1
	c.IsCreator = isCreatorInt == 1

	// Apply isSelf detection (not stored in DB, computed in-memory).
	if c.Type == ChatTypeDMVal {
		e.accountsMu.RLock()
		if acc, ok := e.accounts[accountID]; ok && acc.Core != nil {
			type selfIDer interface{ SelfUserID() string }
			if s, ok := acc.Core.(selfIDer); ok {
				if sid := s.SelfUserID(); sid != "" && c.ChatID == sid {
					c.IsSelf = true
				}
			}
		}
		e.accountsMu.RUnlock()
	}

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
	IsRtmp            bool                    `json:"is_rtmp,omitempty"`
	ScheduleDate      int64                   `json:"schedule_date,omitempty"`
	Origin            string                  `json:"origin,omitempty"`
}

// GroupCallParticipant is a single participant in a group call.
type GroupCallParticipant struct {
	UserID             string  `json:"user_id"`
	DisplayName        string  `json:"display_name"`
	IsMuted            bool    `json:"is_muted"`
	IsSpeaking         bool    `json:"is_speaking"`
	HasVideo           bool    `json:"has_video"`
	AvatarPath         string  `json:"avatar_path,omitempty"`
	CanSelfUnmute      bool    `json:"can_self_unmute"`
	RaisedHandRating   int64   `json:"raised_hand_rating,omitempty"`
	Volume             int     `json:"volume,omitempty"`
	AudioLevel         float64 `json:"audio_level,omitempty"`
	MutedByMe          bool    `json:"muted_by_me,omitempty"`
	Sounding           bool    `json:"sounding,omitempty"`
	AdditionalSounding bool    `json:"additional_sounding,omitempty"`
	AdditionalSpeaking bool    `json:"additional_speaking,omitempty"`
	SSRC               int32   `json:"ssrc,omitempty"`
	LastActive         int64   `json:"last_active,omitempty"`
	Date               int64   `json:"date,omitempty"`
	State              string  `json:"state,omitempty"` // "", "invited" or "calling" (conference rows)
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
	if v, ok := cs.Meta["is_rtmp"]; ok && v == "true" {
		info.IsRtmp = true
	}
	if v, ok := cs.Meta["schedule_date"]; ok {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			info.ScheduleDate = n
		}
	}
	if v, ok := cs.Meta["origin"]; ok {
		info.Origin = v
	}
	avatarDir := filepath.Join(e.mediaDir, accountID, "avatars")
	for _, p := range cs.Participants {
		gcp := GroupCallParticipant{
			UserID:             p.UserID,
			DisplayName:        p.DisplayName,
			IsMuted:            p.IsMuted,
			IsSpeaking:         p.IsSpeaking,
			HasVideo:           p.HasVideo,
			CanSelfUnmute:      p.CanSelfUnmute,
			RaisedHandRating:   p.RaisedHandRating,
			Volume:             p.Volume,
			AudioLevel:         p.AudioLevel,
			MutedByMe:          p.MutedByMe,
			Sounding:           p.Sounding,
			AdditionalSounding: p.AdditionalSounding,
			AdditionalSpeaking: p.AdditionalSpeaking,
			SSRC:               p.SSRC,
			LastActive:         p.LastActive,
			Date:               p.Date,
			State:              p.State,
		}
		avatarFile := filepath.Join(avatarDir, p.UserID+".jpg")
		if data, err := os.ReadFile(avatarFile); err == nil && len(data) > 0 {
			gcp.AvatarPath = base64.StdEncoding.EncodeToString(data)
		}
		info.Participants = append(info.Participants, gcp)
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

// JoinGroupCall joins the active group call in a chat, or creates one if none exists.
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
		type groupCallCreator interface {
			CreateGroupCall(chatID string, title string) (*cores.CallSession, error)
		}
		if creator, ok := acc.Core.(groupCallCreator); ok {
			cs, err = creator.CreateGroupCall(chatID, "")
			if err != nil {
				return "", fmt.Errorf("create group call: %w", err)
			}
		} else {
			return "", err
		}
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

func (e *Engine) InviteToConferenceCall(accountID, callID string, userIDs []string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	type confInviter interface {
		InviteToConferenceCall(callID string, userIDs []string) error
	}
	ci, ok := acc.Core.(confInviter)
	if !ok {
		return fmt.Errorf("conference call invites not supported by this platform")
	}
	return ci.InviteToConferenceCall(callID, userIDs)
}

// DeclineOutgoingConferenceInvite cancels an outgoing conference-call invite:
// discard=false stops the ring (keeps the invite), discard=true revokes it.
func (e *Engine) DeclineOutgoingConferenceInvite(accountID, callID, userID string, discard bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	type confInviteDecliner interface {
		DeclineOutgoingConferenceInvite(callID, userID string, discard bool) error
	}
	cd, ok := acc.Core.(confInviteDecliner)
	if !ok {
		return fmt.Errorf("conference call invites not supported by this platform")
	}
	return cd.DeclineOutgoingConferenceInvite(callID, userID, discard)
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

func (e *Engine) AcceptCall(accountID, callID string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return "", fmt.Errorf("account not connected: %s", accountID)
	}
	cs, err := acc.Core.AcceptCall(callID)
	if err != nil {
		return "", err
	}
	if cs == nil {
		return "", fmt.Errorf("AcceptCall returned nil session")
	}
	return cs.ID, nil
}

func (e *Engine) DeclineCall(accountID, callID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	return acc.Core.DeclineCall(callID)
}

func (e *Engine) EndCall(accountID, callID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	return acc.Core.EndCall(callID)
}

func (e *Engine) EndGroupCall(accountID, callID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	type groupCallEnder interface {
		EndGroupCall(callID string) error
	}
	if gc, ok := acc.Core.(groupCallEnder); ok {
		return gc.EndGroupCall(callID)
	}
	return fmt.Errorf("core does not support EndGroupCall")
}

func (e *Engine) LeaveGroupCall(accountID, callID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	type groupCallLeaver interface {
		LeaveGroupCall(callID string) error
	}
	if gc, ok := acc.Core.(groupCallLeaver); ok {
		return gc.LeaveGroupCall(callID)
	}
	return fmt.Errorf("core does not support LeaveGroupCall")
}

// GetGroupCallJoinAsPeers returns the identities the user can join a chat's
// group call as (yourself / your channels), via phone.getGroupCallJoinAs.
func (e *Engine) GetGroupCallJoinAsPeers(accountID, chatID string) ([]cores.JoinAsPeerInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	type joinAsLister interface {
		GetGroupCallJoinAsPeers(chatID string) ([]cores.JoinAsPeerInfo, error)
	}
	if gc, ok := acc.Core.(joinAsLister); ok {
		return gc.GetGroupCallJoinAsPeers(chatID)
	}
	return nil, fmt.Errorf("core does not support GetGroupCallJoinAsPeers")
}

// JoinGroupCallAs rejoins a chat's group call as the given identity (joinAsChatID).
func (e *Engine) JoinGroupCallAs(accountID, chatID, joinAsChatID string) (string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return "", fmt.Errorf("account not connected: %s", accountID)
	}
	type joinAsJoiner interface {
		JoinGroupCallAs(chatID, joinAsChatID string) (*cores.CallSession, error)
	}
	if gc, ok := acc.Core.(joinAsJoiner); ok {
		cs, err := gc.JoinGroupCallAs(chatID, joinAsChatID)
		if err != nil {
			return "", err
		}
		if cs == nil {
			return "", fmt.Errorf("JoinGroupCallAs returned nil session")
		}
		return cs.ID, nil
	}
	return "", fmt.Errorf("core does not support JoinGroupCallAs")
}

// SendGroupCallMessage sends an ephemeral message into a group call's message
// stream (NOT the permanent chat history), via phone.sendGroupCallMessage.
func (e *Engine) SendGroupCallMessage(accountID, chatID, text string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	type gcMessenger interface {
		SendGroupCallMessage(chatID, text string) error
	}
	if gc, ok := acc.Core.(gcMessenger); ok {
		return gc.SendGroupCallMessage(chatID, text)
	}
	return fmt.Errorf("core does not support SendGroupCallMessage")
}

// GetGroupCallScheduleSubscribed reports whether the user is subscribed to a
// scheduled group call's start reminder (real->scheduleStartSubscribed()).
func (e *Engine) GetGroupCallScheduleSubscribed(accountID, chatID string) (bool, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return false, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return false, fmt.Errorf("account not connected: %s", accountID)
	}
	type subChecker interface {
		GetGroupCallScheduleSubscribed(chatID string) (bool, error)
	}
	if gc, ok := acc.Core.(subChecker); ok {
		return gc.GetGroupCallScheduleSubscribed(chatID)
	}
	return false, fmt.Errorf("core does not support GetGroupCallScheduleSubscribed")
}

func (e *Engine) RaiseHand(accountID, callID string, raised bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	type handRaiser interface {
		RaiseHand(callID string, raised bool) error
	}
	if hr, ok := acc.Core.(handRaiser); ok {
		return hr.RaiseHand(callID, raised)
	}
	return fmt.Errorf("core does not support RaiseHand")
}

// EditGroupCallTitle renames a voice chat / livestream (manager-only).
func (e *Engine) EditGroupCallTitle(accountID, callID, title string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	type titleEditor interface {
		EditGroupCallTitle(callID, title string) error
	}
	if te, ok := acc.Core.(titleEditor); ok {
		return te.EditGroupCallTitle(callID, title)
	}
	return fmt.Errorf("core does not support EditGroupCallTitle")
}

// ToggleGroupCallRecord starts/stops server-side group-call recording.
func (e *Engine) ToggleGroupCallRecord(accountID, callID string, start bool, title string, video, videoPortrait bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	type recorder interface {
		ToggleGroupCallRecord(callID string, start bool, title string, video, videoPortrait bool) error
	}
	if r, ok := acc.Core.(recorder); ok {
		return r.ToggleGroupCallRecord(callID, start, title, video, videoPortrait)
	}
	return fmt.Errorf("core does not support ToggleGroupCallRecord")
}

// SetGroupCallMuteNewParticipants toggles default-mute-on-join (manager-only).
func (e *Engine) SetGroupCallMuteNewParticipants(accountID, callID string, muted bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	type joinMuteToggler interface {
		SetGroupCallMuteNewParticipants(callID string, muted bool) error
	}
	if jm, ok := acc.Core.(joinMuteToggler); ok {
		return jm.SetGroupCallMuteNewParticipants(callID, muted)
	}
	return fmt.Errorf("core does not support SetGroupCallMuteNewParticipants")
}

// SetGroupCallMessagesEnabled toggles in-call text messages (manager-only).
func (e *Engine) SetGroupCallMessagesEnabled(accountID, callID string, enabled bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	type messagesToggler interface {
		SetGroupCallMessagesEnabled(callID string, enabled bool) error
	}
	if mt, ok := acc.Core.(messagesToggler); ok {
		return mt.SetGroupCallMessagesEnabled(callID, enabled)
	}
	return fmt.Errorf("core does not support SetGroupCallMessagesEnabled")
}

// GetGroupCallVideoFrame returns the latest decoded incoming video frame for a
// stream kind ("camera"/"screen") as RGBA8888 + dimensions, or empty if none.
func (e *Engine) GetGroupCallVideoFrame(accountID, callID, endpoint string) ([]byte, int, int, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, 0, 0, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, 0, 0, fmt.Errorf("account not connected: %s", accountID)
	}
	type frameProvider interface {
		GetGroupCallVideoFrame(callID, endpoint string) ([]byte, int, int, error)
	}
	if fp, ok := acc.Core.(frameProvider); ok {
		return fp.GetGroupCallVideoFrame(callID, endpoint)
	}
	return nil, 0, 0, fmt.Errorf("core does not support GetGroupCallVideoFrame")
}

func (e *Engine) StartScheduledGroupCall(accountID, callID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	type scheduledStarter interface {
		StartScheduledGroupCall(callID string) error
	}
	if ss, ok := acc.Core.(scheduledStarter); ok {
		return ss.StartScheduledGroupCall(callID)
	}
	return fmt.Errorf("core does not support StartScheduledGroupCall")
}

func (e *Engine) ToggleGroupCallStartSubscription(accountID, callID string, subscribed bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	type subscriptionToggler interface {
		ToggleGroupCallStartSubscription(callID string, subscribed bool) error
	}
	if st, ok := acc.Core.(subscriptionToggler); ok {
		return st.ToggleGroupCallStartSubscription(callID, subscribed)
	}
	return fmt.Errorf("core does not support ToggleGroupCallStartSubscription")
}

func (e *Engine) SetNoiseSuppression(accountID, callID string, enabled bool) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.config.NoiseSuppression = enabled
	return e.vault.SetConfig(e.config)
}

func (e *Engine) GetAudioDevices(accountID, deviceType string) ([]string, error) {
	var devices []string
	switch deviceType {
	case "output":
		devices = e.enumerateAudioDevices("output")
	case "input":
		devices = e.enumerateAudioDevices("input")
	case "camera":
		devices = e.enumerateAudioDevices("camera")
	default:
		return nil, fmt.Errorf("unknown device type: %s", deviceType)
	}
	return devices, nil
}

// enumerateAudioDevices returns the real OS audio/video devices for the given
// type ("output", "input", or "camera"). The returned names deliberately do NOT
// include a "Default" entry — every Dart caller (settings_screen, call_panel,
// call_screen) prepends its own "Default" sentinel meaning "use the system
// default device", so adding one here would duplicate it.
//
// Pure Go, zero CGo. On Linux it prefers PulseAudio/PipeWire device names via
// `pactl` when that tool is present (friendly names matching the in-call picker
// and AyuGram), and always falls back to the ALSA proc filesystem
// (/proc/asound/*), which exists on every Linux machine even without pactl.
// Cameras come from /sys/class/video4linux. On platforms whose audio APIs need
// CGo (Windows WASAPI, macOS CoreAudio) the list is empty and callers fall back
// to "Default".
func (e *Engine) enumerateAudioDevices(deviceType string) []string {
	if runtime.GOOS != "linux" {
		return nil
	}
	if deviceType == "camera" {
		return enumerateV4L2Cameras()
	}
	if deviceType != "output" && deviceType != "input" {
		return nil
	}
	if devs := enumeratePulseDevices(deviceType); len(devs) > 0 {
		return devs
	}
	return enumerateAlsaDevices(deviceType)
}

// enumeratePulseDevices lists PulseAudio/PipeWire sinks (output) or sources
// (input) via `pactl list short`. Returns nil if pactl is unavailable so the
// caller can fall back to ALSA. Mirrors the name cleanup used by the in-call
// Linux picker (call_screen.dart) so both surfaces show identical labels.
func enumeratePulseDevices(deviceType string) []string {
	kind := "sinks"
	if deviceType == "input" {
		kind = "sources"
	}
	out, err := exec.Command("pactl", "list", "short", kind).Output()
	if err != nil {
		return nil
	}
	var devices []string
	seen := make(map[string]bool)
	for _, line := range strings.Split(string(out), "\n") {
		fields := strings.Split(strings.TrimSpace(line), "\t")
		if len(fields) < 2 {
			continue
		}
		raw := fields[1]
		// A PulseAudio ".monitor" source is the loopback of an output, not a
		// real microphone — skip it for the input list.
		if deviceType == "input" && strings.HasSuffix(raw, ".monitor") {
			continue
		}
		name := prettifyPulseName(raw)
		if name == "" || seen[name] {
			continue
		}
		seen[name] = true
		devices = append(devices, name)
	}
	return devices
}

// prettifyPulseName turns a raw PulseAudio device id into a human-readable name,
// matching the substitutions in call_screen.dart so the settings tab and the
// in-call picker display identical labels for the same device.
func prettifyPulseName(raw string) string {
	s := raw
	s = strings.ReplaceAll(s, "alsa_output.", "")
	s = strings.ReplaceAll(s, "alsa_input.", "")
	s = strings.ReplaceAll(s, ".analog-stereo", " (Analog Stereo)")
	s = strings.ReplaceAll(s, ".hdmi-stereo", " (HDMI Stereo)")
	s = strings.ReplaceAll(s, "_", " ")
	return strings.TrimSpace(s)
}

// enumerateAlsaDevices parses /proc/asound/pcm (always present on Linux) for PCM
// devices supporting the requested direction: "output" matches PCMs exposing a
// "playback" stream, "input" matches a "capture" stream. Each name is prefixed
// with the friendly card name from /proc/asound/cards.
func enumerateAlsaDevices(deviceType string) []string {
	data, err := os.ReadFile("/proc/asound/pcm")
	if err != nil {
		return nil
	}
	want := "playback"
	if deviceType == "input" {
		want = "capture"
	}
	cards := readAlsaCardNames()
	var devices []string
	seen := make(map[string]bool)
	for _, line := range strings.Split(string(data), "\n") {
		// Format: "CC-DD: <id> : <name> : playback N : capture N"
		fields := strings.Split(line, ":")
		if len(fields) < 2 {
			continue
		}
		// Direction lives only in the trailing "playback N"/"capture N" fields.
		hasDir := false
		for _, f := range fields[2:] {
			if strings.Contains(f, want) {
				hasDir = true
				break
			}
		}
		if !hasDir {
			continue
		}
		cardDev := strings.TrimSpace(fields[0]) // "01-00"
		cardIdx := cardDev
		if dash := strings.IndexByte(cardDev, '-'); dash > 0 {
			cardIdx = cardDev[:dash]
		}
		pcmName := strings.TrimSpace(fields[1])
		display := pcmName
		if idx, err := strconv.Atoi(cardIdx); err == nil {
			if cardName := cards[idx]; cardName != "" && !strings.Contains(pcmName, cardName) {
				display = cardName + " — " + pcmName
			}
		}
		if display == "" || seen[display] {
			continue
		}
		seen[display] = true
		devices = append(devices, display)
	}
	return devices
}

// readAlsaCardNames maps each ALSA card index to its human-readable long name
// from /proc/asound/cards (e.g. 1 -> "HDA Intel PCH").
func readAlsaCardNames() map[int]string {
	cards := make(map[int]string)
	data, err := os.ReadFile("/proc/asound/cards")
	if err != nil {
		return cards
	}
	for _, line := range strings.Split(string(data), "\n") {
		// Header lines: " 1 [PCH            ]: HDA-Intel - HDA Intel PCH"
		open := strings.IndexByte(line, '[')
		closeColon := strings.Index(line, "]:")
		if open < 0 || closeColon < open {
			continue
		}
		idx, err := strconv.Atoi(strings.TrimSpace(line[:open]))
		if err != nil {
			continue
		}
		bracketID := strings.TrimSpace(line[open+1 : closeColon])
		rest := strings.TrimSpace(line[closeColon+2:]) // "HDA-Intel - HDA Intel PCH"
		name := bracketID
		if i := strings.LastIndex(rest, " - "); i >= 0 {
			name = strings.TrimSpace(rest[i+3:])
		} else if rest != "" {
			name = rest
		}
		cards[idx] = name
	}
	return cards
}

// enumerateV4L2Cameras lists capture cameras from /sys/class/video4linux,
// reading each node's friendly name. A single physical camera can expose
// several /dev/videoN nodes that share a name; deduping by name collapses them.
func enumerateV4L2Cameras() []string {
	entries, err := os.ReadDir("/sys/class/video4linux")
	if err != nil {
		return nil
	}
	var cams []string
	seen := make(map[string]bool)
	for _, ent := range entries {
		devName := ent.Name()
		if !strings.HasPrefix(devName, "video") {
			continue
		}
		nameBytes, err := os.ReadFile("/sys/class/video4linux/" + devName + "/name")
		if err != nil {
			continue
		}
		camName := strings.TrimSpace(string(nameBytes))
		if camName == "" {
			camName = devName
		}
		if seen[camName] {
			continue
		}
		seen[camName] = true
		cams = append(cams, camName)
	}
	return cams
}

func (e *Engine) GetCallSoundPeak(accountID, callID string) (float64, error) {
	ms := time.Now().UnixMilli()
	ringCycleMs := int64(5000)
	ringOnMs := int64(1200)
	pos := ms % ringCycleMs
	if pos >= ringOnMs {
		return 0, nil
	}
	t := float64(pos) / float64(ringOnMs)
	env := math.Sin(t * math.Pi)
	wave := 0.5 + 0.5*math.Sin(t*2*math.Pi*8.0)
	peak := env * (0.3 + 0.7*wave)
	return peak, nil
}

func (e *Engine) GetGroupCallParticipantLevels(accountID, chatID string) (map[string]float64, error) {
	info, err := e.GetGroupCall(accountID, chatID)
	if err != nil || info == nil {
		return nil, err
	}
	levels := make(map[string]float64, len(info.Participants))
	ms := time.Now().UnixMilli()
	for _, p := range info.Participants {
		if p.IsMuted && !p.Sounding {
			levels[p.UserID] = 0
			continue
		}
		h := int64(0)
		for _, c := range p.UserID {
			h = h*31 + int64(c)
		}
		if h < 0 {
			h = -h
		}
		phaseMs := h % 7000
		cycleMs := int64(3000) + (h%3)*1000
		onMs := int64(1000) + (h%2)*500
		pos := (ms + phaseMs) % cycleMs
		if pos >= onMs {
			levels[p.UserID] = 0
			continue
		}
		t := float64(pos) / float64(onMs)
		env := math.Sin(t * math.Pi)
		freq := 5.0 + float64(h%8)
		wave := 0.5 + 0.5*math.Sin(t*2*math.Pi*freq)
		levels[p.UserID] = env * (0.2 + 0.8*wave)
	}
	return levels, nil
}

func (e *Engine) SetCallMuted(accountID, callID string, muted bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	return acc.Core.SetCallMuted(callID, muted)
}

type GroupCallParticipantMuter interface {
	MuteGroupCallParticipant(callID, userID string, mute bool) error
}

func (e *Engine) MuteGroupCallParticipant(accountID, callID, userID string, mute bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	m, ok := acc.Core.(GroupCallParticipantMuter)
	if !ok {
		return fmt.Errorf("participant muting not supported for this platform")
	}
	return m.MuteGroupCallParticipant(callID, userID, mute)
}

type GroupCallParticipantKicker interface {
	KickGroupCallParticipant(callID, userID string) error
}

func (e *Engine) KickGroupCallParticipant(accountID, callID, userID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	k, ok := acc.Core.(GroupCallParticipantKicker)
	if !ok {
		return fmt.Errorf("participant kicking not supported for this platform")
	}
	return k.KickGroupCallParticipant(callID, userID)
}

type GroupCallParticipantVolumer interface {
	SetGroupCallParticipantVolume(callID, userID string, volume int) error
}

func (e *Engine) SetGroupCallParticipantVolume(accountID, callID, userID string, volume int) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	v, ok := acc.Core.(GroupCallParticipantVolumer)
	if !ok {
		return fmt.Errorf("participant volume not supported for this platform")
	}
	return v.SetGroupCallParticipantVolume(callID, userID, volume)
}

func (e *Engine) ToggleCamera(accountID, callID string, enabled bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	return acc.Core.ToggleCamera(callID, enabled)
}

func (e *Engine) SetCallAudioDevice(accountID, deviceType, device string) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	switch deviceType {
	case "output":
		e.config.CallOutputDevice = device
	case "input":
		e.config.CallInputDevice = device
	case "camera":
		e.config.CallCameraDevice = device
	case "call_output":
		// Separate call-only output device (AyuGram callPlaybackDeviceId).
		// Empty value means "use the same device as the rest of the app".
		e.config.CallSeparateOutputDevice = device
	case "call_input":
		// Separate call-only input device (AyuGram callCaptureDeviceId).
		e.config.CallSeparateInputDevice = device
	default:
		return fmt.Errorf("unknown device type: %s", deviceType)
	}
	return e.vault.SetConfig(e.config)
}

type GroupCallScreenSharer interface {
	StartGroupCallScreenShare(callID string) error
	StopGroupCallScreenShare(callID string) error
}

func (e *Engine) ToggleScreenSharing(accountID, callID string, enabled bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	ss, ok := acc.Core.(GroupCallScreenSharer)
	if !ok {
		return fmt.Errorf("screen sharing not supported for this platform")
	}
	if enabled {
		return ss.StartGroupCallScreenShare(callID)
	}
	return ss.StopGroupCallScreenShare(callID)
}

type BroadcastStatsGetter interface {
	GetBroadcastStats(chatID string) (map[string]interface{}, error)
}

type MegagroupStatsGetter interface {
	GetMegagroupStats(chatID string) (map[string]interface{}, error)
}

type MessageStatsGetter interface {
	GetMessageStatsJSON(chatID string, msgID int) (map[string]interface{}, error)
	GetMessagePublicForwardsJSON(chatID string, msgID int, offset string) (map[string]interface{}, error)
}

type StatsGraphLoader interface {
	LoadStatsGraph(token string, x int64) (map[string]interface{}, error)
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

func (e *Engine) GetMessageStats(accountID, chatID string, msgID int) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	getter, ok := acc.Core.(MessageStatsGetter)
	if !ok {
		return nil, fmt.Errorf("platform does not support message stats")
	}
	return getter.GetMessageStatsJSON(chatID, msgID)
}

func (e *Engine) GetMorePublicForwards(accountID, chatID string, msgID int, offset string) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	getter, ok := acc.Core.(MessageStatsGetter)
	if !ok {
		return nil, fmt.Errorf("platform does not support public forwards")
	}
	return getter.GetMessagePublicForwardsJSON(chatID, msgID, offset)
}

func (e *Engine) LoadStatsGraph(accountID, token string, x int64) (map[string]interface{}, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	loader, ok := acc.Core.(StatsGraphLoader)
	if !ok {
		return nil, fmt.Errorf("platform does not support stats graph loading")
	}
	return loader.LoadStatsGraph(token, x)
}

type EmojiKeywordEntry struct {
	Keyword   string   `json:"keyword"`
	Emoticons []string `json:"emoticons"`
	// Deleted marks a server-diff row that removes a keyword→emoji mapping
	// (MTP emojiKeywordDeleted). Always false for the full (non-diff) fetch.
	Deleted bool `json:"deleted,omitempty"`
}

type EmojiKeywordsResult struct {
	LangCode string              `json:"lang_code"`
	Version  int                 `json:"version"`
	Keywords []EmojiKeywordEntry `json:"keywords"`
}

func (e *Engine) GetEmojiKeywords(accountID, langCode string) (*EmojiKeywordsResult, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	type emojiKeywordsFetcher interface {
		MessagesGetEmojiKeywords(langcode string) (interface{}, error)
	}
	fetcher, ok := acc.Core.(emojiKeywordsFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support emoji keywords")
	}
	raw, err := fetcher.MessagesGetEmojiKeywords(langCode)
	if err != nil {
		return nil, err
	}
	b, err := json.Marshal(raw)
	if err != nil {
		return nil, fmt.Errorf("failed to serialize emoji keywords: %w", err)
	}
	var diff struct {
		LangCode string `json:"LangCode"`
		Version  int    `json:"Version"`
		Keywords []struct {
			Keyword   string   `json:"Keyword"`
			Emoticons []string `json:"Emoticons"`
		} `json:"Keywords"`
	}
	if err := json.Unmarshal(b, &diff); err != nil {
		return nil, fmt.Errorf("failed to parse emoji keywords: %w", err)
	}
	result := &EmojiKeywordsResult{
		LangCode: diff.LangCode,
		Version:  diff.Version,
	}
	for _, kw := range diff.Keywords {
		if kw.Keyword != "" && len(kw.Emoticons) > 0 {
			result.Keywords = append(result.Keywords, EmojiKeywordEntry{
				Keyword:   kw.Keyword,
				Emoticons: kw.Emoticons,
			})
		}
	}
	return result, nil
}

func (e *Engine) GetEmojiKeywordsDifference(accountID, langCode string, fromVersion int) (*EmojiKeywordsResult, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	type emojiKeywordsDiffFetcher interface {
		MessagesGetEmojiKeywordsDifference(langCode string, fromVersion int) (interface{}, error)
	}
	fetcher, ok := acc.Core.(emojiKeywordsDiffFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support emoji keyword diffs")
	}
	raw, err := fetcher.MessagesGetEmojiKeywordsDifference(langCode, fromVersion)
	if err != nil {
		return nil, err
	}
	b, err := json.Marshal(raw)
	if err != nil {
		return nil, fmt.Errorf("failed to serialize emoji keyword diffs: %w", err)
	}
	var diff struct {
		LangCode string `json:"LangCode"`
		Version  int    `json:"Version"`
		Keywords []struct {
			Keyword   string   `json:"Keyword"`
			Emoticons []string `json:"Emoticons"`
			Deleted   bool     `json:"Deleted"`
		} `json:"Keywords"`
	}
	if err := json.Unmarshal(b, &diff); err != nil {
		return nil, fmt.Errorf("failed to parse emoji keyword diffs: %w", err)
	}
	result := &EmojiKeywordsResult{
		LangCode: diff.LangCode,
		Version:  diff.Version,
	}
	for _, kw := range diff.Keywords {
		result.Keywords = append(result.Keywords, EmojiKeywordEntry{
			Keyword:   kw.Keyword,
			Emoticons: kw.Emoticons,
			Deleted:   kw.Deleted,
		})
	}
	return result, nil
}

func (e *Engine) GetEmojiKeywordsLanguages(accountID string, langCodes []string) ([]string, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return nil, fmt.Errorf("account not connected: %s", accountID)
	}
	type emojiKeywordsLangsFetcher interface {
		MessagesGetEmojiKeywordsLanguages(langcodes []string) (interface{}, error)
	}
	fetcher, ok := acc.Core.(emojiKeywordsLangsFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support emoji keywords languages")
	}
	raw, err := fetcher.MessagesGetEmojiKeywordsLanguages(langCodes)
	if err != nil {
		return nil, err
	}
	b, err := json.Marshal(raw)
	if err != nil {
		return nil, fmt.Errorf("failed to serialize emoji keyword languages: %w", err)
	}
	var langs []struct {
		LangCode string `json:"LangCode"`
	}
	if err := json.Unmarshal(b, &langs); err != nil {
		return nil, fmt.Errorf("failed to parse emoji keyword languages: %w", err)
	}
	result := make([]string, 0, len(langs))
	for _, l := range langs {
		if l.LangCode != "" {
			result = append(result, l.LangCode)
		}
	}
	return result, nil
}
