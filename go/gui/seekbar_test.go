package gui

// Seek bar + music row subtitle (slice 185): pure logic — the pointer
// fraction mapping (clamping, degenerate widths) and the audio bubble's
// performer/duration/size subtitle composition.

import (
	"strings"
	"testing"
)

func TestSeekFraction(t *testing.T) {
	cases := []struct {
		name       string
		px         float32
		width      int
		cur        float64
		want       float64
		wantCurPas bool
	}{
		{"mid", 50, 200, 0.0, 0.25, false},
		{"full", 200, 200, 0.0, 1.0, false},
		{"zero", 0, 200, 0.8, 0.0, false},
		{"over-clamps", 300, 200, 0.0, 1.0, false},
		{"negative-clamps", -20, 200, 0.5, 0.0, false},
		{"degenerate-width-passes-cur", 50, 0, 0.42, 0.42, true},
		{"degenerate-negative-width", 50, -1, 0.42, 0.42, true},
	}
	for _, c := range cases {
		got := seekFraction(c.px, c.width, c.cur)
		if c.wantCurPas && got != c.cur {
			t.Errorf("%s: degenerate width must pass current through, got %v", c.name, got)
		}
		if !c.wantCurPas && got != c.want {
			t.Errorf("%s: seekFraction(%v, %d, %v) = %v, want %v", c.name, c.px, c.width, c.cur, got, c.want)
		}
	}
}

func TestAudioSubLine(t *testing.T) {
	// Static (not playing): duration + size.
	s := audioSubLine("", 192, false, 0, 0, 4100000)
	if !strings.Contains(s, "3:12") {
		t.Errorf("static line missing duration: %q", s)
	}
	if !strings.Contains(s, "MB") {
		t.Errorf("static line missing size: %q", s)
	}
	if strings.Contains(s, "·  ·") {
		t.Errorf("double separator: %q", s)
	}

	// Playing: live elapsed/total replaces the static duration.
	s = audioSubLine("Rush", 192, true, 30, 192, 4100000)
	if !strings.HasPrefix(s, "Rush · ") {
		t.Errorf("performer must lead: %q", s)
	}
	if !strings.Contains(s, "0:30") || !strings.Contains(s, "3:12") {
		t.Errorf("live elapsed/total missing: %q", s)
	}

	// No size, no performer: just the duration.
	s = audioSubLine("", 65, false, 0, 0, 0)
	if s != "1:05" && s != "1:05 " {
		t.Errorf("bare line = %q", s)
	}

	// Zero duration honest empty.
	if got := audioSubLine("", 0, false, 0, 0, 0); got != "" && got != "0:00" {
		t.Errorf("zero-duration line = %q", got)
	}
}
