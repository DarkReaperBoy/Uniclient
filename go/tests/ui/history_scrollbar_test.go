package tests

import (
	"testing"

	"uniclient/ui/history"
	"uniclient/ui/tokens"
)

func scrollbarList(heights ...int) history.List {
	items := make([]history.Item, len(heights))
	for i := range items {
		items[i] = history.Item{Kind: history.ItemMessage, Text: "m"}
	}
	return history.List{Items: items, Heights: heights}
}

func TestHistoryScrollBarTokens(t *testing.T) {
	if tokens.HistoryScrollBarWidth != 12 {
		t.Fatalf("historyScroll width = %d, want 12 (chat.style:196)", tokens.HistoryScrollBarWidth)
	}
	if tokens.HistoryScrollBarRadius != 3 {
		t.Fatalf("historyScroll round = %d, want 3 (chat.style:194)", tokens.HistoryScrollBarRadius)
	}
	if tokens.HistoryScrollBarDeltax != 3 || tokens.HistoryScrollBarDeltat != 3 || tokens.HistoryScrollBarDeltab != 3 {
		t.Fatalf("historyScroll deltas = %d/%d/%d, want 3/3/3 (inherited from defaultScrollArea)",
			tokens.HistoryScrollBarDeltax, tokens.HistoryScrollBarDeltat, tokens.HistoryScrollBarDeltab)
	}
	thickness := tokens.HistoryScrollBarWidth - 2*tokens.HistoryScrollBarDeltax
	fullSkip := tokens.HistoryScrollBarDeltat + tokens.HistoryScrollBarDeltab
	if thickness != 6 {
		t.Fatalf("thumb thickness = %d, want 6 (12 - 2*3)", thickness)
	}
	if 2*tokens.HistoryScrollBarRadius != thickness {
		t.Fatalf("round %d must fill the %d-thick strip exactly (round ends)",
			tokens.HistoryScrollBarRadius, thickness)
	}
	if fullSkip != 6 {
		t.Fatalf("fullSkip = %d, want 6", fullSkip)
	}
	if fullSkip+2*thickness != 18 {
		t.Fatalf("min track size = %d, want 18 (refreshGeometry minSize)", fullSkip+2*thickness)
	}
	if tokens.ScrollBarThumbMin != 40 {
		t.Fatalf("scrollBarMin = %d, want 40 (widgets.style:828)", tokens.ScrollBarThumbMin)
	}
	if tokens.ScrollHidingMs != 1000 || tokens.ScrollDurationMs != 150 {
		t.Fatalf("hiding/duration = %d/%d, want 1000/150 (defaultScrollArea)",
			tokens.ScrollHidingMs, tokens.ScrollDurationMs)
	}
}

func TestChatScrollbarThumbGeometry(t *testing.T) {
	l := scrollbarList(500)
	v := history.Viewport{Top: 0, Height: 200}
	th := l.ScrollbarThumb(v, 200)
	if th.Hidden || th.Y != 3 || th.H != 77 {
		t.Fatalf("thumb at top = %+v, want Y 3 H 77", th)
	}
	v.Top = 150
	th = l.ScrollbarThumb(v, 200)
	if th.Hidden || th.Y != 61 || th.H != 77 {
		t.Fatalf("thumb at 150 = %+v, want Y 61 H 77 (barFrom 117*150/300 = 58)", th)
	}
	v.Top = 300
	th = l.ScrollbarThumb(v, 200)
	if th.Hidden || th.Y != 120 || th.H != 77 {
		t.Fatalf("thumb at max = %+v, want Y 120 H 77 (barFrom 117, cutTill 194)", th)
	}
}

