package engine

import (
	"fmt"

	"uniclient/cores"
)

// Channel-post comment threads (slice 195): the discussion-thread fetch
// (messages.getDiscussionMessage) with cache write-through, the thread
// filter (chat + reply-to-top root), and read marking.

// GetDiscussionThread fetches the comment thread of a channel post
// through the core, caches every row under its own discussion chat, and
// returns them newest-first (the GUI thread view contract).
func (e *Engine) GetDiscussionThread(accountID, chatID, msgID string) ([]CachedMessage, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return nil, fmt.Errorf("account %q not found or not connected", accountID)
	}
	type discussionFetcher interface {
		GetDiscussionThread(chatID, msgID string) ([]cores.Message, error)
	}
	df, ok := acc.Core.(discussionFetcher)
	if !ok {
		return nil, fmt.Errorf("platform does not support comment threads")
	}
	msgs, err := df.GetDiscussionThread(chatID, msgID)
	if err != nil {
		return nil, err
	}
	var discussionChat string
	for _, m := range msgs {
		if m.ChatID != "" {
			discussionChat = m.ChatID
			break
		}
	}
	for _, m := range msgs {
		e.cacheMessage(accountID, m.ChatID, &m)
	}
	if discussionChat == "" {
		return nil, nil
	}
	// The thread root: the first row that is its own root (the forwarded
	// post), else the earliest row's ThreadRoot.
	root := ""
	for _, m := range msgs {
		if m.ThreadRoot == m.ID {
			root = m.ID
			break
		}
	}
	if root == "" {
		for _, m := range msgs {
			if m.ThreadRoot != "" {
				root = m.ThreadRoot
				break
			}
		}
	}
	if root == "" {
		return nil, nil
	}
	return e.GetThreadMessages(accountID, discussionChat, root, 0, 100)
}

// GetThreadMessages returns one discussion thread (root + comments),
// newest-first, from the cache — the thread view's read path. beforeMs
// > 0 pages strictly older rows (the scroll-up loader).
func (e *Engine) GetThreadMessages(accountID, chatID, rootID string, beforeMs int64, limit int) ([]CachedMessage, error) {
	if limit <= 0 {
		limit = 50
	}
	q := `SELECT account_id, chat_id, msg_id, local_id, sender_id, sender_name, sender_rank, sender_color_id,
                        content_text, content_raw, content_rich, timestamp, edited_at,
                        status, reply_to_id, reply_preview, forward_from, forward_from_id, is_pinned, is_outgoing, is_service, has_media, grouped_id, no_forwards, is_deleted, deleted_at, paid_post_type, reactions_json, views, forwards, comments_count, thread_root, saved_peer
                 FROM messages
                 WHERE account_id = ? AND chat_id = ? AND (thread_root = ? OR msg_id = ?)`
	args := []interface{}{accountID, chatID, rootID, rootID}
	if beforeMs > 0 {
		q += ` AND timestamp < ?`
		args = append(args, beforeMs)
	}
	q += ` ORDER BY timestamp DESC LIMIT ?`
	args = append(args, limit)
	rows, err := e.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	msgs, err := scanMessages(rows)
	if err != nil {
		return msgs, err
	}
	e.populateMediaMetadata(msgs)
	e.populateReplyPreviews(msgs)
	e.populateSenderNoForwards(accountID, msgs)
	return msgs, nil
}

// ReadDiscussion marks the comment thread of a channel post read
// (messages.readDiscussion — tdesktop marks on open).
func (e *Engine) ReadDiscussion(accountID, chatID, msgID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type discussionReader interface {
		ReadDiscussion(chatID, msgID string) error
	}
	if r, ok := acc.Core.(discussionReader); ok {
		return r.ReadDiscussion(chatID, msgID)
	}
	return fmt.Errorf("platform does not support comment threads")
}
