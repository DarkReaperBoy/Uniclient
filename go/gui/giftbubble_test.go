package gui

import (
	"encoding/json"
	"testing"

	"uniclient/engine"
)

// Gift card bubbles (slice 180, GUI half): pure logic — parseGift over
// the cached message's Extra (gift_* fields written by the telegram
// core's convertServiceMessage), stars formatting, bubble gating.
// Layout verified by compile + review.

func giftMessage(extra map[string]interface{}) *engine.CachedMessage {
	env := struct {
		Extra map[string]interface{} `json:"extra"`
	}{Extra: extra}
	raw, _ := json.Marshal(env)
	return &engine.CachedMessage{
		AccountID:   "a",
		ChatID:      "c",
		MsgID:       "1",
		IsService:   true,
		ContentText: "Al sent a gift",
		ContentRaw:  raw,
	}
}

func TestParseGift(t *testing.T) {
	m := giftMessage(map[string]interface{}{
		"gift_kind":      "stargift",
		"gift_stars":     float64(100),
		"gift_text":      "Happy birthday!",
		"gift_thumb_b64": "aGk=",
		"gift_limited":   true,
		"gift_saved":     true,
		"gift_converted": false,
		"gift_refunded":  false,
	})
	g := parseGift(m)
	if g == nil {
		t.Fatal("gift not parsed")
	}
	if g.Kind != "stargift" || g.Stars != 100 || g.Text != "Happy birthday!" {
		t.Fatalf("gift = %+v", g)
	}
	if g.ThumbB64 != "aGk=" || !g.Limited || !g.Saved || g.Converted || g.Refunded {
		t.Fatalf("flags = %+v", g)
	}

	// Stars gift.
	m2 := giftMessage(map[string]interface{}{
		"gift_kind":  "stars",
		"gift_stars": float64(75),
	})
	g2 := parseGift(m2)
	if g2 == nil || g2.Kind != "stars" || g2.Stars != 75 {
		t.Fatalf("stars gift = %+v", g2)
	}

	// Plain service message → nil (never a gift bubble).
	if parseGift(giftMessage(map[string]interface{}{"service_action": "gift_stars"})) != nil {
		t.Fatal("message without gift_kind parsed as gift")
	}
	if parseGift(&engine.CachedMessage{IsService: true, ContentText: "hi"}) != nil {
		t.Fatal("raw-less message parsed as gift")
	}
}

func TestGiftStarsText(t *testing.T) {
	if got := giftStarsText(1); got != "1 Star" {
		t.Fatalf("1 star = %q", got)
	}
	if got := giftStarsText(75); got != "75 Stars" {
		t.Fatalf("75 stars = %q", got)
	}
	if got := giftStarsText(0); got != "" {
		t.Fatalf("0 stars = %q", got)
	}
}

func TestGiftBubbleVisible(t *testing.T) {
	// A parsed gift renders the card, regardless of service framing.
	g := &giftData{Kind: "stargift", Stars: 100}
	if !giftBubbleVisible(g) {
		t.Fatal("stargift must render the card")
	}
	if giftBubbleVisible(nil) {
		t.Fatal("nil gift must not render the card")
	}
	// Converted-to-stars gifts keep the card (with the converted chip).
	g2 := &giftData{Kind: "stargift", Stars: 100, Converted: true}
	if !giftBubbleVisible(g2) {
		t.Fatal("converted gift must render the card")
	}
}
