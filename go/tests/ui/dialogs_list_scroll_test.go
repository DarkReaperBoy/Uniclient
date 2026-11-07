package tests

import (
	"testing"

	"uniclient/ui/dialogs"
	. "uniclient/ui/tokens"
)

func scrollFixture() dialogs.List {
	return dialogs.List{Rows: []dialogs.Entry{
		{Name: "plain"},
		{Name: "tagged", Tagged: true},
		{Name: "forum", Forum: true},
		{Name: "taggedforum", Tagged: true, Forum: true},
	}}
}

func TestPreloadScreensToken(t *testing.T) {
	if PreloadScreens != 3 {
		t.Fatalf("preload screens drifted: %d (want 3 — config.h PreloadHeightsCount)",
			PreloadScreens)
	}
}

func TestListMaxOffset(t *testing.T) {
	l := scrollFixture()
	const wide = 400
	if got := l.MaxOffset(wide, 100); got != 210 {
		t.Fatalf("max offset = %d, want 210 (310 content - 100 view)", got)
	}
	if got := l.MaxOffset(wide, 310); got != 0 {
		t.Fatalf("max offset at exact fit = %d, want 0", got)
	}
	if got := l.MaxOffset(wide, 500); got != 0 {
		t.Fatalf("max offset with view taller than content = %d, want 0 (clamped)", got)
	}
	empty := dialogs.List{}
	if got := empty.MaxOffset(wide, 100); got != 0 {
		t.Fatalf("max offset of empty list = %d, want 0", got)
	}
	narrow := dialogs.List{Rows: []dialogs.Entry{
		{Name: "a", Tagged: true}, {Name: "b", Forum: true},
		{Name: "c", Tagged: true, Forum: true}, {Name: "d"},
	}}
	if got := narrow.MaxOffset(100, 100); got != 148 {
		t.Fatalf("narrow max offset = %d, want 148 (4*62 - 100)", got)
	}
}

func TestListClampOffset(t *testing.T) {
	l := scrollFixture()
	const wide = 400
	if got := l.ClampOffset(-5, wide, 100); got != 0 {
		t.Fatalf("clamp(-5) = %d, want 0", got)
	}
	if got := l.ClampOffset(999, wide, 100); got != 210 {
		t.Fatalf("clamp(999) = %d, want 210", got)
	}
	if got := l.ClampOffset(100, wide, 100); got != 100 {
		t.Fatalf("clamp(100) = %d, want 100 (in range passes through)", got)
	}
	if got := l.ClampOffset(0, wide, 500); got != 0 {
		t.Fatalf("clamp(0) with oversized view = %d, want 0", got)
	}
}

func TestVisibleRowsWalk(t *testing.T) {
	l := scrollFixture()
	const wide = 400
	cases := []struct {
		top, viewH, first, last int
	}{
		{0, 100, 0, 2},
		{62, 100, 1, 3},
		{61, 100, 0, 3},
		{214, 100, 3, 4},
		{155, 100, 2, 4},
		{133, 100, 1, 4},
		{134, 100, 2, 4},
		{309, 100, 3, 4},
	}
	for _, c := range cases {
		first, last := l.VisibleRows(dialogs.Viewport{Top: c.top, Height: c.viewH}, wide)
		if first != c.first || last != c.last {
			t.Fatalf("VisibleRows{top %d, viewH %d} = (%d, %d), want (%d, %d)",
				c.top, c.viewH, first, last, c.first, c.last)
		}
	}
}

