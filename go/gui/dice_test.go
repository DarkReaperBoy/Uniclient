package gui

// Dice GUI helpers (slice 125): message parsing, the animated-emoji gate,
// hold-last-frame semantics and player re-parse on source swap.

import (
	"testing"
	"time"

	"uniclient/engine"
	"uniclient/lottie"
)

func diceRaw(emoji string, value int) []byte {
	return []byte(`{"extra":{"dice_emoji":"` + emoji + `","dice_value":` + itoa(value) + `}}`)
}

func TestParseDiceMessage(t *testing.T) {
	m := &engine.CachedMessage{ContentRaw: diceRaw("🎲", 5)}
	info, ok := parseDiceMessage(m)
	if !ok || info.Emoji != "🎲" || info.Value != 5 {
		t.Fatalf("parseDiceMessage = %+v ok=%v", info, ok)
	}
	if _, ok := parseDiceMessage(&engine.CachedMessage{}); ok {
		t.Error("empty message parsed as dice")
	}
	if _, ok := parseDiceMessage(nil); ok {
		t.Error("nil message parsed as dice")
	}
	m2 := &engine.CachedMessage{ContentRaw: []byte(`{"extra":{}}`)}
	if _, ok := parseDiceMessage(m2); ok {
		t.Error("extra without dice fields parsed as dice")
	}
}

func TestDiceAnimated(t *testing.T) {
	for _, e := range []string{"🎲", "🎯", "⚽", "🏀"} {
		if !diceAnimated(e) {
			t.Errorf("diceAnimated(%q) = false, want true", e)
		}
	}
	for _, e := range []string{"🎰", "🎉", ""} {
		if diceAnimated(e) {
			t.Errorf("diceAnimated(%q) = true, want false", e)
		}
	}
}

func TestDiceHoldLastFrame(t *testing.T) {
	if diceHoldLastFrame(0) {
		t.Error("rolling dice must loop, not hold")
	}
	for v := 1; v <= 6; v++ {
		if !diceHoldLastFrame(v) {
			t.Errorf("outcome value %d must hold its final frame", v)
		}
	}
}

func TestTgsFrameAtHold(t *testing.T) {
	anim := &lottie.Animation{FrameRate: 30, InPoint: 0, OutPoint: 90} // 3s
	// Looping mode wraps.
	if got := tgsFrameAt(anim, 7*time.Second, false); got != 30 {
		t.Errorf("loop mode = %v, want 30", got)
	}
	// Hold mode clamps at the out point.
	if got := tgsFrameAt(anim, 7*time.Second, true); got != 90 {
		t.Errorf("hold mode = %v, want 90 (clamped)", got)
	}
	if got := tgsFrameAt(anim, time.Second, true); got != 30 {
		t.Errorf("hold mid-animation = %v, want 30", got)
	}
	if got := tgsFrameAt(nil, time.Second, true); got != 0 {
		t.Errorf("hold nil = %v, want 0", got)
	}
}

func TestTgsPlayerPathSwap(t *testing.T) {
	c := &tgsPlayerCache{players: make(map[string]*tgsPlayer)}
	anim := &lottie.Animation{FrameRate: 30, InPoint: 0, OutPoint: 90}
	c.setAnim("m", "/cache/a.tgs", anim)
	p := c.get("m")
	if !p.parsed || p.path != "/cache/a.tgs" {
		t.Fatalf("setAnim state wrong: parsed=%v path=%q", p.parsed, p.path)
	}
	// A new source file for the same message resets the player.
	c.reset("m")
	p = c.get("m")
	if p.parsed || p.anim != nil || p.path != "" || p.failed {
		t.Fatalf("reset did not clear: %+v", p)
	}
	c.setAnim("m", "/cache/b.tgs", anim)
	if c.get("m").path != "/cache/b.tgs" {
		t.Error("path swap not recorded")
	}
}

func TestIsBareStickerMsgDice(t *testing.T) {
	if !isBareStickerMsg(&engine.CachedMessage{HasMedia: true, MediaType: engine.MediaDice}) {
		t.Error("dice message must render bare")
	}
	if isBareStickerMsg(&engine.CachedMessage{HasMedia: true, MediaType: engine.MediaDice, ContentText: "hi"}) {
		t.Error("dice with caption keeps the bubble")
	}
}

func TestMediaBlockKindDice(t *testing.T) {
	if got := mediaBlockKind(engine.MediaDice); got != "sticker" {
		t.Errorf("mediaBlockKind(MediaDice) = %q, want sticker", got)
	}
}
