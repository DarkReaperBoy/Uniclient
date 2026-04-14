package engine

import (
	"database/sql"
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
		`SELECT account_id, chat_id, type, title, avatar_path,
		        last_msg_id, last_msg_text, last_msg_time, last_msg_sender,
		        unread_count, is_muted, is_pinned, is_archived,
		        draft_text, member_count, parent_id
		 FROM chats
		 WHERE title LIKE '%' || ? || '%'
		 ORDER BY last_msg_time DESC
		 LIMIT ?`, query, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanChats(rows)
}