func TestVisibleRowsEmptyAndNarrow(t *testing.T) {
	empty := dialogs.List{}
	if first, last := empty.VisibleRows(dialogs.Viewport{Top: 0, Height: 100}, 400); first != 0 || last != 0 {
		t.Fatalf("empty list VisibleRows = (%d, %d), want (0, 0)", first, last)
	}
	narrow := scrollFixture()
	if first, last := narrow.VisibleRows(dialogs.Viewport{Top: 100, Height: 100}, 100); first != 1 || last != 4 {
		t.Fatalf("narrow VisibleRows{top 100} = (%d, %d), want (1, 4) — all rows 62 tall below 100",
			first, last)
	}
	if first, last := narrow.VisibleRows(dialogs.Viewport{Top: 0, Height: 62}, 100); first != 0 || last != 1 {
		t.Fatalf("narrow VisibleRows{top 0, viewH 62} = (%d, %d), want (0, 1)", first, last)
	}
}

func TestPreloadWindow(t *testing.T) {
	l := scrollFixture()
	from, to := l.PreloadWindow(dialogs.Viewport{Top: 210, Height: 100})
	if from != 210 || to != 610 {
		t.Fatalf("preload window = (%d, %d), want (210, 610) — top + 4 viewports", from, to)
	}
	from, to = l.PreloadWindow(dialogs.Viewport{Top: 0, Height: 0})
	if from != 0 || to != 0 {
		t.Fatalf("zero-height preload window = (%d, %d), want (0, 0)", from, to)
	}
}

func TestLoadMoreNeeded(t *testing.T) {
	l := scrollFixture()
	const wide = 400
	if l.LoadMoreNeeded(dialogs.Viewport{Top: 0, Height: 100}, wide) {
		t.Fatal("load-more fired at top 0 (0 + 3*100 = 300 < 310 content)")
	}
	if !l.LoadMoreNeeded(dialogs.Viewport{Top: 10, Height: 100}, wide) {
		t.Fatal("load-more did not fire at exact boundary (10 + 300 = 310 >= 310)")
	}
	if !l.LoadMoreNeeded(dialogs.Viewport{Top: 50, Height: 100}, wide) {
		t.Fatal("load-more did not fire past boundary (350 >= 310)")
	}
	empty := dialogs.List{}
	if !empty.LoadMoreNeeded(dialogs.Viewport{Top: 0, Height: 100}, wide) {
		t.Fatal("empty list must request load-more immediately (0 >= 0)")
	}
}

func TestScrollToRevealVisible(t *testing.T) {
	if got := dialogs.ScrollToReveal(60, 120, 50, 100, 210); got != 50 {
		t.Fatalf("reveal of fully visible item = %d, want 50 (no scroll)", got)
	}
	if got := dialogs.ScrollToReveal(10, 70, 50, 100, 210); got != 10 {
		t.Fatalf("reveal of item above view = %d, want 10 (top-align)", got)
	}
	if got := dialogs.ScrollToReveal(50, 150, 50, 100, 210); got != 50 {
		t.Fatalf("reveal of exactly-fitting item = %d, want 50", got)
	}
}

func TestScrollToRevealBelow(t *testing.T) {
	if got := dialogs.ScrollToReveal(160, 220, 50, 100, 210); got != 120 {
		t.Fatalf("reveal of item below view = %d, want 120 (bottom-align 220-100)", got)
	}
	if got := dialogs.ScrollToReveal(180, 320, 50, 100, 210); got != 180 {
		t.Fatalf("reveal of taller-than-view item = %d, want 180 (cap at item top)", got)
	}
	if got := dialogs.ScrollToReveal(160, 250, 100, 100, 210); got != 150 {
		t.Fatalf("reveal of partially below item = %d, want 150 (bottom-align 250-100)", got)
	}
}

func TestScrollToRevealExactAndClamp(t *testing.T) {
	if got := dialogs.ScrollToReveal(160, -1, 50, 100, 210); got != 160 {
		t.Fatalf("exact reveal = %d, want 160 (top-align, bottom ignored)", got)
	}
	if got := dialogs.ScrollToReveal(-20, 40, 50, 100, 210); got != 0 {
		t.Fatalf("reveal clamp below 0 = %d, want 0", got)
	}
	if got := dialogs.ScrollToReveal(999, 1050, 50, 100, 210); got != 210 {
		t.Fatalf("reveal clamp above max = %d, want 210", got)
	}
	if got := dialogs.ScrollToReveal(5, 40, 0, 100, 0); got != 0 {
		t.Fatalf("reveal with zero scroll range = %d, want 0", got)
	}
}

