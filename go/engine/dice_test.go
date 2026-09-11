package engine

// Dice engine helpers (slice 125): extra parsing, pack-value picking and
// the animated-emoji gate. The media-row rewrite + download flow rides the
// standard pipeline (covered by integration on live accounts).

import (
	"testing"

	"uniclient/cores"
)

func TestParseDiceExtra(t *testing.T) {
	info, ok := parseDiceExtra([]byte(`{"extra":{"dice_emoji":"🎲","dice_value":4}}`))
	if !ok || info.Emoji != "🎲" || info.Value != 4 {
		t.Fatalf("parseDiceExtra = %+v ok=%v", info, ok)
	}
	// Rolling state: value 0.
	info, ok = parseDiceExtra([]byte(`{"extra":{"dice_emoji":"🎯","dice_value":0}}`))
	if !ok || info.Emoji != "🎯" || info.Value != 0 {
		t.Fatalf("rolling parse = %+v ok=%v", info, ok)
	}
	// No dice data.
	if _, ok := parseDiceExtra([]byte(`{"extra":{"poll_question":"q"}}`)); ok {
		t.Error("non-dice extra parsed as dice")
	}
	if _, ok := parseDiceExtra(nil); ok {
		t.Error("empty raw parsed as dice")
	}
	if _, ok := parseDiceExtra([]byte(`not json`)); ok {
		t.Error("garbage parsed as dice")
	}
}

func TestDiceStickerForValue(t *testing.T) {
	set := &cores.DiceStickersResult{Emoji: "🎲", Stickers: []cores.DiceSticker{
		{Value: 0, FileID: "roll"},
		{Value: 1, FileID: "one"},
		{Value: 6, FileID: "six"},
	}}
	cases := []struct {
		value int
		want  string
	}{
		{0, "roll"},
		{1, "one"},
		{6, "six"},
		{4, ""}, // missing value → nil
	}
	for _, c := range cases {
		doc := diceStickerForValue(set, c.value)
		got := ""
		if doc != nil {
			got = doc.FileID
		}
		if got != c.want {
			t.Errorf("diceStickerForValue(%d) = %q, want %q", c.value, got, c.want)
		}
	}
	if diceStickerForValue(nil, 1) != nil {
		t.Error("nil set returned a sticker")
	}
}

func TestDicePackWanted(t *testing.T) {
	for _, e := range []string{"🎲", "🎯", "⚽", "🏀"} {
		if got := dicePackWanted(diceMsgInfo{Emoji: e}); got != e {
			t.Errorf("dicePackWanted(%q) = %q, want %q", e, got, e)
		}
	}
	for _, e := range []string{"🎰", "🎉", "", "🎲🎲"} {
		if got := dicePackWanted(diceMsgInfo{Emoji: e}); got != "" {
			t.Errorf("dicePackWanted(%q) = %q, want empty", e, got)
		}
	}
}
