package engine

// tests-first for slice 229 — the sound half of row 281: a video that
// began from the fetch-on-read stream gets its bytes only when the file
// completes, so its audio must start at the PICTURE's playhead, not at
// zero. What must be pinned: the clamp (a hostile/edge offset never
// plays out of bounds) and PlayMediaAt really planting Position at the
// requested offset on a real decoded fixture.

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// TestMediaStartPosClamp pins the pure clamp.
func TestMediaStartPosClamp(t *testing.T) {
	cases := []struct {
		name    string
		startAt time.Duration
		dur     float64
		want    float64
	}{
		{"zero offset", 0, 10, 0},
		{"negative offset", -time.Second, 10, 0},
		{"mid track", 250 * time.Millisecond, 3, 0.25},
		{"exactly at end", 10 * time.Second, 10, 0}, // past-the-end: loop, like the picture
		{"beyond end", 12 * time.Second, 10, 0},     // ditto
		{"unknown duration", 250 * time.Millisecond, 0, 0},
		{"one tick before end", 9999 * time.Millisecond, 10, 9.999},
	}
	for _, c := range cases {
		if got := mediaStartPos(c.startAt, c.dur); got != c.want {
			t.Errorf("%s: mediaStartPos(%v, %v) = %v, want %v", c.name, c.startAt, c.dur, got, c.want)
		}
	}
}

// TestPlayMediaAtStartsAtOffset drives the real decode+play path with a
// committed MP4 fixture and asserts the reported Position lands at the
// requested offset (±30 ms covers sample rounding).
func TestPlayMediaAtStartsAtOffset(t *testing.T) {
	e := newTestEngine(t)
	p := filepath.Join("..", "aacaud", "testdata", "talk.mp4")
	if _, err := os.Stat(p); err != nil {
		t.Skipf("aacaud testdata missing: %v", err)
	}
	startAt := 250 * time.Millisecond
	if err := e.PlayMediaAt("a1", "c1", "m1", p, startAt); err != nil {
		t.Fatalf("PlayMediaAt: %v", err)
	}
	st := e.MediaState()
	if st.MsgID != "m1" {
		t.Errorf("MsgID = %q, want m1", st.MsgID)
	}
	if st.Duration <= 0 {
		t.Fatalf("Duration = %v, want the decoded track's length", st.Duration)
	}
	// Tolerance both ways: where a device is live (host, PulseAudio),
	// the fill callback pulls buffers between our call and this read and
	// Position keeps advancing; on a headless CI runner it sits exactly
	// at the plant. 0.24..0.35 brackets both for startAt=0.25.
	if st.Position < 0.22 || st.Position > 0.35 {
		t.Errorf("Position = %v, want ~0.25 (the requested startAt)", st.Position)
	}

	// PlayMedia (startAt 0) must still be near zero — the refactor may
	// not move the default entry point (a live device may already have
	// pulled a buffer, hence the upper bound instead of == 0).
	if err := e.PlayMedia("a1", "c1", "m2", p); err != nil {
		t.Fatalf("PlayMedia: %v", err)
	}
	if got := e.MediaState().Position; got >= 0.2 {
		t.Errorf("PlayMedia Position = %v, want ~0 (startAt ignored for the default path)", got)
	}
}
