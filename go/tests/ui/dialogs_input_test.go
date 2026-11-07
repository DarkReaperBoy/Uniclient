package tests

import (
	"testing"

	"uniclient/ui/dialogs"
	. "uniclient/ui/tokens"
)

func inputList(rows int) dialogs.List {
	entries := make([]dialogs.Entry, rows)
	for i := range entries {
		entries[i] = dialogs.Entry{Name: "row"}
	}
	return dialogs.List{Rows: entries}
}

func TestWheelDeltaNotch(t *testing.T) {
	if dy := dialogs.WheelDelta(0, -120, WheelScrollLines, 400, 300, false); dy != 60 {
		t.Fatalf("notch down = %d, want 60 (120*3/6)", dy)
	}
	if dy := dialogs.WheelDelta(0, 120, WheelScrollLines, 400, 300, false); dy != -60 {
		t.Fatalf("notch up = %d, want -60", dy)
	}
	if dy := dialogs.WheelDelta(0, -45, WheelScrollLines, 400, 300, false); dy != 23 {
		t.Fatalf("odd angle -45 = %d, want 23 (qRound(-22.5) = -23, sign-flipped)", dy)
	}
	if dy := dialogs.WheelDelta(0, -120, 1, 400, 300, false); dy != 20 {
		t.Fatalf("lines=1 notch = %d, want 20 (120*1/6)", dy)
	}
}

func TestWheelDeltaAccelerate(t *testing.T) {
	if dy := dialogs.WheelDelta(0, -120, WheelScrollLines, 400, 300, true); dy != 150 {
		t.Fatalf("accel notch = %d, want 150 (-60 * max(300,120)/120 = -150, flipped)", dy)
	}
	if dy := dialogs.WheelDelta(0, -45, WheelScrollLines, 400, 300, true); dy != 57 {
		t.Fatalf("accel odd = %d, want 57 (trunc(-23 * 2.5) = -57, flipped)", dy)
	}
	if dy := dialogs.WheelDelta(0, -120, WheelScrollLines, 400, 100, true); dy != 60 {
		t.Fatalf("accel small area = %d, want 60 (max(100,120)/120 = 1)", dy)
	}
}

func TestWheelDeltaCrossAxis(t *testing.T) {
	if dy := dialogs.WheelDelta(-120, -120, WheelScrollLines, 400, 300, false); dy != 0 {
		t.Fatalf("equal axes = %d, want 0 (|x| >= |y| ignores)", dy)
	}
	if dy := dialogs.WheelDelta(-130, -120, WheelScrollLines, 400, 300, false); dy != 0 {
		t.Fatalf("horizontal dominant = %d, want 0", dy)
	}
	if dy := dialogs.WheelDelta(-90, -100, WheelScrollLines, 400, 300, false); dy != 50 {
		t.Fatalf("vertical dominant = %d, want 50", dy)
	}
	if dy := dialogs.WheelDelta(-90, -100, WheelScrollLines, 400, 300, true); dy != 0 {
		t.Fatalf("accel flips verdict = %d, want 0 (trunc(-45*400/120)=-150 vs trunc(-50*2.5)=-125)", dy)
	}
}

func TestScrollPixels(t *testing.T) {
	if dy := dialogs.ScrollPixels(0, -40, 400, 300, false); dy != 40 {
		t.Fatalf("pixel down = %d, want 40", dy)
	}
	if dy := dialogs.ScrollPixels(0, 25, 400, 300, false); dy != -25 {
		t.Fatalf("pixel up = %d, want -25", dy)
	}
	if dy := dialogs.ScrollPixels(0, -40, 400, 300, true); dy != 100 {
		t.Fatalf("pixel accel = %d, want 100 (trunc(-40*2.5) = -100, flipped)", dy)
	}
	if dy := dialogs.ScrollPixels(0, -1, 400, 300, true); dy != 2 {
		t.Fatalf("pixel accel odd = %d, want 2 (trunc(-2.5) = -2, flipped)", dy)
	}
	if dy := dialogs.ScrollPixels(-50, -40, 400, 300, false); dy != 0 {
		t.Fatalf("cross-axis = %d, want 0", dy)
	}
}

func TestBarOver(t *testing.T) {
	thumb := dialogs.Thumb{Y: 122, H: 88}
	if !dialogs.BarOver(thumb, 3, 122) {
		t.Fatal("left edge of thumb x must hit")
	}
	if !dialogs.BarOver(thumb, 6, 122) {
		t.Fatal("right-inside of thumb x must hit")
	}
	if dialogs.BarOver(thumb, 7, 150) {
		t.Fatal("x past thickness must miss")
	}
	if dialogs.BarOver(thumb, 2, 150) {
		t.Fatal("x before deltax must miss")
	}
	if dialogs.BarOver(thumb, 5, 121) {
		t.Fatal("above thumb must miss")
	}
	if !dialogs.BarOver(thumb, 5, 122) {
		t.Fatal("thumb top must hit")
	}
	if !dialogs.BarOver(thumb, 5, 209) {
		t.Fatal("last thumb row must hit")
	}
	if dialogs.BarOver(thumb, 5, 210) {
		t.Fatal("below thumb must miss")
	}
	if dialogs.BarOver(dialogs.Thumb{Hidden: true}, 5, 150) {
		t.Fatal("hidden thumb never hits")
	}
}

func TestBarTrackJump(t *testing.T) {
	l := inputList(16)
	v := dialogs.Viewport{Top: 400, Height: 300}
	if top := l.BarTrackJump(v, 400, 300, 150); top != 346 {
		t.Fatalf("jump y=150 = %d, want 346 (692*103/206)", top)
	}
	if top := l.BarTrackJump(v, 400, 300, 0); top != 0 {
		t.Fatalf("jump y=0 = %d, want 0 (clamped to first half)", top)
	}
	if top := l.BarTrackJump(v, 400, 300, 299); top != 692 {
		t.Fatalf("jump y=299 = %d, want 692 (scrollable end)", top)
	}
	if top := l.BarTrackJump(v, 400, 300, 100); top != 178 {
		t.Fatalf("jump y=100 = %d, want 178 (692*53/206 = 178.04 truncated)", top)
	}
	empty := dialogs.List{}
	if top := empty.BarTrackJump(dialogs.Viewport{Top: 5, Height: 300}, 400, 300, 150); top != 5 {
		t.Fatalf("hidden thumb jump = %d, want 5 (echo of current)", top)
	}
}

func TestBarDragScale(t *testing.T) {
	l := inputList(16)
	v := dialogs.Viewport{Top: 400, Height: 300}
	if dy := l.BarDragScale(v, 400, 300, 10); dy != 33 {
		t.Fatalf("scale dy=10 = %d, want 33 (10*692/206)", dy)
	}
	if dy := l.BarDragScale(v, 400, 300, -20); dy != -67 {
		t.Fatalf("scale dy=-20 = %d, want -67", dy)
	}
	short := inputList(5)
	if dy := short.BarDragScale(dialogs.Viewport{Top: 0, Height: 300}, 400, 300, 7); dy != 7 {
		t.Fatalf("short list dy=7 = %d, want 7 (scrollable 10 <= outsideBar 10, 1:1)", dy)
	}
	if dy := short.BarDragScale(dialogs.Viewport{Top: 0, Height: 300}, 400, 300, -3); dy != -3 {
		t.Fatalf("short list dy=-3 = %d, want -3", dy)
	}
}