func TestScrollbarThumbGeometry(t *testing.T) {
	l := scrollFixture()
	const wide = 400
	th := l.ScrollbarThumb(dialogs.Viewport{Top: 0, Height: 100}, wide, 200)
	if th.Hidden {
		t.Fatal("thumb hidden at scroll top with 310 content in 100 view")
	}
	if th.Y != 3 || th.H != 62 {
		t.Fatalf("thumb at top = (%d, %d), want (3, 62) — 194*100/310 floor, deltat inset",
			th.Y, th.H)
	}
	th = l.ScrollbarThumb(dialogs.Viewport{Top: 210, Height: 100}, wide, 200)
	if th.Hidden {
		t.Fatal("thumb hidden at scroll bottom")
	}
	if th.Y != 135 || th.H != 62 {
		t.Fatalf("thumb at bottom = (%d, %d), want (135, 62) — 3 + 132, bottom-aligned",
			th.Y, th.H)
	}
	th = l.ScrollbarThumb(dialogs.Viewport{Top: 105, Height: 100}, wide, 200)
	if th.Y != 69 || th.H != 62 {
		t.Fatalf("thumb at mid = (%d, %d), want (69, 62)", th.Y, th.H)
	}
	long := dialogs.List{Rows: make([]dialogs.Entry, 20)}
	th = long.ScrollbarThumb(dialogs.Viewport{Top: 0, Height: 100}, wide, 200)
	if th.Hidden || th.H != 40 {
		t.Fatalf("min thumb law = (%d hidden %v), want height 40 (scrollBarMin)", th.H, th.Hidden)
	}
}

func TestScrollbarThumbMinAndHidden(t *testing.T) {
	l := scrollFixture()
	const wide = 400
	short := dialogs.List{Rows: []dialogs.Entry{{Name: "a"}, {Name: "b"}}}
	th := short.ScrollbarThumb(dialogs.Viewport{Top: 0, Height: 62}, wide, 60)
	if th.Hidden {
		t.Fatal("thumb hidden on 60 track with 124 content in 62 view")
	}
	if th.Y != 3 || th.H != 27 {
		t.Fatalf("half-track min law = (%d, %d), want (3, 27) — barWanted 54*62/124, barMin min(40, 54/2)",
			th.Y, th.H)
	}
	th = short.ScrollbarThumb(dialogs.Viewport{Top: 62, Height: 62}, wide, 60)
	if th.Hidden || th.Y != 30 || th.H != 27 {
		t.Fatalf("half-track min law at bottom = (%d, %d hidden %v), want (30, 27)",
			th.Y, th.H, th.Hidden)
	}
	if th := l.ScrollbarThumb(dialogs.Viewport{Top: 0, Height: 310}, wide, 200); !th.Hidden {
		t.Fatal("thumb must hide when view covers content")
	}
	if th := l.ScrollbarThumb(dialogs.Viewport{Top: 0, Height: 100}, wide, 13); !th.Hidden {
		t.Fatal("thumb must hide on 13 track (min size 14)")
	}
	empty := dialogs.List{}
	if th := empty.ScrollbarThumb(dialogs.Viewport{Top: 0, Height: 100}, wide, 200); !th.Hidden {
		t.Fatal("thumb must hide on empty list")
	}
	th = l.ScrollbarThumb(dialogs.Viewport{Top: -50, Height: 100}, wide, 200)
	if th.Hidden || th.Y != 3 {
		t.Fatalf("overscroll thumb = (%d hidden %v), want Y 3 (cut clamped at 0)", th.Y, th.Hidden)
	}
}
