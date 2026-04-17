package engine

import (
	"database/sql"
	"fmt"
	"log"
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
	UnreadCount       int    `json:"unread_count"`
	IsMuted      bool   `json:"is_muted"`
	IsPinned     bool   `json:"is_pinned"`
	IsArchived   bool   `json:"is_archived"`
	DraftText    string `json:"draft_text,omitempty"`
	MemberCount  int    `json:"member_count,omitempty"`
	ParentID     string `json:"parent_id,omitempty"`
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
		`SELECT account_id, chat_id, type, title, avatar_path,
		        last_msg_id, last_msg_text, last_msg_time, last_msg_sender,
		        last_msg_is_outgoing,
		        unread_count, is_muted, is_pinned, is_archived,
		        draft_text, member_count, parent_id
		 FROM chats
		 WHERE is_archived = 0
		 ORDER BY is_pinned DESC, last_msg_time DESC
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
		`SELECT account_id, chat_id, type, title, avatar_path,
		        last_msg_id, last_msg_text, last_msg_time, last_msg_sender,
		        last_msg_is_outgoing,
		        unread_count, is_muted, is_pinned, is_archived,
		        draft_text, member_count, parent_id
		 FROM chats
		 WHERE account_id = ? AND is_archived = ?
		 ORDER BY is_pinned DESC, last_msg_time DESC
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
		var lastMsgTime sql.NullInt64
		var memberCount sql.NullInt64
		var isMuted, isPinned, isArchived, lastMsgIsOutgoing int

		if err := rows.Scan(
			&c.AccountID, &c.ChatID, &c.Type, &c.Title, &avatarPath,
			&lastMsgID, &lastMsgText, &lastMsgTime, &lastMsgSender,
			&lastMsgIsOutgoing,
			&c.UnreadCount, &isMuted, &isPinned, &isArchived,
			&draftText, &memberCount, &parentID,
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
		c.IsMuted = isMuted == 1
		c.IsPinned = isPinned == 1
		c.IsArchived = isArchived == 1
		c.DraftText = draftText.String
		if memberCount.Valid {
			c.MemberCount = int(memberCount.Int64)
		}
		c.ParentID = parentID.String

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
	if d.LastMessage != nil {
		lastMsgID = d.LastMessage.ID
		lastMsgText = d.LastMessage.Text
		if len(lastMsgText) > 100 {
			lastMsgText = lastMsgText[:100]
		}
		lastMsgSender = d.LastMessage.SenderName
		lastMsgTime = d.LastMessage.Timestamp.UnixMilli()
		if d.LastMessage.IsOutgoing {
			lastMsgIsOutgoing = 1
		}
	}

	_, err := e.db.Exec(
		`INSERT INTO chats (account_id, chat_id, type, title, last_msg_id, last_msg_text,
		                     last_msg_time, last_msg_sender, last_msg_is_outgoing,
		                     unread_count, is_muted, is_pinned,
		                     is_archived, member_count, parent_id, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		 ON CONFLICT(account_id, chat_id) DO UPDATE SET
		     type = excluded.type,
		     title = excluded.title,
		     last_msg_id = COALESCE(excluded.last_msg_id, chats.last_msg_id),
		     last_msg_text = COALESCE(excluded.last_msg_text, chats.last_msg_text),
		     last_msg_time = MAX(COALESCE(excluded.last_msg_time, 0), COALESCE(chats.last_msg_time, 0)),
		     last_msg_sender = COALESCE(excluded.last_msg_sender, chats.last_msg_sender),
		     last_msg_is_outgoing = CASE WHEN excluded.last_msg_time > COALESCE(chats.last_msg_time, 0) THEN excluded.last_msg_is_outgoing ELSE chats.last_msg_is_outgoing END,
		     unread_count = excluded.unread_count,
		     is_muted = excluded.is_muted,
		     is_pinned = excluded.is_pinned,
		     is_archived = excluded.is_archived,
		     member_count = excluded.member_count,
		     parent_id = excluded.parent_id,
		     updated_at = excluded.updated_at`,
		accountID, d.ID, chatType, d.Title, lastMsgID, lastMsgText,
		lastMsgTime, lastMsgSender, lastMsgIsOutgoing, d.UnreadCount, boolToInt(d.IsMuted), boolToInt(d.IsPinned),
		boolToInt(d.IsArchived), d.MemberCount, d.ParentID, now)
	return err
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
	return nil
}

// updateChatLastMessage updates the preview fields for a chat.
func (e *Engine) updateChatLastMessage(accountID, chatID, msgID, text, sender string, timeMs int64, isOutgoing bool) {
	outgoing := 0
	if isOutgoing {
		outgoing = 1
	}
	e.db.Exec(
		`UPDATE chats SET last_msg_id = ?, last_msg_text = ?, last_msg_sender = ?,
		                  last_msg_time = ?, last_msg_is_outgoing = ?, updated_at = ?
		 WHERE account_id = ? AND chat_id = ? AND (last_msg_time IS NULL OR last_msg_time <= ?)`,
		msgID, text, sender, timeMs, outgoing, time.Now().UnixMilli(), accountID, chatID, timeMs)
	e.emitChatUpdate(accountID, chatID)
}

// incrementUnread bumps the unread count for a chat.
func (e *Engine) incrementUnread(accountID, chatID string) {
	e.db.Exec(
		"UPDATE chats SET unread_count = unread_count + 1 WHERE account_id = ? AND chat_id = ?",
		accountID, chatID)
}

// MarkChatRead resets unread count to 0 and optionally calls core.MarkAsRead.
func (e *Engine) MarkChatRead(accountID, chatID, upToMsgID string) error {
	e.db.Exec(
		"UPDATE chats SET unread_count = 0 WHERE account_id = ? AND chat_id = ?",
		accountID, chatID)

	// Call through to core if available.
	if acc, ok := e.getAccount(accountID); ok && acc.Core != nil && upToMsgID != "" {
		acc.Core.MarkAsRead(chatID, upToMsgID)
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
func (e *Engine) MuteChat(accountID, chatID string, muted bool) error {
	_, err := e.db.Exec(
		"UPDATE chats SET is_muted = ? WHERE account_id = ? AND chat_id = ?",
		boolToInt(muted), accountID, chatID)
	if err != nil {
		return err
	}

	// Also call core.
	if acc, ok := e.getAccount(accountID); ok && acc.Core != nil {
		acc.Core.MuteChat(chatID, muted)
	}

	e.emitChatUpdate(accountID, chatID)
	return nil
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

	if archived {
		e.emitEvent(EventChatRemoved, accountID, ChatRemovedEvent{ChatID: chatID})
	} else {
		e.emitChatUpdate(accountID, chatID)
	}
	return nil
}

// GetForumTopics fetches forum topics for a chat from the core, caches them,
// and returns the list. Only works for cores that support topics (e.g. Telegram).
// Returns an empty list for cores that don't support forum topics.
func (e *Engine) GetForumTopics(accountID, chatID string) ([]ChatInfo, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}

	// Check if the core supports topics via type assertion.
	type forumTopicGetter interface {
		GetForumTopics(chatID string, limit int) ([]cores.Dialog, error)
	}
	ftg, ok := acc.Core.(forumTopicGetter)
	if !ok {
		// Core doesn't support forum topics — return empty list gracefully.
		return nil, nil
	}

	topics, err := ftg.GetForumTopics(chatID, 100)
	if err != nil {
		return nil, err
	}

	// Cache each topic as a chat entry.
	for _, t := range topics {
		if err := e.UpsertChat(accountID, t); err != nil {
			log.Printf("[engine] GetForumTopics: failed to cache topic %s: %v", t.ID, err)
		}
	}

	// Return from DB to get the fully populated ChatInfo structs.
	rows, err := e.db.Query(
		`SELECT account_id, chat_id, type, title, avatar_path,
		        last_msg_id, last_msg_text, last_msg_time, last_msg_sender,
		        last_msg_is_outgoing,
		        unread_count, is_muted, is_pinned, is_archived,
		        draft_text, member_count, parent_id
		 FROM chats
		 WHERE account_id = ? AND parent_id = ?
		 ORDER BY title ASC`, accountID, chatID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanChats(rows)
}

// FolderInfo represents a synced folder from the platform (e.g. Telegram folders).
type FolderInfo struct {
	ID      string
	Name    string
	ChatIDs []string
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
			ID:      f.ID,
			Name:    f.Name,
			ChatIDs: f.ChatIDs,
		}
	}
	return result, nil
}

// emitChatUpdate reads the current chat state from DB and emits an update event.
func (e *Engine) emitChatUpdate(accountID, chatID string) {
	row := e.db.QueryRow(
		`SELECT account_id, chat_id, type, title, avatar_path,
		        last_msg_id, last_msg_text, last_msg_time, last_msg_sender,
		        last_msg_is_outgoing,
		        unread_count, is_muted, is_pinned, is_archived,
		        draft_text, member_count, parent_id
		 FROM chats WHERE account_id = ? AND chat_id = ?`, accountID, chatID)

	var c ChatInfo
	var avatarPath, lastMsgID, lastMsgText, lastMsgSender, draftText, parentID sql.NullString
	var lastMsgTime, memberCount sql.NullInt64
	var isMuted, isPinned, isArchived, lastMsgIsOutgoing int

	err := row.Scan(
		&c.AccountID, &c.ChatID, &c.Type, &c.Title, &avatarPath,
		&lastMsgID, &lastMsgText, &lastMsgTime, &lastMsgSender,
		&lastMsgIsOutgoing,
		&c.UnreadCount, &isMuted, &isPinned, &isArchived,
		&draftText, &memberCount, &parentID,
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
	c.IsMuted = isMuted == 1
	c.IsPinned = isPinned == 1
	c.IsArchived = isArchived == 1
	c.DraftText = draftText.String
	if memberCount.Valid {
		c.MemberCount = int(memberCount.Int64)
	}
	c.ParentID = parentID.String

	e.emitEvent(EventChatUpdated, accountID, ChatUpdatedEvent{Chat: c})
}
