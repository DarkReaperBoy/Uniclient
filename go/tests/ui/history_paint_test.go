package tests

import (
	"testing"

	"uniclient/ui/history"
	"uniclient/ui/tokens"
)

func TestChatModeFor(t *testing.T) {
	if history.ChatModeFor(879) != history.ModeNormal {
		t.Fatalf("879 should be normal mode")
	}
	if history.ChatModeFor(880) != history.ModeWide {
		t.Fatalf("880 should be wide mode")
	}
	if history.ChatModeFor(1920) != history.ModeWide {
		t.Fatalf("1920 should be wide mode")
	}
}

func TestMessageRoundingLaw(t *testing.T) {
	base := history.MessageRounding(false, false, false, false, false)
	if base != (history.BubbleRounding{
		TopLeft:     history.CornerLarge,
		TopRight:    history.CornerLarge,
		BottomLeft:  history.CornerTail,
		BottomRight: history.CornerLarge,
	}) {
		t.Fatalf("plain in: %+v", base)
	}
	out := history.MessageRounding(false, false, true, false, false)
	if out.BottomLeft != history.CornerLarge || out.BottomRight != history.CornerTail {
		t.Fatalf("plain out: %+v", out)
	}
	top := history.MessageRounding(true, false, false, false, false)
	if top.TopLeft != history.CornerSmall || top.TopRight != history.CornerLarge {
		t.Fatalf("attached top in: %+v", top)
	}
	topOut := history.MessageRounding(true, false, true, false, false)
	if topOut.TopLeft != history.CornerLarge || topOut.TopRight != history.CornerSmall {
		t.Fatalf("attached top out: %+v", topOut)
	}
	bottom := history.MessageRounding(false, true, false, false, false)
	if bottom.BottomLeft != history.CornerSmall || bottom.BottomRight != history.CornerLarge {
		t.Fatalf("attached bottom in: %+v", bottom)
	}
	bottomOut := history.MessageRounding(false, true, true, false, false)
	if bottomOut.BottomLeft != history.CornerLarge || bottomOut.BottomRight != history.CornerSmall {
		t.Fatalf("attached bottom out: %+v", bottomOut)
	}
	skip := history.MessageRounding(false, false, false, true, false)
	if skip.BottomLeft != history.CornerLarge || skip.BottomRight != history.CornerLarge {
		t.Fatalf("skipTail in: %+v", skip)
	}
	kb := history.MessageRounding(false, false, false, false, true)
	if kb.BottomLeft != history.CornerSmall || kb.BottomRight != history.CornerSmall {
		t.Fatalf("keyboard in: %+v", kb)
	}
}

func TestBubbleCornerRadii(t *testing.T) {
	if r := history.CornerRadius(history.CornerLarge); r != tokens.BubbleRadiusLarge {
		t.Fatalf("large = %d, want %d", r, tokens.BubbleRadiusLarge)
	}
	if r := history.CornerRadius(history.CornerSmall); r != tokens.BubbleRadiusSmall {
		t.Fatalf("small = %d, want %d", r, tokens.BubbleRadiusSmall)
	}
	if r := history.CornerRadius(history.CornerTail); r != 0 {
		t.Fatalf("tail radius = %d, want 0", r)
	}
	if r := history.CornerRadius(history.CornerNone); r != 0 {
		t.Fatalf("none radius = %d, want 0", r)
	}
	plain := history.MessageRounding(false, false, false, false, false)
	radii := history.BubbleCorners(plain, false)
	if radii != [4]int{16, 16, 0, 16} {
		t.Fatalf("plain in corners = %v", radii)
	}
	removed := history.BubbleCorners(plain, true)
	if removed != [4]int{16, 16, 16, 16} {
		t.Fatalf("removeTail in corners = %v", removed)
	}
	if left, right := history.BubbleTails(plain, false); !left || right {
		t.Fatalf("plain in tails = %v %v", left, right)
	}
	if left, right := history.BubbleTails(plain, true); left || right {
		t.Fatalf("removeTail in tails = %v %v", left, right)
	}
	plainOut := history.MessageRounding(false, false, true, false, false)
	if left, right := history.BubbleTails(plainOut, false); left || !right {
		t.Fatalf("plain out tails = %v %v", left, right)
	}
	attached := history.MessageRounding(false, true, false, false, false)
	if left, right := history.BubbleTails(attached, false); left || right {
		t.Fatalf("attached bottom tails = %v %v", left, right)
	}
}

