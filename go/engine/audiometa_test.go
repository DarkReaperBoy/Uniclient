package engine

// AudioMeta (slice 185): the cached message's embedded music tags
// (audio_title / audio_performer from the core's DocumentAttributeAudio
// export) parse out of ContentRaw; absent/degenerate content stays
// honestly empty.

import (
	"encoding/json"
	"testing"
)

func TestAudioMeta(t *testing.T) {
	raw := map[string]any{
		"id":   "m1",
		"text": "",
		"extra": map[string]any{
			"audio_title":     "Tom Sawyer",
			"audio_performer": "Rush",
			"waveform":        "AAAA",
		},
	}
	b, err := json.Marshal(raw)
	if err != nil {
		t.Fatal(err)
	}
	m := &CachedMessage{ContentRaw: b}
	title, performer := m.AudioMeta()
	if title != "Tom Sawyer" || performer != "Rush" {
		t.Fatalf("AudioMeta = %q, %q", title, performer)
	}

	// No extra at all.
	m = &CachedMessage{ContentRaw: []byte(`{"id":"m2","text":"hi"}`)}
	if title, performer = m.AudioMeta(); title != "" || performer != "" {
		t.Fatalf("absent tags = %q, %q", title, performer)
	}

	// Only one of the two.
	m = &CachedMessage{ContentRaw: []byte(`{"extra":{"audio_performer":"X"}}`)}
	if title, performer = m.AudioMeta(); title != "" || performer != "X" {
		t.Fatalf("performer-only = %q, %q", title, performer)
	}

	// Degenerate: nil receiver, empty raw, garbage raw.
	m = nil
	if title, performer = m.AudioMeta(); title != "" || performer != "" {
		t.Fatalf("nil receiver = %q, %q", title, performer)
	}
	m = &CachedMessage{}
	if title, performer = m.AudioMeta(); title != "" || performer != "" {
		t.Fatalf("empty raw = %q, %q", title, performer)
	}
	m = &CachedMessage{ContentRaw: []byte("not json")}
	if title, performer = m.AudioMeta(); title != "" || performer != "" {
		t.Fatalf("garbage raw = %q, %q", title, performer)
	}

	// Non-string values are skipped, not fatal.
	m = &CachedMessage{ContentRaw: []byte(`{"extra":{"audio_title":42,"audio_performer":true}}`)}
	if title, performer = m.AudioMeta(); title != "" || performer != "" {
		t.Fatalf("non-string tags = %q, %q", title, performer)
	}
}
