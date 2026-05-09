package engine

import (
	"database/sql"
	"fmt"

	"uniclient/cores"
)

// SearchResult represents a message found via FTS5 search.
type SearchResult struct {
	AccountID  string `json:"account_id"`
	ChatID     string `json:"chat_id"`
	MsgID      string `json:"msg_id"`
	SenderName string `json:"sender_name,omitempty"`
	Text       string `json:"text"`
	Timestamp  int64  `json:"timestamp"`
	ChatTitle  string `json:"chat_title,omitempty"`
}

// SearchMessages performs a cross-account FTS5 search.
// If accountID is non-empty, restricts to that account.
func (e *Engine) SearchMessages(query string, accountID string, limit int) ([]SearchResult, error) {
	if limit <= 0 {
		limit = 50
	}
	if query == "" {
		return nil, nil
	}

	// FTS5 query syntax: wrap in quotes for exact phrase, or use as-is for OR matching.
	// Append * for prefix matching.
	ftsQuery := query + "*"

	var rows *sql.Rows
	var err error

	if accountID != "" {
		rows, err = e.db.Query(
			`SELECT m.account_id, m.chat_id, m.msg_id, m.sender_name, m.content_text, m.timestamp,
			        c.title
			 FROM messages m
			 JOIN messages_fts ON messages_fts.rowid = m.rowid
			 LEFT JOIN chats c ON c.account_id = m.account_id AND c.chat_id = m.chat_id
			 WHERE messages_fts MATCH ? AND m.account_id = ?
			 ORDER BY m.timestamp DESC
			 LIMIT ?`, ftsQuery, accountID, limit)
	} else {
		rows, err = e.db.Query(
			`SELECT m.account_id, m.chat_id, m.msg_id, m.sender_name, m.content_text, m.timestamp,
			        c.title
			 FROM messages m
			 JOIN messages_fts ON messages_fts.rowid = m.rowid
			 LEFT JOIN chats c ON c.account_id = m.account_id AND c.chat_id = m.chat_id
			 WHERE messages_fts MATCH ?
			 ORDER BY m.timestamp DESC
			 LIMIT ?`, ftsQuery, limit)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []SearchResult
	for rows.Next() {
		var r SearchResult
		var senderName, chatTitle sql.NullString
		if err := rows.Scan(&r.AccountID, &r.ChatID, &r.MsgID, &senderName, &r.Text, &r.Timestamp, &chatTitle); err != nil {
			return results, err
		}
		r.SenderName = senderName.String
		r.ChatTitle = chatTitle.String
		results = append(results, r)
	}
	return results, rows.Err()
}

// SearchChats searches chat titles across all accounts.
func (e *Engine) SearchChats(query string, limit int) ([]ChatInfo, error) {
	if limit <= 0 {
		limit = 20
	}
	if query == "" {
		return nil, nil
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
		        c.not_joined, c.join_request, c.can_post, c.is_admin, c.no_forwards
		 FROM chats c
		 LEFT JOIN users u ON c.account_id = u.account_id AND c.chat_id = u.user_id AND c.type = 1
		 WHERE c.title LIKE '%' || ? || '%'
		 ORDER BY c.last_msg_time DESC
		 LIMIT ?`, query, limit)
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

func (e *Engine) SearchGlobalChats(accountID, query string, limit int) ([]ChatInfo, error) {
	if query == "" {
		return nil, nil
	}
	if limit <= 0 {
		limit = 20
	}
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account not found: %s", accountID)
	}
	type globalSearcher interface {
		SearchGlobal(query string, opts cores.PaginationOpts) ([]cores.Dialog, error)
	}
	gs, ok := acc.Core.(globalSearcher)
	if !ok {
		return e.SearchChats(query, limit)
	}
	dialogs, err := gs.SearchGlobal(query, cores.PaginationOpts{Limit: limit})
	if err != nil {
		return e.SearchChats(query, limit)
	}
	var result []ChatInfo
	for _, d := range dialogs {
		result = append(result, ChatInfo{
			AccountID: accountID,
			ChatID:    d.ID,
			Title:     d.Title,
			Type:      chatTypeToInt(d.Type),
		})
	}
	return result, nil
}
