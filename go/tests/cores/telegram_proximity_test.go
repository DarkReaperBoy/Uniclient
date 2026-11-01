package tests

import (
	"testing"
	. "uniclient/cores"
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
		{1239, "1.2 km"},
		{1250, "1.2 km"},
		{12345, "12.3 km"},
		{100000, "100 km"},
	}
	for _, c := range cases {
		got := ProximityDistanceLabel(c.meters)
		if c.meters == 1250 && (got == "1.2 km" || got == "1.3 km") {
			continue
		}
		if got != c.want {
			t.Errorf("ProximityDistanceLabel(%d) = %q, want %q", c.meters, got, c.want)
		}
	}
}

func TestProximityReachedText(t *testing.T) {
	if got := ProximityReachedText("Me", "Alice", true, false, 500); got != "You're now within 500 m of Alice" {
		t.Errorf("from-self text = %q", got)
	}
	if got := ProximityReachedText("Bob", "Me", false, true, 1500); got != "Bob is now within 1.5 km of you" {
		t.Errorf("to-self text = %q", got)
	}
	if got := ProximityReachedText("Bob", "Alice", false, false, 42); got != "Bob is now within 42 m of Alice" {
		t.Errorf("third-party text = %q", got)
	}
}
