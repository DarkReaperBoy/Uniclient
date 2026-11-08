package tests

import (
	"testing"

	. "uniclient/ui/app"
	"uniclient/ui/dialogs"
	"uniclient/ui/history"
)

func chatInputModel(t *testing.T, w, h, items int, rowH int) Model {
	t.Helper()
	list := make([]history.Item, items)
	heights := make([]int, items)
	for i := range list {
		list[i] = history.Item{Kind: history.ItemMessage, Text: "m"}
		heights[i] = rowH
	}
	m, _ := Update(InitialModel(), Resized{Width: w, Height: h})
	m, _ = Update(m, ChatLoaded{Items: list})
	m, _ = Update(m, ChatMeasured{Heights: heights})
	return m
}

func TestChatWheelScrollsClamped(t *testing.T) {
	m := chatInputModel(t, 800, 120, 4, 50)
	m, cmd := Update(m, ChatWheel{AngleY: -160, Now: 1000})
	if m.ChatScroll.Top != 80 {
		t.Fatalf("wheel to the exact bottom = %d, want 80", m.ChatScroll.Top)
	}
	if cmd != nil {
		t.Fatal("landing exactly on the bottom must not fire the bottom request")
	}
	m, cmd = Update(m, ChatWheel{AngleY: -120, Now: 1010})
	if m.ChatScroll.Top != 80 {
		t.Fatalf("wheel past end = %d, want 80 (clamped, no rubber band on classic wheel)", m.ChatScroll.Top)
	}
	if cmd == nil {
		t.Fatal("wheel past the bottom edge must fire the bottom content request")
	}
	m, _ = Update(m, ChatWheel{AngleY: 120, Now: 1020})
	if m.ChatScroll.Top != 20 {
		t.Fatalf("wheel up = %d, want 20", m.ChatScroll.Top)
	}
}

func TestChatWheelCrossAxisIgnored(t *testing.T) {
	m := chatInputModel(t, 800, 120, 4, 50)
	m, _ = Update(m, ChatWheel{AngleX: -130, AngleY: -120, Y: 10, Now: 1000})
	if m.ChatScroll.Top != 0 {
		t.Fatalf("horizontal-dominant wheel = %d, want 0 (routed to consumeScrollAction, nothing consumes)", m.ChatScroll.Top)
	}
	m, _ = Update(m, ChatTrackpadScrolled{PixelX: -50, PixelY: -40, Y: 10, Now: 1010})
	if m.ChatScroll.Top != 0 {
		t.Fatalf("horizontal-dominant trackpad = %d, want 0", m.ChatScroll.Top)
	}
}

func TestChatWheelAccelerate(t *testing.T) {
	m := chatInputModel(t, 800, 300, 10, 50)
	m, cmd := Update(m, ChatWheel{AngleY: -120, Accelerate: true, Now: 1000})
	if m.ChatScroll.Top != 150 {
		t.Fatalf("accel notch = %d, want 150 (60 * max(300,120)/120)", m.ChatScroll.Top)
	}
	if cmd != nil {
		t.Fatal("in-content accelerate must not fire the bottom request")
	}
}

func TestChatWheelBottomRequestFires(t *testing.T) {
	m := chatInputModel(t, 800, 120, 4, 50)
	m, _ = Update(m, ChatScrolled{DeltaY: 1000})
	if m.ChatScroll.Top != 80 {
		t.Fatalf("setup = %d, want 80 (at the bottom)", m.ChatScroll.Top)
	}
	m, cmd := Update(m, ChatWheel{AngleY: -120, Now: 1000})
	if m.ChatScroll.Top != 80 {
		t.Fatalf("wheel at bottom = %d, want 80", m.ChatScroll.Top)
	}
	if cmd == nil {
		t.Fatal("wheel past the bottom edge must fire the bottom content request")
	}
	if got := cmd(); got != (ChatBottomRequested{}) {
		t.Fatalf("bottom request cmd = %T, want ChatBottomRequested", got)
	}
	m, cmd = Update(m, ChatTrackpadScrolled{PixelY: -40, Now: 1010})
	if cmd == nil {
		t.Fatal("trackpad past the bottom edge must fire the bottom content request")
	}
	m, _ = Update(m, ChatScrolled{DeltaY: -1000})
	m, cmd = Update(m, ChatWheel{AngleY: 120, Now: 1020})
	if cmd != nil {
		t.Fatal("wheel up must not fire the bottom request")
	}
}

