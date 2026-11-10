package cores

import (
	"fmt"
	"strconv"

	"github.com/gotd/td/tg"
)

func DiceValueFromEmoticon(emoticon string) int {
	switch emoticon {
	case "#":
		return 0
	case "1", "2", "3", "4", "5", "6":
		return int(emoticon[0]) - '0'
	}
	return -1
}

func MapDiceStickerSet(emoji string, docs []tg.DocumentClass, packs []tg.StickerPack) *DiceStickersResult {
	res := &DiceStickersResult{Emoji: emoji}

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
		for _, id := range order {
			ds := byID[id]
			ds.Value = len(res.Stickers)
			res.Stickers = append(res.Stickers, ds)
		}
		return res
	}

	for _, pack := range packs {
		v := DiceValueFromEmoticon(pack.Emoticon)
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

	res := MapDiceStickerSet(emoji, set.Documents, set.Packs)
	if len(res.Stickers) == 0 {
		return nil, fmt.Errorf("dice pack %q has no stickers", emoji)
	}
	return res, nil
}
