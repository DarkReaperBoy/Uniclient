package tests

import (
	"os"
	"path/filepath"
	"testing"
	"time"
	. "uniclient/engine"
)

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
		{"exactly at end", 10 * time.Second, 10, 0},
		{"beyond end", 12 * time.Second, 10, 0},
		{"unknown duration", 250 * time.Millisecond, 0, 0},
		{"one tick before end", 9999 * time.Millisecond, 10, 9.999},
	}
	for _, c := range cases {
		if got := MediaStartPos(c.startAt, c.dur); got != c.want {
			t.Errorf("%s: mediaStartPos(%v, %v) = %v, want %v", c.name, c.startAt, c.dur, got, c.want)
		}
	}
}

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
	if st.Position < 0.22 || st.Position > 0.35 {
		t.Errorf("Position = %v, want ~0.25 (the requested startAt)", st.Position)
	}

	if err := e.PlayMedia("a1", "c1", "m2", p); err != nil {
		t.Fatalf("PlayMedia: %v", err)
	}
	if got := e.MediaState().Position; got >= 0.2 {
		t.Errorf("PlayMedia Position = %v, want ~0 (startAt ignored for the default path)", got)
	}
}
