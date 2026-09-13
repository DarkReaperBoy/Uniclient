package gui

import (
	"testing"

	"uniclient/cores"
	"uniclient/engine"
)

// Channel statistics page (slice 184, GUI half): pure logic — Telegram
// chart JSON parsing ({"columns":[["x",...],["y",...]]}), axis value
// formatting, delta labels, header-menu gating. Layout verified by
// compile + review.

func TestParseChartJSON(t *testing.T) {
	pts := parseChartJSON(`{"columns":[["x",1561910400,1561996800,1562083200],["y",100,150,200]]}`)
	if len(pts) != 3 {
		t.Fatalf("points = %d", len(pts))
	}
	if pts[0].T != 1561910400 || pts[0].V != 100 {
		t.Fatalf("first = %+v", pts[0])
	}
	if pts[2].T != 1562083200 || pts[2].V != 200 {
		t.Fatalf("last = %+v", pts[2])
	}

	// Multi-series charts take the first non-x series.
	pts2 := parseChartJSON(`{"columns":[["x",1,2],["y0",3,4],["y1",5,6]]}`)
	if len(pts2) != 2 || pts2[1].V != 4 {
		t.Fatalf("multi-series = %+v", pts2)
	}

	// Degenerate inputs → nil, never panic.
	if parseChartJSON("") != nil {
		t.Fatal("empty json parsed")
	}
	if parseChartJSON("not json") != nil {
		t.Fatal("garbage parsed")
	}
	if parseChartJSON(`{"columns":[]}`) != nil {
		t.Fatal("no columns parsed")
	}
	if parseChartJSON(`{"columns":[["x",1]]}`) != nil {
		t.Fatal("x-only parsed")
	}
}

func TestChartRange(t *testing.T) {
	min, max := chartRange([]chartPoint{{V: 5}, {V: 1}, {V: 3}})
	if min != 1 || max != 5 {
		t.Fatalf("range = %v..%v", min, max)
	}
	// Flat series widens (avoids divide-by-zero in the plot).
	min2, max2 := chartRange([]chartPoint{{V: 7}, {V: 7}})
	if min2 >= max2 {
		t.Fatalf("flat range = %v..%v", min2, max2)
	}
}

func TestFmtChartValue(t *testing.T) {
	cases := []struct {
		in   float64
		want string
	}{
		{0, "0"},
		{42, "42"},
		{1234, "1.2K"},
		{1500000, "1.5M"},
		{2.5, "2.5"},
	}
	for _, c := range cases {
		if got := fmtChartValue(c.in); got != c.want {
			t.Errorf("fmtChartValue(%v) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestStatsDeltaLabel(t *testing.T) {
	if got := statsDeltaLabel(4100, 3900); got != "+200" {
		t.Fatalf("up = %q", got)
	}
	if got := statsDeltaLabel(3800, 3900); got != "−100" {
		t.Fatalf("down = %q", got)
	}
	if got := statsDeltaLabel(50, 50); got != "±0" {
		t.Fatalf("flat = %q", got)
	}
	if got := statsDeltaLabel(10.5, 10); got != "+0.5" {
		t.Fatalf("frac = %q", got)
	}
}

func TestHeaderMenuStatsEntry(t *testing.T) {
	// Admin channels get Statistics.
	c := engine.ChatInfo{Type: engine.ChatTypeChanVal, IsAdmin: true}
	found := false
	for _, it := range headerMenuItems(c, false, false, false) {
		if it.id == "stats" {
			found = true
		}
	}
	if !found {
		t.Fatal("admin channel menu lacks Statistics")
	}
	// Non-admin channels never see it.
	c2 := engine.ChatInfo{Type: engine.ChatTypeChanVal, IsAdmin: false}
	for _, it := range headerMenuItems(c2, false, false, false) {
		if it.id == "stats" {
			t.Fatal("non-admin sees Statistics")
		}
	}
	// Groups never see it (megagroup stats is a different RPC; out of
	// this slice's scope — the row is the channel page).
	c3 := engine.ChatInfo{Type: engine.ChatTypeGroupVal, IsAdmin: true}
	for _, it := range headerMenuItems(c3, false, false, false) {
		if it.id == "stats" {
			t.Fatal("group menu shows channel Statistics")
		}
	}
	_ = cores.ChannelStats{}
}
