package engine

// Dice messages (slice 125): a dice/dart/basketball/football message's
// animation lives in a per-emoji special sticker set — the engine resolves
// the message's value to the pack document, rewrites the message's media
// row to that document and lets the normal download pipeline fetch the
// .tgs (the GUI renders it through the lottie player like a sticker).
// Slot-machine values compose several reel stickers (tdesktop builds a
// multi-sticker collage); UniClient honestly serves the plain emoji +
// value text for those instead of faking a collage (§1.10).

import (
	"encoding/json"
	"fmt"
	"time"

	"uniclient/cores"
)

// DiceStickersFetcher is implemented by cores with dice pack support.
type DiceStickersFetcher interface {
	GetDiceStickers(emoji string) (*cores.DiceStickersResult, error)
}

// dicePackCache memoizes one account's pack per emoji.
type dicePackCache struct {
	emoji string
	set   *cores.DiceStickersResult
	err   error
}

// diceMsgInfo is the parsed dice metadata of a cached message.
type diceMsgInfo struct {
	Emoji string
	Value int
}

// parseDiceExtra reads dice_emoji / dice_value from a message's raw JSON.
func parseDiceExtra(raw []byte) (diceMsgInfo, bool) {
	if len(raw) == 0 {
		return diceMsgInfo{}, false
	}
	var env struct {
		Extra struct {
			DiceEmoji string `json:"dice_emoji"`
			DiceValue int    `json:"dice_value"`
		} `json:"extra"`
	}
	if err := json.Unmarshal(raw, &env); err != nil {
		return diceMsgInfo{}, false
	}
	if env.Extra.DiceEmoji == "" {
		return diceMsgInfo{}, false
	}
	return diceMsgInfo{Emoji: env.Extra.DiceEmoji, Value: env.Extra.DiceValue}, true
}

// diceStickerForValue picks the pack document for a dice value: 0 = the
// rolling intro, 1..6 the outcome animation. Pure — unit-tested.
func diceStickerForValue(set *cores.DiceStickersResult, value int) *cores.DiceSticker {
	if set == nil {
		return nil
	}
	for i := range set.Stickers {
		if set.Stickers[i].Value == value {
			return &set.Stickers[i]
		}
	}
	return nil
}

// dicePackWanted reports which emoji a dice message needs ("" = none).
// The slot machine is out of scope for animation (see file comment).
func dicePackWanted(info diceMsgInfo) string {
	switch info.Emoji {
	case "🎲", "🎯", "⚽", "🏀":
		return info.Emoji
	}
	return ""
}

// EnsureDiceSticker resolves a dice message's animation document and routes
// it through the standard download pipeline:
//  1. read the message's dice emoji + value from the cache,
//  2. fetch (and memoize) the account's dice pack for that emoji,
//  3. rewrite the message's media row (seq 0) to the picked document,
//  4. enqueue the download at prefetch priority.
//
// Idempotent: a row already pointing at the right document is left alone
// (unless the previous download failed, which re-arms it).
func (e *Engine) EnsureDiceSticker(accountID, chatID, msgID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account not connected: %s", accountID)
	}
	fetcher, ok := acc.Core.(DiceStickersFetcher)
	if !ok {
		return fmt.Errorf("platform does not support dice stickers")
	}

	var raw []byte
	if err := e.db.QueryRow(
		"SELECT content_raw FROM messages WHERE account_id = ? AND chat_id = ? AND msg_id = ?",
		accountID, chatID, msgID).Scan(&raw); err != nil {
		return fmt.Errorf("message %s not found: %w", msgID, err)
	}
	info, ok := parseDiceExtra(raw)
	if !ok {
		return fmt.Errorf("message %s carries no dice data", msgID)
	}
	emoji := dicePackWanted(info)
	if emoji == "" {
		return fmt.Errorf("dice emoji %q has no animated pack support", info.Emoji)
	}

	// Memoized pack fetch per account+emoji (rolling → value swaps reuse it).
	cacheKey := accountID + "|" + emoji
	e.mu.Lock()
	cached := e.dicePacks[cacheKey]
	e.mu.Unlock()
	if cached == nil || (cached.set == nil && cached.err != nil) {
		set, err := fetcher.GetDiceStickers(emoji)
		e.mu.Lock()
		e.dicePacks[cacheKey] = &dicePackCache{emoji: emoji, set: set, err: err}
		e.mu.Unlock()
		cached = e.dicePacks[cacheKey]
	}
	if cached == nil || cached.set == nil {
		if cached != nil && cached.err != nil {
			return cached.err
		}
		return fmt.Errorf("dice pack %q unavailable", emoji)
	}

	doc := diceStickerForValue(cached.set, info.Value)
	if doc == nil {
		return fmt.Errorf("dice pack %q has no sticker for value %d", emoji, info.Value)
	}

	// Rewrite the media row unless it already points at this document
	// (and is not failed — a failed row re-arms the download).
	var curRef string
	var curState int
	err := e.db.QueryRow(
		"SELECT remote_ref, download_state FROM media WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = 0",
		accountID, chatID, msgID).Scan(&curRef, &curState)
	if err == nil && curRef == doc.FileID && curState != DownloadFailed {
		return nil // already resolved (in flight or complete)
	}

	fileName := info.Emoji + ".tgs"
	if info.Value != 0 {
		fileName = fmt.Sprintf("%s_%d.tgs", info.Emoji, info.Value)
	}
	if _, err := e.db.Exec(
		`UPDATE media SET remote_ref = ?, extra = ?, mime_type = ?, file_name = ?,
		                  local_path = '', download_state = ?, last_accessed = ?
		 WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = 0`,
		doc.FileID, doc.Extra, "application/x-tgsticker", fileName,
		DownloadNone, time.Now().UnixMilli(),
		accountID, chatID, msgID); err != nil {
		return fmt.Errorf("rewrite media row: %w", err)
	}

	return e.RequestDownload(accountID, chatID, msgID, 0, 2)
}