func TestChatScrollbarThumbMinAndCut(t *testing.T) {
	l := scrollbarList(10000)
	v := history.Viewport{Top: 4900, Height: 200}
	th := l.ScrollbarThumb(v, 200)
	if th.Hidden || th.Y != 80 || th.H != 40 {
		t.Fatalf("min thumb mid-range = %+v, want Y 80 H 40 (barWanted 3 floored to 40)", th)
	}
	v.Top = -400
	th = l.ScrollbarThumb(v, 200)
	if th.Hidden || th.Y != 3 || th.H != 34 {
		t.Fatalf("cut thumb above top = %+v, want Y 3 H 34 (barFrom -6, cutTill 34)", th)
	}
	v.Top = 10200
	th = l.ScrollbarThumb(v, 200)
	if th.Hidden || th.Y != 163 || th.H != 34 {
		t.Fatalf("cut thumb past bottom = %+v, want Y 163 H 34 (cutFrom 160, cutTill 194)", th)
	}

	small := scrollbarList(4000)
	th = small.ScrollbarThumb(history.Viewport{Top: 0, Height: 40}, 60)
	if th.Hidden || th.Y != 3 || th.H != 27 {
		t.Fatalf("small-track thumb = %+v, want Y 3 H 27 (barMin min(40, 54/2))", th)
	}
	th = small.ScrollbarThumb(history.Viewport{Top: 3960, Height: 40}, 60)
	if th.Hidden || th.Y != 30 || th.H != 27 {
		t.Fatalf("small-track thumb at max = %+v, want Y 30 H 27", th)
	}

	if th := scrollbarList(40).ScrollbarThumb(history.Viewport{Top: 0, Height: 40}, 60); !th.Hidden {
		t.Fatalf("content == view must hide the thumb: %+v", th)
	}
	if th := l.ScrollbarThumb(history.Viewport{Top: 0, Height: 200}, 17); !th.Hidden {
		t.Fatalf("track under minSize 18 must hide the thumb: %+v", th)
	}
	if th := scrollbarList().ScrollbarThumb(history.Viewport{Top: 0, Height: 200}, 200); !th.Hidden {
		t.Fatalf("empty list must hide the thumb: %+v", th)
	}
	if th := l.ScrollbarThumb(history.Viewport{Top: 0, Height: 0}, 200); !th.Hidden {
		t.Fatalf("zero viewport must hide the thumb: %+v", th)
	}
}

func TestChatBarOver(t *testing.T) {
	l := scrollbarList(500)
	th := l.ScrollbarThumb(history.Viewport{Top: 150, Height: 200}, 200)
	if !history.BarOver(th, 3, 61) || !history.BarOver(th, 8, 137) {
		t.Fatal("points inside the 6-wide thumb strip must be over")
	}
	if history.BarOver(th, 2, 100) {
		t.Fatal("x left of deltax is not over")
	}
	if history.BarOver(th, 9, 100) {
		t.Fatal("x right of the strip is not over")
	}
	if history.BarOver(th, 5, 60) || history.BarOver(th, 5, 138) {
		t.Fatal("y outside [Y, Y+H) is not over")
	}
	if history.BarOver(history.Thumb{Hidden: true}, 5, 100) {
		t.Fatal("hidden thumb is never over")
	}
}

func TestChatBarTrackJump(t *testing.T) {
	l := scrollbarList(1000)
	v := history.Viewport{Top: 0, Height: 200}
	if top := l.BarTrackJump(v, 300, 150); top != 400 {
		t.Fatalf("jump(150) = %d, want 400 (800*(150-32)/236)", top)
	}
	if top := l.BarTrackJump(v, 300, 0); top != 0 {
		t.Fatalf("jump(0) = %d, want 0 (middle clamps to deltat+half)", top)
	}
	if top := l.BarTrackJump(v, 300, 299); top != 800 {
		t.Fatalf("jump(299) = %d, want 800 (middle clamps to the track end)", top)
	}
	if top := l.BarTrackJump(v, 300, 100); top != 230 {
		t.Fatalf("jump(100) = %d, want 230 (800*68/236 trunc)", top)
	}
	empty := scrollbarList()
	if top := empty.BarTrackJump(history.Viewport{Top: 5, Height: 200}, 300, 150); top != 5 {
		t.Fatalf("jump with hidden thumb = %d, want the scroll unchanged (5)", top)
	}
}

