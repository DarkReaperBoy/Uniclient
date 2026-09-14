package engine

import (
	"fmt"

	"uniclient/cores"
)

// Saved Messages sublists (slice 197): the scoped message page — the
// self-chat cache filtered by the new messages.saved_peer column (fed
// by every saved message the core converts, plus the fwd-from backfill),
// with messages.getSavedHistory as the cold-start server feed. The
// sublist LIST itself flows through the existing SavedSublistsFetcher
// surface (cores.SavedSublistInfo). Mirrors the forum-topic layer's
// shape: cache-fed scoped views stay current through the live update
// stream.

// savedHistoryCore is the server-side scoped fetch (messages.getSavedHistory).
type savedHistoryCore interface {
	GetSavedHistory(peerID string, offsetID, limit int) ([]cores.Message, error)
}

// SavedSublistsSupported reports whether the account's core exposes the
// saved-sublist surface (the list fetcher; Telegram today).
func (e *Engine) SavedSublistsSupported(accountID string) bool {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return false
	}
	_, ok = acc.Core.(SavedSublistsFetcher)
	return ok
}

// GetSavedSublistMessages returns one sublist's message page (newest
// first, like GetMessages): the self-chat cache filtered by saved_peer.
// peerID "" = the whole Saved Messages chat (all sublists). beforeMs = 0
// loads the latest page. A cold cache is fed by a server fetch
// (messages.getSavedHistory) before the filtered read, so the first open
// shows real rows; paged reads (beforeMs > 0) stay cache-only — the
// chat-wide loader keeps older rows coming (the forum-topic pattern).
func (e *Engine) GetSavedSublistMessages(accountID, savedChatID, peerID string, beforeMs int64, limit int) ([]CachedMessage, error) {
	if limit <= 0 {
		limit = 50
	}
	if beforeMs == 0 {
		if n := e.countSavedRows(accountID, savedChatID, peerID); n == 0 {
			e.fetchSavedHistory(accountID, peerID, 0, 100)
		}
	}
	return e.readSavedRows(accountID, savedChatID, peerID, beforeMs, limit)
}

// readSavedRows is the saved_peer-filtered cache read.
func (e *Engine) readSavedRows(accountID, savedChatID, peerID string, beforeMs int64, limit int) ([]CachedMessage, error) {
	q := `SELECT account_id, chat_id, msg_id, local_id, sender_id, sender_name, sender_rank, sender_color_id,
			content_text, content_raw, content_rich, timestamp, edited_at,
			status, reply_to_id, reply_preview, forward_from, forward_from_id, is_pinned, is_outgoing, is_service, has_media, grouped_id, no_forwards, is_deleted, deleted_at, paid_post_type, reactions_json, views, forwards, comments_count, thread_root, saved_peer
		FROM messages
		WHERE account_id = ? AND chat_id = ?`
	args := []interface{}{accountID, savedChatID}
	if peerID != "" {
		q += ` AND saved_peer = ?`
		args = append(args, peerID)
	}
	if beforeMs > 0 {
		q += ` AND timestamp < ?`
		args = append(args, beforeMs)
	}
	q += `
		AND NOT EXISTS (SELECT 1 FROM locally_hidden_messages h WHERE h.account_id = messages.account_id AND h.chat_id = messages.chat_id AND h.msg_id = messages.msg_id)
		` + shadowBanSQL + `
		ORDER BY timestamp DESC
		LIMIT ?`
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
	return e.applyAyuFilters(msgs), nil
}

// countSavedRows counts the scoped rows currently cached.
func (e *Engine) countSavedRows(accountID, savedChatID, peerID string) int {
	q := `SELECT COUNT(*) FROM messages WHERE account_id = ? AND chat_id = ?`
	args := []interface{}{accountID, savedChatID}
	if peerID != "" {
		q += ` AND saved_peer = ?`
		args = append(args, peerID)
	}
	var n int
	e.db.QueryRow(q, args...).Scan(&n)
	return n
}

// fetchSavedHistory pulls one sublist's (or the whole saved chat's)
// history through the core and caches it under the self chat (the rows
// carry their saved_peer, so the filter picks them up).
func (e *Engine) fetchSavedHistory(accountID, peerID string, offsetID, limit int) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return
	}
	dc, ok := acc.Core.(savedHistoryCore)
	if !ok {
		return
	}
	selfChat := e.SavedMessagesChatID(accountID)
	if selfChat == "" {
		return
	}
	msgs, err := dc.GetSavedHistory(peerID, offsetID, limit)
	if err != nil {
		return
	}
	for i := range msgs {
		e.cacheMessage(accountID, selfChat, &msgs[i])
	}
}

// ToggleSavedSublistPin pins/unpins one Saved Messages sublist
// (messages.toggleSavedDialogPin — the raw core wrapper already exists).
func (e *Engine) ToggleSavedSublistPin(accountID, peerID string, pinned bool) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type pinToggler interface {
		ToggleSavedDialogPin(peerID string, pinned bool) error
	}
	pt, ok := acc.Core.(pinToggler)
	if !ok {
		return fmt.Errorf("platform does not support saved sublists")
	}
	return pt.ToggleSavedDialogPin(peerID, pinned)
}

// ReorderSavedSublists (slice 204) changes the pinned-sublist order
// (messages.reorderPinnedSavedDialogs with force, so a stale server pin
// outside the passed order unpins instead of corrupting it).
func (e *Engine) ReorderSavedSublists(accountID string, peerIDs []string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}
	type reorderer interface {
		ReorderPinnedSavedDialogs(peerIDs []string) error
	}
	ro, ok := acc.Core.(reorderer)
	if !ok {
		return fmt.Errorf("platform does not support saved sublists")
	}
	return ro.ReorderPinnedSavedDialogs(peerIDs)
}
