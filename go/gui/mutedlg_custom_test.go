package gui

import "testing"

func TestParseCustomMuteDuration(t *testing.T) {
	cases := []struct {
		in   string
		want int
		ok   bool
	}{
		{"1h", 3600, true},
		{"8h", 8 * 3600, true},
		{"2d", 2 * 86400, true},
		{"90m", 90 * 60, true},
		{"45s", 45, true},
		{"1h30m", 3600 + 30*60, true},
		{"2d 3h 5m", 2*86400 + 3*3600 + 5*60, true},
		{"1H30M", 3600 + 30*60, true},
		{" 2h ", 2 * 3600, true},
		{"3600", 3600, true},
		{"60", 60, true},
		{"0", 0, false},
		{"", 0, false},
		{"abc", 0, false},
		{"h", 0, false},
		{"-5m", 0, false},
		{"1.5h", 0, false},
	}
	for _, c := range cases {
		got, ok := parseCustomMuteDuration(c.in)
		if ok != c.ok || (ok && got != c.want) {
			t.Fatalf("parse(%q) = %d,%v want %d,%v", c.in, got, ok, c.want, c.ok)
		}
	}
}

func TestCustomMuteCap(t *testing.T) {
	if got, ok := parseCustomMuteDuration("5000d"); !ok || got != 0 {
		t.Fatalf("5000d should cap to forever (0), got %d ok=%v", got, ok)
	}
	if got, ok := parseCustomMuteDuration("1000d"); !ok || got != 1000*86400 {
		t.Fatalf("1000d should stay a real duration, got %d ok=%v", got, ok)
	}
}
