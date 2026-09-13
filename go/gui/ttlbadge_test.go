package gui

import (
	"encoding/json"
	"testing"

	"uniclient/engine"
)

// TTL badges (slice 182, parity row "Expired/self-destruct media"):
// pure logic — one-time media (media_ttl_seconds) → "One-time …" chip;
// message auto-delete (ttl_seconds) → timer glyph + period text beside
// the timestamp. Layout verified by compile + review.

func ttlMessage(extra map[string]interface{}, mediaType int) *engine.CachedMessage {
	env := struct {
		Extra map[string]interface{} `json:"extra"`
	}{Extra: extra}
	raw, _ := json.Marshal(env)
	return &engine.CachedMessage{
		AccountID:  "a",
		ChatID:     "c",
		MsgID:      "1",
		HasMedia:   mediaType != 0,
		MediaType:  mediaType,
		ContentRaw: raw,
	}
}

func TestParseTTLExtras(t *testing.T) {
	m := ttlMessage(map[string]interface{}{
		"ttl_seconds":       float64(300),
		"media_ttl_seconds": float64(5),
	}, engine.MediaImage)
	msgTTL, mediaTTL := parseTTLExtras(m)
	if msgTTL != 300 || mediaTTL != 5 {
		t.Fatalf("ttl = %d/%d", msgTTL, mediaTTL)
	}
	// Absent → zeros.
	m2 := ttlMessage(map[string]interface{}{}, engine.MediaImage)
	if msg2, media2 := parseTTLExtras(m2); msg2 != 0 || media2 != 0 {
		t.Fatalf("absent ttl = %d/%d", msg2, media2)
	}
	if msg3, media3 := parseTTLExtras(&engine.CachedMessage{}); msg3 != 0 || media3 != 0 {
		t.Fatalf("raw-less ttl = %d/%d", msg3, media3)
	}
}

func TestFmtTTLPeriod(t *testing.T) {
	cases := []struct {
		in   int
		want string
	}{
		{0, ""},
		{30, "30s"},
		{60, "1m"},
		{300, "5m"},
		{3600, "1h"},
		{7200, "2h"},
		{86400, "1d"},
		{172800, "2d"},
		{604800, "1w"},
		{1209600, "2w"},
	}
	for _, c := range cases {
		if got := fmtTTLPeriod(c.in); got != c.want {
			t.Errorf("fmtTTLPeriod(%d) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestOneTimeLabel(t *testing.T) {
	cases := []struct {
		mediaType int
		want      string
	}{
		{engine.MediaImage, "One-time photo"},
		{engine.MediaVideo, "One-time video"},
		{engine.MediaVoice, "One-time voice message"},
		{engine.MediaVideoNote, "One-time video message"},
		{engine.MediaFile, ""},
	}
	for _, c := range cases {
		if got := oneTimeLabel(c.mediaType); got != c.want {
			t.Errorf("oneTimeLabel(%d) = %q, want %q", c.mediaType, got, c.want)
		}
	}
	// The chip shows only when the media carries a TTL.
	if oneTimeChipVisible(0, 5) {
		t.Fatal("media TTL 0 must not show the chip")
	}
	if !oneTimeChipVisible(engine.MediaImage, 5) {
		t.Fatal("photo with media TTL must show the chip")
	}
	if oneTimeChipVisible(engine.MediaImage, 0) {
		t.Fatal("photo without media TTL must not show the chip")
	}
	// File media never shows it (no one-time files).
	if oneTimeChipVisible(engine.MediaFile, 5) {
		t.Fatal("file media must not show the chip")
	}
}
