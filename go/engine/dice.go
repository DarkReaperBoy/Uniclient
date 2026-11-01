package engine

import (
	"encoding/json"
	"fmt"
	"time"

	"uniclient/cores"
)

type DiceStickersFetcher interface {
	GetDiceStickers(emoji string) (*cores.DiceStickersResult, error)
}

type dicePackCache struct {
	emoji string
	set   *cores.DiceStickersResult
	err   error
}

type diceMsgInfo struct {
	Emoji string
	Value int
}

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

func dicePackWanted(info diceMsgInfo) string {
	switch info.Emoji {
	case "🎲", "🎯", "⚽", "🏀":
		return info.Emoji
	}
	return ""
}

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

	var curRef string
	var curState int
	err := e.db.QueryRow(
		"SELECT remote_ref, download_state FROM media WHERE account_id = ? AND chat_id = ? AND msg_id = ? AND seq = 0",
		accountID, chatID, msgID).Scan(&curRef, &curState)
	if err == nil && curRef == doc.FileID && curState != DownloadFailed {
		return nil
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
