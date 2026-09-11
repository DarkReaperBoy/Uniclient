package cores

// Dice sticker packs (slice 125): Telegram dice/dart/basketball/football
// messages render as .tgs animations from a special per-emoji sticker set
// (messages.getStickerSet(inputStickerSetDice)). The set's packs map
// emoticons to documents: "#" is the rolling intro, "1".."6" the outcome
// animations (tdesktop chat_helpers/stickers_dice_pack.cpp semantics —
// verified against the tdesktop source 2026-09-11). Pure mapping tests.

import (
	"encoding/base64"
	"strconv"
	"testing"

	"github.com/gotd/td/tg"
)

func TestDiceValueFromEmoticon(t *testing.T) {
	cases := []struct {
		in   string
		want int
	}{
		{"#", 0},
		{"1", 1},
		{"6", 6},
		{"0", -1},
		{"7", -1},
		{"", -1},
		{"12", -1},
		{"#1", -1},
	}
	for _, c := range cases {
		if got := diceValueFromEmoticon(c.in); got != c.want {
			t.Errorf("diceValueFromEmoticon(%q) = %d, want %d", c.in, got, c.want)
		}
	}
}

// diceDocs builds the raw document/pack structures of a dice set.
func diceDocs(t *testing.T) ([]tg.DocumentClass, []tg.StickerPack) {
	t.Helper()
	doc := func(id int64) tg.DocumentClass {
		return &tg.Document{
			ID:            id,
			AccessHash:    id * 17,
			FileReference: []byte{byte(id)},
			MimeType:      "application/x-tgsticker",
			Attributes: []tg.DocumentAttributeClass{
				&tg.DocumentAttributeSticker{Alt: "🎲"},
				&tg.DocumentAttributeImageSize{W: 512, H: 512},
			},
		}
	}
	return []tg.DocumentClass{doc(101), doc(102), doc(103)},
		[]tg.StickerPack{
			{Emoticon: "#", Documents: []int64{101}},
			{Emoticon: "1", Documents: []int64{102}},
			{Emoticon: "6", Documents: []int64{103}},
		}
}

func TestMapDiceStickerSet(t *testing.T) {
	docs, packs := diceDocs(t)
	res := mapDiceStickerSet("🎲", docs, packs)
	if res == nil || len(res.Stickers) != 3 {
		t.Fatalf("mapped stickers = %+v, want 3", res)
	}
	byValue := map[int]DiceSticker{}
	for _, s := range res.Stickers {
		byValue[s.Value] = s
	}
	if byValue[0].FileID != strconv.FormatInt(101, 10) {
		t.Errorf("roll sticker FileID = %q, want 101", byValue[0].FileID)
	}
	if byValue[6].FileID != strconv.FormatInt(103, 10) {
		t.Errorf("value-6 sticker FileID = %q, want 103", byValue[6].FileID)
	}
	// FileRef Extra form: "accessHash:base64(fileReference)".
	want := strconv.FormatInt(102*17, 10) + ":" + base64.StdEncoding.EncodeToString([]byte{102})
	if byValue[1].Extra != want {
		t.Errorf("extra = %q, want %q", byValue[1].Extra, want)
	}
	if byValue[1].Width != 512 || byValue[1].Height != 512 {
		t.Errorf("dims not parsed: %dx%d", byValue[1].Width, byValue[1].Height)
	}
}

func TestMapDiceStickerSetSlotMachine(t *testing.T) {
	// Slot machine packs are positional (no emoticon packs list).
	docs, _ := diceDocs(t)
	res := mapDiceStickerSet("🎰", docs, nil)
	if res == nil || len(res.Stickers) != 3 {
		t.Fatalf("slot stickers = %+v, want 3 positional", res)
	}
	for i, s := range res.Stickers {
		if s.Value != i {
			t.Errorf("slot[%d].Value = %d, want %d", i, s.Value, i)
		}
	}
}

func TestMapDiceStickerSetIgnoresNonStickers(t *testing.T) {
	docs := []tg.DocumentClass{
		&tg.Document{ID: 201, MimeType: "application/x-tgsticker", Attributes: []tg.DocumentAttributeClass{&tg.DocumentAttributeSticker{}}},
		&tg.Document{ID: 202, MimeType: "image/jpeg"}, // not a sticker
	}
	res := mapDiceStickerSet("🎲", docs, []tg.StickerPack{{Emoticon: "#", Documents: []int64{201, 202}}})
	if res == nil || len(res.Stickers) != 1 {
		t.Fatalf("stickers = %+v, want 1 (non-sticker dropped)", res)
	}
}
