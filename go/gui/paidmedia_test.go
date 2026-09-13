package gui

import (
	"encoding/json"
	"testing"

	"uniclient/engine"
)

// Paid-media star wall (slice 181, GUI half): pure logic — parsePaidMedia
// over the cached Extra, wall gating (locked → wall, unlocked → normal
// media bubble), star text. Layout verified by compile + review.

func paidMessage(extra map[string]interface{}) *engine.CachedMessage {
	env := struct {
		Extra map[string]interface{} `json:"extra"`
	}{Extra: extra}
	raw, _ := json.Marshal(env)
	return &engine.CachedMessage{
		AccountID:  "a",
		ChatID:     "c",
		MsgID:      "1",
		HasMedia:   true,
		MediaType:  engine.MediaInvoice,
		ContentRaw: raw,
	}
}

func TestParsePaidMedia(t *testing.T) {
	m := paidMessage(map[string]interface{}{
		"invoice_is_paid_media": true,
		"invoice_first_video":   true,
		"paid_stars":            float64(25),
		"paid_thumb_b64":        "aGk=",
		"paid_w":                float64(640),
		"paid_h":                float64(480),
		"paid_video_duration":   float64(15),
	})
	p := parsePaidMedia(m)
	if p == nil {
		t.Fatal("paid media not parsed")
	}
	if p.Stars != 25 || p.ThumbB64 != "aGk=" || p.W != 640 || p.H != 480 || p.VideoDur != 15 {
		t.Fatalf("paid = %+v", p)
	}
	if !p.FirstVideo {
		t.Fatal("first video flag lost")
	}
	if p.Unlocked {
		t.Fatal("locked media parsed as unlocked")
	}

	// Unlocked: the wall never renders; the real media bubble does.
	m2 := paidMessage(map[string]interface{}{
		"invoice_is_paid_media": true,
		"paid_stars":            float64(25),
		"paid_unlocked":         true,
	})
	p2 := parsePaidMedia(m2)
	if p2 == nil || !p2.Unlocked {
		t.Fatalf("unlocked parse = %+v", p2)
	}
	if paidWallVisible(p2) {
		t.Fatal("unlocked paid media must not render the wall")
	}
	if !paidWallVisible(p) {
		t.Fatal("locked paid media must render the wall")
	}

	// Plain invoice (a bot invoice, not paid media) → no wall.
	m3 := paidMessage(map[string]interface{}{})
	if parsePaidMedia(m3) != nil {
		t.Fatal("non-paid-media message parsed as paid")
	}
	if parsePaidMedia(&engine.CachedMessage{}) != nil {
		t.Fatal("raw-less message parsed as paid")
	}
}

func TestPaidStarsText(t *testing.T) {
	if got := paidStarsText(25); got != "25 Stars" {
		t.Fatalf("25 = %q", got)
	}
	if got := paidStarsText(1); got != "1 Star" {
		t.Fatalf("1 = %q", got)
	}
	if got := paidStarsText(0); got != "" {
		t.Fatalf("0 = %q", got)
	}
}