func TestChatTrackpadScrolls(t *testing.T) {
	m := chatInputModel(t, 800, 120, 4, 50)
	m, _ = Update(m, ChatTrackpadScrolled{PixelY: -40, Now: 1000})
	if m.ChatScroll.Top != 40 {
		t.Fatalf("trackpad = %d, want 40", m.ChatScroll.Top)
	}
	m, _ = Update(m, ChatTrackpadScrolled{PixelY: -40, Accelerate: true, Now: 1010})
	if m.ChatScroll.Top != 80 {
		t.Fatalf("trackpad accel = %d, want 80 (40 + 100 clamped)", m.ChatScroll.Top)
	}
}

func TestChatWheelBeforeMeasured(t *testing.T) {
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 120})
	m, _ = Update(m, ChatLoaded{Items: make([]history.Item, 4)})
	m, cmd := Update(m, ChatWheel{AngleY: -120, Now: 1000})
	if m.ChatScroll.Top != 0 {
		t.Fatalf("wheel before measure = %d, want 0", m.ChatScroll.Top)
	}
	if cmd == nil {
		t.Fatal("the geometry gate still fires on an empty history (the content host no-ops)")
	}
}

func TestChatTouchDragClampsAtEdge(t *testing.T) {
	m := chatInputModel(t, 800, 120, 4, 50)
	m, _ = Update(m, ChatPressed{X: 400, Y: 100, Touch: true, Now: 1000})
	m, _ = Update(m, ChatDragged{X: 400, Y: 90, Now: 1010})
	if m.ChatScroll.Top != 0 {
		t.Fatalf("arm = %d, want 0 (crossing delta swallowed)", m.ChatScroll.Top)
	}
	m, _ = Update(m, ChatDragged{X: 400, Y: 70, Now: 1020})
	if m.ChatScroll.Top != 20 {
		t.Fatalf("follow = %d, want 20 (1:1, no overscroll pipeline)", m.ChatScroll.Top)
	}
	m, _ = Update(m, ChatDragged{X: 400, Y: -1000, Now: 1030})
	if m.ChatScroll.Top != 80 {
		t.Fatalf("past bottom = %d, want 80 (clamped hard, no rubber band on chat touch)", m.ChatScroll.Top)
	}
	m, _ = Update(m, ChatDragged{X: 400, Y: -1100, Now: 1040})
	if m.ChatScroll.Top != 80 {
		t.Fatalf("deeper past bottom = %d, want 80", m.ChatScroll.Top)
	}
}

func TestChatTouchFlingStopsAtEdge(t *testing.T) {
	m := chatInputModel(t, 800, 120, 4, 50)
	m, _ = Update(m, ChatPressed{X: 400, Y: 100, Touch: true, Now: 1000})
	m, _ = Update(m, ChatDragged{X: 400, Y: 90, Now: 1010})
	m, _ = Update(m, ChatDragged{X: 400, Y: 70, Now: 1020})
	m, _ = Update(m, ChatDragged{X: 400, Y: 50, Now: 1030})
	if m.ChatScroll.Top != 40 {
		t.Fatalf("setup = %d, want 40", m.ChatScroll.Top)
	}
	m, _ = Update(m, ChatReleased{X: 400, Y: 50, Now: 1040})
	if m.ChatTouch.State != dialogs.TouchScrollAuto {
		t.Fatalf("release = state %d, want auto", m.ChatTouch.State)
	}
	m, _ = Update(m, ChatTick{Now: 1055})
	if m.ChatScroll.Top != 70 {
		t.Fatalf("fling tick = %d, want 70 (-30 content)", m.ChatScroll.Top)
	}
	m, _ = Update(m, ChatTick{Now: 1070})
	m, _ = Update(m, ChatTick{Now: 1085})
	if m.KineticActive() {
		t.Fatalf("fling at the bottom edge must stop dead (hasScrolled), state %d top %d",
			m.ChatTouch.State, m.ChatScroll.Top)
	}
	if m.ChatScroll.Top != 80 || m.ChatTouch.State != dialogs.TouchScrollManual || m.ChatTouch.Scrolling {
		t.Fatalf("edge stop = top %d state %d scrolling %v, want 80/manual/false",
			m.ChatScroll.Top, m.ChatTouch.State, m.ChatTouch.Scrolling)
	}
}