func TestTailRect(t *testing.T) {
	g := history.Geometry{Left: 100, Top: 50, Width: 200, Height: 80}
	left := history.TailRect(history.TailLeft, g)
	if left != (history.Geometry{Left: 94, Top: 120, Width: 6, Height: 10}) {
		t.Fatalf("left tail = %+v", left)
	}
	right := history.TailRect(history.TailRight, g)
	if right != (history.Geometry{Left: 300, Top: 120, Width: 6, Height: 10}) {
		t.Fatalf("right tail = %+v", right)
	}
}

func TestShadowStrip(t *testing.T) {
	g := history.Geometry{Left: 100, Top: 50, Width: 200, Height: 80}
	plain := history.MessageRounding(false, false, false, false, false)
	s, ok := history.ShadowStrip(g, plain, false)
	if !ok || s != (history.Geometry{Left: 94, Top: 130, Width: 190, Height: 2}) {
		t.Fatalf("plain in shadow = %+v %v", s, ok)
	}
	plainOut := history.MessageRounding(false, false, true, false, false)
	s, ok = history.ShadowStrip(g, plainOut, false)
	if !ok || s != (history.Geometry{Left: 116, Top: 130, Width: 190, Height: 2}) {
		t.Fatalf("plain out shadow = %+v %v", s, ok)
	}
	attached := history.MessageRounding(false, true, false, false, false)
	s, ok = history.ShadowStrip(g, attached, false)
	if !ok || s != (history.Geometry{Left: 106, Top: 130, Width: 178, Height: 2}) {
		t.Fatalf("attached bottom shadow = %+v %v", s, ok)
	}
	skip := history.MessageRounding(false, false, false, true, false)
	s, ok = history.ShadowStrip(g, skip, false)
	if !ok || s != (history.Geometry{Left: 116, Top: 130, Width: 168, Height: 2}) {
		t.Fatalf("skipTail shadow = %+v %v", s, ok)
	}
	s, ok = history.ShadowStrip(g, plain, true)
	if !ok || s != (history.Geometry{Left: 116, Top: 130, Width: 168, Height: 2}) {
		t.Fatalf("removeTail shadow = %+v %v", s, ok)
	}
	narrow := history.Geometry{Left: 100, Top: 50, Width: 10, Height: 80}
	if _, ok = history.ShadowStrip(narrow, plain, false); ok {
		t.Fatalf("narrow plain in shadow should vanish")
	}
}

func TestServicePill(t *testing.T) {
	if r := history.ServicePillRadius(18); r != 12 {
		t.Fatalf("pill radius(18) = %d, want 12", r)
	}
	if r := history.ServicePillRadius(19); r != 13 {
		t.Fatalf("pill radius(19) = %d, want 13", r)
	}
	g := history.Geometry{Left: 50, Top: 20, Width: 300, Height: 40}
	pill := history.ServicePill(g, 100, 18)
	if pill != (history.Geometry{Left: 138, Top: 20, Width: 124, Height: 25}) {
		t.Fatalf("pill = %+v", pill)
	}
	pill = history.ServicePill(g, 250, 18)
	if pill != (history.Geometry{Left: 63, Top: 20, Width: 274, Height: 25}) {
		t.Fatalf("wide pill = %+v", pill)
	}
}

func TestServiceTimeBadgePosition(t *testing.T) {
	trect := history.Geometry{Left: 50, Top: 20, Width: 300, Height: 26}
	x, y, gap := history.ServiceTimeBadgePosition(trect, 100, 30, 18, 22, 1)
	if x != 228 || y != 18 || gap != tokens.AyuServiceTimeBadgeGap {
		t.Fatalf("badge pos = %d %d %d", x, y, gap)
	}
	x, y, gap = history.ServiceTimeBadgePosition(trect, 25, 30, 18, 22, 1)
	if x != 187 || y != 18 || gap != 0 {
		t.Fatalf("short last line badge pos = %d %d %d", x, y, gap)
	}
	_, y, _ = history.ServiceTimeBadgePosition(trect, 100, 30, 18, 22, 2)
	if y != 36 {
		t.Fatalf("second line badge y = %d, want 36", y)
	}
}

