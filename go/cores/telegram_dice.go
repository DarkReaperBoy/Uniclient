package cores

// telegram_dice.go — slice 125: dice sticker packs. Telegram dice messages
// (MessageMediaDice: 🎲 🎯 ⚽ 🏀, slot machine 🎰) render as animated .tgs
// stickers from a per-emoji special sticker set fetched via
// messages.getStickerSet(inputStickerSetDice). The set's packs list maps
// emoticons to documents — "#" is the rolling intro, "1".."6" the outcome
// animations — mirroring tdesktop's chat_helpers/stickers_dice_pack.cpp
// (verified against the tdesktop source, 2026-09-11). The GUI plays the
// roll loop until the message edit lands the value, then switches to the
// value's document and holds its last frame (tdesktop Dice behavior).

import (
	"fmt"
	"strconv"

	"github.com/gotd/td/tg"
)

// DiceSticker is one dice-pack document mapped to its game value.
type DiceSticker struct {
	Value    int
	FileID   string // document ID (remote_ref form)
	Extra    string // FileRef.Extra form: "accessHash:base64(fileReference)"
	ThumbB64 string
	Width    int
	Height   int
}

// DiceStickersResult is a dice emoji's resolved sticker pack.
type DiceStickersResult struct {
	Emoji    string
	Stickers []DiceSticker
}

// diceValueFromEmoticon maps a dice-set pack emoticon to its value slot:
// "#" → 0 (the rolling intro), "1".."6" → the outcome. Anything else is
// not part of the dice vocabulary. Pure.
func diceValueFromEmoticon(emoticon string) int {
	switch emoticon {
	case "#":
		return 0
	case "1", "2", "3", "4", "5", "6":
		return int(emoticon[0]) - '0'
	}
	return -1
}

// mapDiceStickerSet folds a messages.stickerSet response into the
// value→document mapping. Slot-machine sets (no pack emoticons) fall back
// to positional indexing like tdesktop. Pure — unit-tested.
func mapDiceStickerSet(emoji string, docs []tg.DocumentClass, packs []tg.StickerPack) *DiceStickersResult {
	res := &DiceStickersResult{Emoji: emoji}

	// Documents first (id → parsed sticker), stickers only.
	byID := make(map[int64]DiceSticker, len(docs))
	var order []int64
	for _, dc := range docs {
		d, ok := dc.(*tg.Document)
		if !ok {
			continue
		}
		isSticker := false
		ds := DiceSticker{
			FileID: strconv.FormatInt(d.ID, 10),
			Extra:  encodeFileExtra(d.AccessHash, d.FileReference),
		}
		for _, attr := range d.Attributes {
			switch a := attr.(type) {
			case *tg.DocumentAttributeSticker:
				isSticker = true
			case *tg.DocumentAttributeImageSize:
				ds.Width, ds.Height = int(a.W), int(a.H)
			case *tg.DocumentAttributeVideo:
				ds.Width, ds.Height = int(a.W), int(a.H)
			}
		}
		if !isSticker {
			continue
		}
		ds.ThumbB64 = extractStrippedThumbB64(d.Thumbs)
		byID[d.ID] = ds
		order = append(order, d.ID)
	}

	if len(packs) == 0 {
		// Slot machine: positional values.
		for _, id := range order {
			ds := byID[id]
			ds.Value = len(res.Stickers)
			res.Stickers = append(res.Stickers, ds)
		}
		return res
	}

	for _, pack := range packs {
		v := diceValueFromEmoticon(pack.Emoticon)
		if v < 0 {
			continue
		}
		for _, id := range pack.Documents {
			if ds, ok := byID[id]; ok {
				ds.Value = v
				res.Stickers = append(res.Stickers, ds)
			}
		}
	}
	return res
}

// GetDiceStickers fetches the dice sticker set for one game emoji
// (🎲 🎯 ⚽ 🏀 🎰) and maps its documents to values.
func (t *TelegramCore) GetDiceStickers(emoji string) (*DiceStickersResult, error) {
	t.mu.RLock()
	authed, api, ctx := t.authed, t.api, t.ctx
	t.mu.RUnlock()
	if !authed || api == nil {
		return nil, ErrAuth
	}
	if emoji == "" {
		return nil, fmt.Errorf("%w: empty dice emoji", ErrInvalidInput)
	}

	result, err := api.MessagesGetStickerSet(ctx, &tg.MessagesGetStickerSetRequest{
		Stickerset: &tg.InputStickerSetDice{
			Emoticon: emoji,
		},
		Hash: 0,
	})
	if err != nil {
		return nil, fmt.Errorf("get dice sticker set: %w", err)
	}
	set, ok := result.(*tg.MessagesStickerSet)
	if !ok {
		return nil, fmt.Errorf("get dice sticker set: unexpected response %T", result)
	}

	res := mapDiceStickerSet(emoji, set.Documents, set.Packs)
	if len(res.Stickers) == 0 {
		return nil, fmt.Errorf("dice pack %q has no stickers", emoji)
	}
	return res, nil
}
