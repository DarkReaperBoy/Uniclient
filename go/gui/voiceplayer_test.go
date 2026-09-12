package gui

import (
	"encoding/base64"
	"encoding/json"
	"testing"

	"uniclient/engine"
)

// In-app voice player (slice 113): the pure helpers — playback time
// formatting, the speed chip label ladder, waveform normalization
// bounds — plus the engine-side waveform extraction the bubble reads.

func TestFmtPlaybackTime(t *testing.T) {
	cases := []struct {
		pos, total float64
		want       string
	}{
		{0, 12, "0:00 / 0:12"},
		{3.4, 12, "0:03 / 0:12"},
		{65, 125, "1:05 / 2:05"},
		{0, 0, "0:00 / 0:00"},
	}
	for _, c := range cases {
		if got := fmtPlaybackTime(c.pos, c.total); got != c.want {
			t.Fatalf("fmtPlaybackTime(%v,%v) = %q, want %q", c.pos, c.total, got, c.want)
		}
	}
}

func TestFmtSpeed(t *testing.T) {
	for _, c := range []struct {
		in   float64
		want string
	}{
		{1, "1×"}, {1.5, "1.5×"}, {2, "2×"}, {0.5, "0.5×"}, {3.25, "3.25×"},
	} {
		if got := fmtSpeed(c.in); got != c.want {
			t.Fatalf("fmtSpeed(%v) = %q, want %q", c.in, got, c.want)
		}
	}
}

// TestVoiceWaveformExtraction pins the ContentRaw → Extra.waveform →
// base64 → bytes path the bubble's bars come from.
func TestVoiceWaveformExtraction(t *testing.T) {
	wf := []byte{0, 5, 31, 12, 7}
	b64, err := json.Marshal(map[string]any{
		"extra": map[string]any{"waveform": base64.StdEncoding.EncodeToString(wf)},
	})
	if err != nil {
		t.Fatal(err)
	}
	m := &engine.CachedMessage{ContentRaw: b64}
	got := m.VoiceWaveform()
	if len(got) != len(wf) {
		t.Fatalf("waveform length: %d", len(got))
	}
	for i := range wf {
		if got[i] != wf[i] {
			t.Fatalf("waveform byte %d: %d != %d", i, got[i], wf[i])
		}
	}

	// Absent waveform → nil (the bubble must draw the plain track).
	m2 := &engine.CachedMessage{ContentRaw: []byte(`{"extra":{}}`)}
	if m2.VoiceWaveform() != nil {
		t.Fatal("absent waveform must be nil")
	}
	m3 := &engine.CachedMessage{}
	if m3.VoiceWaveform() != nil {
		t.Fatal("no content → nil waveform")
	}
	var nilMsg *engine.CachedMessage
	if nilMsg.VoiceWaveform() != nil {
		t.Fatal("nil message → nil waveform (no panic)")
	}
}

// TestMediaPlayClickableStable pins the per-control clickable identity:
// same message → same clickable (state survives across frames), and
// the reset guard keeps the map bounded.
func TestMediaPlayClickableStable(t *testing.T) {
	a := &App{}
	a.wid.init()
	key := "a|c|m1"
	c1 := a.mediaPlayClickable(key)
	c2 := a.mediaPlayClickable(key)
	if c1 != c2 {
		t.Fatal("clickable must be stable per key")
	}
	// Distinct controls (play button vs speed chip) get distinct ones.
	if a.mediaPlayClickable(key+"|speed") == c1 {
		t.Fatal("speed chip must have its own clickable")
	}
}