func TestTimeLabel(t *testing.T) {
	g := history.Geometry{Left: 100, Top: 50, Width: 200, Height: 80}
	x, y, _, _ := history.TimeLabel(g, 40, 16, 16, false)
	if x != 251 || y != 111 {
		t.Fatalf("time label = %d %d", x, y)
	}
	tx, ty, ix, iy := history.TimeLabel(g, 40, 16, 16, true)
	if tx != 227 || ty != 111 || ix != 274 || iy != 108 {
		t.Fatalf("send-state time label = %d %d %d %d", tx, ty, ix, iy)
	}
}

func TestChatViewportLaws(t *testing.T) {
	l := history.List{Items: make([]history.Item, 4), Heights: []int{30, 40, 50, 60}}
	if h := l.ContentHeight(); h != 180 {
		t.Fatalf("content = %d, want 180", h)
	}
	v := history.Viewport{Top: 0, Height: 100}
	if m := l.MaxOffset(v); m != 80 {
		t.Fatalf("max offset = %d, want 80", m)
	}
	if c := l.ClampOffset(-5, v); c != 0 {
		t.Fatalf("clamp -5 = %d", c)
	}
	if c := l.ClampOffset(50, v); c != 50 {
		t.Fatalf("clamp 50 = %d", c)
	}
	if c := l.ClampOffset(90, v); c != 80 {
		t.Fatalf("clamp 90 = %d", c)
	}
	tall := history.Viewport{Top: 0, Height: 200}
	if m := l.MaxOffset(tall); m != 0 {
		t.Fatalf("tall max offset = %d, want 0", m)
	}
}

func TestChatVisibleRows(t *testing.T) {
	l := history.List{Items: make([]history.Item, 4), Heights: []int{30, 40, 50, 60}}
	first, count := l.VisibleRows(history.Viewport{Top: 35, Height: 100})
	if first != 1 || count != 3 {
		t.Fatalf("visible(35,100) = %d %d, want 1 3", first, count)
	}
	first, count = l.VisibleRows(history.Viewport{Top: 0, Height: 100})
	if first != 0 || count != 3 {
		t.Fatalf("visible(0,100) = %d %d, want 0 3", first, count)
	}
	first, count = l.VisibleRows(history.Viewport{Top: 180, Height: 100})
	if first != 4 || count != 0 {
		t.Fatalf("visible(180,100) = %d %d, want 4 0", first, count)
	}
	first, count = l.VisibleRows(history.Viewport{Top: 70, Height: 0})
	if first != 0 || count != 0 {
		t.Fatalf("visible(70,0) = %d %d, want 0 0 (zero-height viewport paints nothing)", first, count)
	}
}

func TestChatPane(t *testing.T) {
	l := history.List{Items: make([]history.Item, 4), Heights: []int{30, 40, 50, 60}}
	pane := l.Pane(history.Viewport{Top: 70, Height: 60}, 320)
	if pane.Width != 320 || pane.View != (history.Viewport{Top: 70, Height: 60}) {
		t.Fatalf("pane header = %+v", pane)
	}
	if pane.First != 2 || pane.Count != 2 {
		t.Fatalf("pane rows = %d %d, want 2 2", pane.First, pane.Count)
	}
	if len(pane.Rows) != 2 || len(pane.Ys) != 2 {
		t.Fatalf("pane slices = %d %d", len(pane.Rows), len(pane.Ys))
	}
	if pane.Ys[0] != 70 || pane.Ys[1] != 120 {
		t.Fatalf("pane ys = %v", pane.Ys)
	}
}

func TestChatPaneEmpty(t *testing.T) {
	l := history.List{}
	pane := l.Pane(history.Viewport{Top: 0, Height: 100}, 320)
	if pane.First != 0 || pane.Count != 0 || len(pane.Rows) != 0 {
		t.Fatalf("empty pane = %+v", pane)
	}
}
