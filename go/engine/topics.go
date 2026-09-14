package engine

import (
	"fmt"
	"log"
)

// Forum topics (slice 118, Telegram forum parity): the topic list comes from
// the core (GetForumTopics); message scoping filters the messages cache by
// topic_id (every forum message carries its topic anchor in the reply
// header — the core caches it). New topic messages keep landing in the cache
// through the live update stream, so topic views stay current.

// GetTopicMessages returns one forum topic's cached message page (newest
// first, like GetMessages). beforeMs = 0 loads the latest page.
func (e *Engine) GetTopicMessages(accountID, chatID, topicID string, beforeMs int64, limit int) ([]CachedMessage, error) {
	if limit <= 0 {
		limit = 50
	}
	if topicID == "" {
		return e.GetMessages(accountID, chatID, beforeMs, 0, limit)
	}

	q := `SELECT account_id, chat_id, msg_id, local_id, sender_id, sender_name, sender_rank, sender_color_id,
                content_text, content_raw, content_rich, timestamp, edited_at,
                status, reply_to_id, reply_preview, forward_from, forward_from_id, is_pinned, is_outgoing, is_service, has_media, grouped_id, no_forwards, is_deleted, deleted_at, paid_post_type, reactions_json, views, forwards, comments_count, thread_root, saved_peer
                FROM messages
                WHERE account_id = ? AND chat_id = ? AND topic_id = ?
                AND NOT EXISTS (SELECT 1 FROM locally_hidden_messages h WHERE h.account_id = messages.account_id AND h.chat_id = messages.chat_id AND h.msg_id = messages.msg_id)
                ` + shadowBanSQL + `
                ORDER BY timestamp DESC
                LIMIT ?`
	args := []interface{}{accountID, chatID, topicID, limit}
	if beforeMs > 0 {
		q = `SELECT account_id, chat_id, msg_id, local_id, sender_id, sender_name, sender_rank, sender_color_id,
                        content_text, content_raw, content_rich, timestamp, edited_at,
                        status, reply_to_id, reply_preview, forward_from, forward_from_id, is_pinned, is_outgoing, is_service, has_media, grouped_id, no_forwards, is_deleted, deleted_at, paid_post_type, reactions_json, views, forwards, comments_count, thread_root, saved_peer
                        FROM messages
                        WHERE account_id = ? AND chat_id = ? AND topic_id = ? AND timestamp < ?
                        AND NOT EXISTS (SELECT 1 FROM locally_hidden_messages h WHERE h.account_id = messages.account_id AND h.chat_id = messages.chat_id AND h.msg_id = messages.msg_id)
                        ` + shadowBanSQL + `
                        ORDER BY timestamp DESC
                        LIMIT ?`
		args = []interface{}{accountID, chatID, topicID, beforeMs, limit}
	}
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
	e.populateAdminRanks(accountID, chatID, msgs)
	e.populateSenderNoForwards(accountID, msgs)
	e.populateTranscriptions(accountID, chatID, msgs)
	log.Printf("[engine] GetTopicMessages(%s, %s, topic %s): %d rows", accountID, chatID, topicID, len(msgs))
	return e.applyAyuFilters(msgs), nil
}

// GetTopicMessagesAfter returns topic messages NEWER than afterMs
// (strict), newest-first, capped at limit — the topic-permalink jump's
// "load toward the present" half (slice 189; mirrors GetMessages'
// afterMs window). Empty topicID delegates to the chat-wide window.
func (e *Engine) GetTopicMessagesAfter(accountID, chatID, topicID string, afterMs int64, limit int) ([]CachedMessage, error) {
	if limit <= 0 {
		limit = 50
	}
	if topicID == "" {
		return e.GetMessages(accountID, chatID, 0, afterMs, limit)
	}
	q := `SELECT account_id, chat_id, msg_id, local_id, sender_id, sender_name, sender_rank, sender_color_id,
                content_text, content_raw, content_rich, timestamp, edited_at,
                status, reply_to_id, reply_preview, forward_from, forward_from_id, is_pinned, is_outgoing, is_service, has_media, grouped_id, no_forwards, is_deleted, deleted_at, paid_post_type, reactions_json, views, forwards, comments_count, thread_root, saved_peer
                FROM messages
                WHERE account_id = ? AND chat_id = ? AND topic_id = ? AND timestamp > ?
                AND NOT EXISTS (SELECT 1 FROM locally_hidden_messages h WHERE h.account_id = messages.account_id AND h.chat_id = messages.chat_id AND h.msg_id = messages.msg_id)
                ` + shadowBanSQL + `
                ORDER BY timestamp ASC
                LIMIT ?`
	rows, err := e.db.Query(q, accountID, chatID, topicID, afterMs, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	msgs, err := scanMessages(rows)
	if err != nil {
		return msgs, err
	}
	// ASC select, newest-first contract: reverse in place.
	for i, j := 0, len(msgs)-1; i < j; i, j = i+1, j-1 {
		msgs[i], msgs[j] = msgs[j], msgs[i]
	}
	e.populateMediaMetadata(msgs)
	e.populateReplyPreviews(msgs)
	return e.applyAyuFilters(msgs), nil
}

// ReorderPinnedForumTopics (slice 205) changes the pinned-topic order
// in a forum (messages.reorderPinnedForumTopics with force — stale
// server pins outside the passed order unpin instead of corrupting
// it, the same semantics the dialogs and saved-sublists reorders use).
func (e *Engine) ReorderPinnedForumTopics(accountID, chatID string, topicIDs []int) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type topicReorderer interface {
		ReorderPinnedForumTopics(chatID string, topicIDs []int) error
	}
	tr, ok := acc.Core.(topicReorderer)
	if !ok {
		return fmt.Errorf("platform does not support forum topics")
	}
	return tr.ReorderPinnedForumTopics(chatID, topicIDs)
}
