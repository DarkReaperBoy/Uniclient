package engine

import (
	"database/sql"
	"fmt"
	"strings"
	"unicode"

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
// If chatID is non-empty, restricts to that chat.
// If topicID is non-empty, restricts to that forum topic.
// If senderID is non-empty, restricts to messages from that sender
// (the "Search from [user]" filter — AyuGram ChatSearchIn `_from`).
func (e *Engine) SearchMessages(query string, accountID string, limit int, chatID string, topicID string, senderID string) ([]SearchResult, error) {
	if limit <= 0 {
		limit = 50
	}
	if query == "" {
		return nil, nil
	}

	ftsQuery := buildFTSMatch(query)
	if ftsQuery == "" {
		// The query had no tokenizable characters (e.g. just "#"): there is
		// nothing for FTS5 to match, so return no results instead of erroring.
		return nil, nil
	}

	selectCols := `SELECT m.account_id, m.chat_id, m.msg_id, m.sender_name, m.content_text, m.timestamp,
		        c.title
		 FROM messages m
		 JOIN messages_fts ON messages_fts.rowid = m.rowid
		 LEFT JOIN chats c ON c.account_id = m.account_id AND c.chat_id = m.chat_id`

	where := ` WHERE messages_fts MATCH ?`
	args := []interface{}{ftsQuery}

	if accountID != "" {
		where += ` AND m.account_id = ?`
		args = append(args, accountID)
	}
	if chatID != "" {
		where += ` AND m.chat_id = ?`
		args = append(args, chatID)
	}
	if topicID != "" {
		where += ` AND m.topic_id = ?`
		args = append(args, topicID)
	}
	if senderID != "" {
		where += ` AND m.sender_id = ?`
		args = append(args, senderID)
	}

	where += ` ORDER BY m.timestamp DESC LIMIT ?`
	args = append(args, limit)

	rows, err := e.db.Query(selectCols+where, args...)
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

// buildFTSMatch turns a raw user search string into a safe FTS5 MATCH
// expression. Each whitespace-separated token is wrapped in double quotes (with
// embedded quotes doubled per FTS5's escaping rules) so that FTS5 syntax
// characters in user input — '#', ':', '^', '(', ')', '*', '"', '-', etc. — are
// treated as literal text rather than query operators. Without this a query
// like "#bitcoin" produced `SQL logic error: fts5: syntax error near "#"`.
// The final token keeps a trailing '*' for search-as-you-type prefix matching,
// preserving the previous `query + "*"` behavior. Tokens that contain no
// letters or digits tokenize to nothing under the unicode61 tokenizer and are
// dropped to avoid empty-phrase syntax errors; if every token drops out the
// result is "" and the caller treats it as "no results".
func buildFTSMatch(query string) string {
	tokens := strings.Fields(query)
	parts := make([]string, 0, len(tokens))
	for _, t := range tokens {
		if !hasTokenRune(t) {
			continue
		}
		parts = append(parts, `"`+strings.ReplaceAll(t, `"`, `""`)+`"`)
	}
	if len(parts) == 0 {
		return ""
	}
	parts[len(parts)-1] += "*"
	return strings.Join(parts, " ")
}

// hasTokenRune reports whether s contains at least one rune that the unicode61
// tokenizer treats as a token character (a Unicode letter or digit).
func hasTokenRune(s string) bool {
	for _, r := range s {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			return true
		}
	}
	return false
}

// CountMessagesFrom counts messages from a specific sender in a chat (local cache).
func (e *Engine) CountMessagesFrom(accountID, chatID, senderID string) (int, error) {
	var count int
	err := e.db.QueryRow(
		`SELECT COUNT(*) FROM messages WHERE account_id = ? AND chat_id = ? AND sender_id = ?`,
		accountID, chatID, senderID,
	).Scan(&count)
	return count, err
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
		        c.not_joined, c.join_request, c.can_post, c.is_admin, c.is_creator, c.no_forwards, c.username,
		        0, c.has_active_call
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

func (e *Engine) SearchGlobalPosts(accountID, query string, limit int) ([]ChatInfo, error) {
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
	type postsSearcher interface {
		SearchGlobalPosts(query string, opts cores.PaginationOpts) ([]cores.Dialog, error)
	}
	ps, ok := acc.Core.(postsSearcher)
	if !ok {
		chats, err := e.SearchGlobalChats(accountID, query, limit)
		if err != nil {
			return nil, err
		}
		var filtered []ChatInfo
		for _, c := range chats {
			if c.Type == 3 {
				filtered = append(filtered, c)
			}
		}
		return filtered, nil
	}
	dialogs, err := ps.SearchGlobalPosts(query, cores.PaginationOpts{Limit: limit})
	if err != nil {
		return nil, err
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

func (e *Engine) SearchGlobalPostMessages(accountID, query string, limit int) ([]SearchResult, error) {
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
	type postMessageSearcher interface {
		SearchGlobalPostMessages(query string, limit int) ([]cores.Message, error)
	}
	pm, ok := acc.Core.(postMessageSearcher)
	if !ok {
		return nil, nil
	}
	msgs, err := pm.SearchGlobalPostMessages(query, limit)
	if err != nil {
		return nil, err
	}
	var results []SearchResult
	for _, m := range msgs {
		chatTitle := ""
		if e.db != nil {
			_ = e.db.QueryRow("SELECT title FROM chats WHERE account_id = ? AND chat_id = ?", accountID, m.ChatID).Scan(&chatTitle)
		}
		results = append(results, SearchResult{
			AccountID:  accountID,
			ChatID:     m.ChatID,
			MsgID:      m.ID,
			SenderName: m.SenderName,
			Text:       m.Text,
			Timestamp:  m.Timestamp.Unix(),
			ChatTitle:  chatTitle,
		})
	}
	return results, nil
}
