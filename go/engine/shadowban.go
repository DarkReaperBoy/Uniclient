package engine

// Ayu shadow ban (matrix row 240): a per-chat local ignore list. Messages
// from a shadow-banned sender never render in that chat's local view —
// nothing is deleted server-side and the sender is never told (unlike a
// block, which cuts the connection). Bans live in the shadow_bans table
// (v47); GetMessages excludes them in SQL so the fetch windowing (the
// before/after cursor math) stays consistent — the same approach as the
// locally-hidden rows, and stronger than a post-scan (a page is never
// short-filled by hidden rows).

import (
	"database/sql"
	"fmt"
	"strings"
	"time"
)

// ShadowBan is one local per-chat shadow ban.
type ShadowBan struct {
	AccountID  string `json:"account_id"`
	ChatID     string `json:"chat_id"`
	SenderID   string `json:"sender_id"`
	SenderName string `json:"sender_name"`
	CreatedAt  int64  `json:"created_at"` // ms
}

// shadowBanSQL is the NOT EXISTS clause appended to every GetMessages
// branch. Keyed account+chat+sender: a ban in one chat does not affect
// the same user elsewhere (AyuGram semantics).
const shadowBanSQL = ` AND NOT EXISTS (SELECT 1 FROM shadow_bans s
                         WHERE s.account_id = messages.account_id
                           AND s.chat_id = messages.chat_id
                           AND s.sender_id = messages.sender_id)`

// ShadowBanSender adds or removes a local shadow ban. Empty senderID is
// rejected (own/service rows have none — callers gate on the message).
func (e *Engine) ShadowBanSender(accountID, chatID, senderID, senderName string, ban bool) error {
	if strings.TrimSpace(senderID) == "" {
		return fmt.Errorf("empty sender")
	}
	if strings.TrimSpace(accountID) == "" || strings.TrimSpace(chatID) == "" {
		return fmt.Errorf("shadow ban is per-chat (account and chat required)")
	}
	if ban {
		_, err := e.db.Exec(
			`INSERT OR REPLACE INTO shadow_bans (account_id, chat_id, sender_id, sender_name, created_at)
                         VALUES (?, ?, ?, ?, ?)`,
			accountID, chatID, senderID, senderName, time.Now().UnixMilli())
		return err
	}
	_, err := e.db.Exec(
		`DELETE FROM shadow_bans WHERE account_id = ? AND chat_id = ? AND sender_id = ?`,
		accountID, chatID, senderID)
	return err
}

// ListShadowBans returns the bans for one chat, newest first.
func (e *Engine) ListShadowBans(accountID, chatID string) []ShadowBan {
	rows, err := e.db.Query(
		`SELECT account_id, chat_id, sender_id, sender_name, created_at
                 FROM shadow_bans WHERE account_id = ? AND chat_id = ?
                 ORDER BY created_at DESC`, accountID, chatID)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []ShadowBan
	for rows.Next() {
		var b ShadowBan
		if err := rows.Scan(&b.AccountID, &b.ChatID, &b.SenderID, &b.SenderName, &b.CreatedAt); err != nil {
			continue
		}
		out = append(out, b)
	}
	return out
}

// IsShadowBanned reports whether the sender is banned in this chat.
// Best-effort: unreadable store = no ban (messages keep rendering).
func (e *Engine) IsShadowBanned(accountID, chatID, senderID string) bool {
	if senderID == "" {
		return false
	}
	var one int
	err := e.db.QueryRow(
		`SELECT 1 FROM shadow_bans WHERE account_id = ? AND chat_id = ? AND sender_id = ?`,
		accountID, chatID, senderID).Scan(&one)
	return err == nil
}

// CountShadowBans is the per-account total (for settings summaries).
func (e *Engine) CountShadowBans(accountID string) int {
	var n int
	if err := e.db.QueryRow(
		`SELECT COUNT(*) FROM shadow_bans WHERE account_id = ?`, accountID).Scan(&n); err != nil {
		return 0
	}
	return n
}

// dropShadowBanned removes banned senders' rows from an in-memory page
// (the live-fetch path returns freshly cached rows before any SQL
// exclusion runs). One ban-set read, then set lookup.
func (e *Engine) dropShadowBanned(accountID, chatID string, msgs []CachedMessage) []CachedMessage {
	bans := e.ListShadowBans(accountID, chatID)
	if len(bans) == 0 || len(msgs) == 0 {
		return msgs
	}
	banned := make(map[string]bool, len(bans))
	for _, b := range bans {
		banned[b.SenderID] = true
	}
	out := msgs[:0:0]
	for _, m := range msgs {
		if !banned[m.SenderID] {
			out = append(out, m)
		}
	}
	return out
}

var _ = sql.ErrNoRows