func TestChatBarDragScale(t *testing.T) {
	l := scrollbarList(1000)
	v := history.Viewport{Top: 0, Height: 200}
	if dy := l.BarDragScale(v, 300, 10); dy != 33 {
		t.Fatalf("scale(10) = %d, want 33 (10*800/236 trunc)", dy)
	}
	if dy := l.BarDragScale(v, 300, -20); dy != -67 {
		t.Fatalf("scale(-20) = %d, want -67 (-20*800/236 trunc)", dy)
	}
	short := scrollbarList(290)
	if dy := short.BarDragScale(history.Viewport{Top: 0, Height: 200}, 300, 7); dy != 7 {
		t.Fatalf("short-content scale(7) = %d, want 7 (scrollable <= outsideBar)", dy)
	}
	empty := scrollbarList()
	if dy := empty.BarDragScale(history.Viewport{Top: 0, Height: 200}, 300, 9); dy != 9 {
		t.Fatalf("hidden-thumb scale(9) = %d, want 9", dy)
	}
}

func TestChatApplyBarDragDeadZone(t *testing.T) {
	l := scrollbarList(1000)

	top, accum := l.ApplyBarDrag(history.Viewport{Top: 400, Height: 200}, 300, -59, 0)
	if top != 200 || accum != 0 {
		t.Fatalf("mid drag = %d/%d, want 200/0", top, accum)
	}

	top, accum = l.ApplyBarDrag(history.Viewport{Top: 0, Height: 200}, 300, -59, 0)
	if top != 0 || accum != -200 {
		t.Fatalf("edge drag = %d/%d, want 0/-200", top, accum)
	}
	top, accum = l.ApplyBarDrag(history.Viewport{Top: 0, Height: 200}, 300, 29, accum)
	if top != 0 || accum != -102 {
		t.Fatalf("partial reversal = %d/%d, want 0/-102", top, accum)
	}
	top, accum = l.ApplyBarDrag(history.Viewport{Top: 0, Height: 200}, 300, 59, accum)
	if top != 98 || accum != 0 {
		t.Fatalf("reversal release = %d/%d, want 98/0", top, accum)
	}

	top, accum = l.ApplyBarDrag(history.Viewport{Top: 800, Height: 200}, 300, 59, 0)
	if top != 800 || accum != 200 {
		t.Fatalf("bottom edge drag = %d/%d, want 800/200", top, accum)
	}
	top, accum = l.ApplyBarDrag(history.Viewport{Top: 800, Height: 200}, 300, -29, accum)
	if top != 800 || accum != 102 {
		t.Fatalf("bottom partial reversal = %d/%d, want 800/102", top, accum)
	}
	top, accum = l.ApplyBarDrag(history.Viewport{Top: 800, Height: 200}, 300, -59, accum)
	if top != 702 || accum != 0 {
		t.Fatalf("bottom release = %d/%d, want 702/0", top, accum)
	}

	top, accum = l.ApplyBarDrag(history.Viewport{Top: 100, Height: 200}, 300, 0, 7)
	if top != 100 || accum != 7 {
		t.Fatalf("zero delta = %d/%d, want 100/7 (change==0 skips the law)", top, accum)
	}
}

func TestChatPaneCarriesThumb(t *testing.T) {
	l := scrollbarList(360)
	pane := l.Pane(history.Viewport{Top: 0, Height: 300}, 800)
	if pane.Thumb.Hidden || pane.Thumb.Y != 3 || pane.Thumb.H != 245 {
		t.Fatalf("pane thumb = %+v, want Y 3 H 245 (barWanted 294*300/360)", pane.Thumb)
	}
	pane = l.Pane(history.Viewport{Top: 60, Height: 300}, 800)
	if pane.Thumb.Hidden || pane.Thumb.Y != 52 || pane.Thumb.H != 245 {
		t.Fatalf("pane thumb at max = %+v, want Y 52 H 245 (barFrom 49)", pane.Thumb)
	}
	empty := scrollbarList()
	pane = empty.Pane(history.Viewport{Top: 0, Height: 300}, 800)
	if !pane.Thumb.Hidden {
		t.Fatalf("empty pane thumb must be hidden: %+v", pane.Thumb)
	}
}