func TestChatTouchFlingRunsInList(t *testing.T) {
	m := chatInputModel(t, 800, 120, 40, 50)
	m, _ = Update(m, ChatPressed{X: 400, Y: 100, Touch: true, Now: 1000})
	m, _ = Update(m, ChatDragged{X: 400, Y: 90, Now: 1010})
	m, _ = Update(m, ChatDragged{X: 400, Y: 70, Now: 1020})
	m, _ = Update(m, ChatDragged{X: 400, Y: 50, Now: 1030})
	m, _ = Update(m, ChatReleased{X: 400, Y: 50, Now: 1040})
	m, _ = Update(m, ChatTick{Now: 1055})
	m, _ = Update(m, ChatTick{Now: 1070})
	if m.ChatScroll.Top != 100 {
		t.Fatalf("fling ticks = %d, want 100 (40+30+30, qRound fling deltas)", m.ChatScroll.Top)
	}
	if !m.KineticActive() {
		t.Fatal("fling mid-list must stay kinetic")
	}
}

func TestChatTouchTapIsClean(t *testing.T) {
	m := chatInputModel(t, 800, 120, 4, 50)
	m, _ = Update(m, ChatPressed{X: 400, Y: 100, Touch: true, Now: 1000})
	m, _ = Update(m, ChatReleased{X: 400, Y: 102, Now: 1030})
	if m.ChatScroll.Top != 0 {
		t.Fatalf("tap = %d, want 0 (no scroll)", m.ChatScroll.Top)
	}
	if m.ChatTouch.Active || m.ChatTouch.State != dialogs.TouchScrollManual {
		t.Fatalf("tap reset = active %v state %d, want false/manual", m.ChatTouch.Active, m.ChatTouch.State)
	}
}

func TestChatTouchCancelResets(t *testing.T) {
	m := chatInputModel(t, 800, 120, 4, 50)
	m, _ = Update(m, ChatPressed{X: 400, Y: 100, Touch: true, Now: 1000})
	m, _ = Update(m, ChatDragged{X: 400, Y: 90, Now: 1010})
	m, _ = Update(m, ChatDragged{X: 400, Y: 70, Now: 1020})
	m, _ = Update(m, ChatPressCanceled{})
	if m.ChatTouch.Active || m.ChatTouch.State != dialogs.TouchScrollManual || m.ChatTouch.Scrolling {
		t.Fatalf("cancel = active %v state %d scrolling %v, want false/manual/false",
			m.ChatTouch.Active, m.ChatTouch.State, m.ChatTouch.Scrolling)
	}
	m, _ = Update(m, ChatTick{Now: 1030})
	if m.KineticActive() || m.ChatScroll.Top != 20 {
		t.Fatalf("after cancel = active %v top %d, want false/20 (no fling without release)", m.KineticActive(), m.ChatScroll.Top)
	}
}

func TestChatTouchAccelerationUnderFinger(t *testing.T) {
	m := chatInputModel(t, 800, 120, 40, 50)
	m, _ = Update(m, ChatPressed{X: 400, Y: 100, Touch: true, Now: 1000})
	m, _ = Update(m, ChatDragged{X: 400, Y: 90, Now: 1010})
	m, _ = Update(m, ChatDragged{X: 400, Y: 70, Now: 1020})
	m, _ = Update(m, ChatDragged{X: 400, Y: 50, Now: 1030})
	m, _ = Update(m, ChatReleased{X: 400, Y: 50, Now: 1040})
	m, _ = Update(m, ChatTick{Now: 1055})
	m, _ = Update(m, ChatPressed{X: 400, Y: 200, Touch: true, Now: 1060})
	if m.ChatTouch.State != dialogs.TouchScrollAcceleration || !m.ChatTouch.WaitingAcceleration {
		t.Fatalf("press during fling = state %d waiting %v, want acceleration/true",
			m.ChatTouch.State, m.ChatTouch.WaitingAcceleration)
	}
	m, _ = Update(m, ChatTick{Now: 1075})
	if m.ChatScroll.Top != 110 {
		t.Fatalf("fling continues under finger = %d, want 110 (-40 qRound)", m.ChatScroll.Top)
	}
	m, _ = Update(m, ChatTick{Now: 1090})
	m, _ = Update(m, ChatTick{Now: 1105})
	if m.ChatTouch.State != dialogs.TouchScrollManual {
		t.Fatalf("40ms stillness = state %d, want manual", m.ChatTouch.State)
	}
	m, _ = Update(m, ChatDragged{X: 400, Y: 130, Now: 1115})
	if m.ChatScroll.Top != 209 {
		t.Fatalf("manual resume = %d, want 209 (139 + 70)", m.ChatScroll.Top)
	}
}
