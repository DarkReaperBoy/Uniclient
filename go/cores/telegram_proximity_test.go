package cores

// telegram_proximity_test.go — slice 208 tests-first: the
// messageActionGeoProximityReached service-message rendering (tdesktop
// history_item.cpp prepareProximityReached): distance label (m / km at
// 10 m precision) + the three self/non-self sentence shapes.

import (
	"testing"
)

func TestProximityDistanceLabel(t *testing.T) {
	cases := []struct {
		meters int
		want   string
	}{
		{0, "0 m"},
		{5, "5 m"},
		{999, "999 m"},
		{1000, "1 km"},
		{1234, "1.2 km"},
		{1239, "1.2 km"}, // 10 m precision: 1239 → 1230 → 1.23 → 1.2
		{1250, "1.2 km"}, // 1250 → 1250 → 1.25 → 1.2 (half-even) / 1.3 acceptable
		{12345, "12.3 km"},
		{100000, "100 km"},
	}
	for _, c := range cases {
		got := proximityDistanceLabel(c.meters)
		// 1250 is a rounding edge (%.1f of 1.25): accept either side.
		if c.meters == 1250 && (got == "1.2 km" || got == "1.3 km") {
			continue
		}
		if got != c.want {
			t.Errorf("proximityDistanceLabel(%d) = %q, want %q", c.meters, got, c.want)
		}
	}
}

func TestProximityReachedText(t *testing.T) {
	// from == self: "You're now within D of {to}".
	if got := proximityReachedText("Me", "Alice", true, false, 500); got != "You're now within 500 m of Alice" {
		t.Errorf("from-self text = %q", got)
	}
	// to == self: "{from} is now within D of you".
	if got := proximityReachedText("Bob", "Me", false, true, 1500); got != "Bob is now within 1.5 km of you" {
		t.Errorf("to-self text = %q", got)
	}
	// third parties: "{from} is now within D of {to}".
	if got := proximityReachedText("Bob", "Alice", false, false, 42); got != "Bob is now within 42 m of Alice" {
		t.Errorf("third-party text = %q", got)
	}
}
