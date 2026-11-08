package tests

import (
	"testing"

	. "uniclient/ui/app"
	"uniclient/ui/dialogs"
	"uniclient/ui/history"
	"uniclient/ui/tokens"
)

func uniformHeights(n, h int) []int {
	hs := make([]int, n)
	for i := range hs {
		hs[i] = h
	}
	return hs
}

func preloadItems(n int) []history.Item {
	items := make([]history.Item, n)
	for i := range items {
		items[i] = history.Item{Kind: history.ItemMessage, Text: "m", TimeText: "10:00"}
	}
	return items
}

func TestHistoryPreloadIfLessThanScreensToken(t *testing.T) {
	if tokens.HistoryPreloadIfLessThanScreens != 2 {
		t.Fatalf("history preload screens drifted: %d (want 2 — history_view_list_widget.cpp kPreloadIfLessThanScreens)",
			tokens.HistoryPreloadIfLessThanScreens)
	}
}

func TestHistoryPreloadTopNeeded(t *testing.T) {
	l := history.List{Items: preloadItems(6)}
	if !l.PreloadTopNeeded(history.Viewport{Top: 0, Height: 100}) {
		t.Fatal("top 0 must preload")
	}
	if !l.PreloadTopNeeded(history.Viewport{Top: 199, Height: 100}) {
		t.Fatal("top 199 < 200 must preload")
	}
	if l.PreloadTopNeeded(history.Viewport{Top: 200, Height: 100}) {
		t.Fatal("top 200 = 2 screens must not preload (strict <)")
	}
	if l.PreloadTopNeeded(history.Viewport{Top: 0, Height: 0}) {
		t.Fatal("zero viewport height must not preload (visibleHeight gate)")
	}
	empty := history.List{}
	if empty.PreloadTopNeeded(history.Viewport{Top: 0, Height: 100}) {
		t.Fatal("empty list must not preload (checkMoveToOtherViewer gate)")
	}
}

func TestChatPreloadFiresOnMeasureNearTop(t *testing.T) {
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 120})
	m, _ = Update(m, ChatLoaded{Items: preloadItems(6), MoreAbove: true})
	m, cmd := Update(m, ChatMeasured{Heights: uniformHeights(6, 50)})
	if cmd == nil {
		t.Fatal("measure near top with more-above must fire the preload cmd")
	}
	if _, ok := cmd().(ChatPreloadTopRequested); !ok {
		t.Fatalf("preload cmd emitted %T, want ChatPreloadTopRequested", cmd())
	}
	m, cmd = Update(m, ChatMeasured{Heights: uniformHeights(6, 50)})
	if cmd == nil {
		t.Fatal("still near top: the request must stay armed (engine owns dedup)")
	}
}

func TestChatPreloadGatedByMoreAbove(t *testing.T) {
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 120})
	m, _ = Update(m, ChatLoaded{Items: preloadItems(6)})
	m, cmd := Update(m, ChatMeasured{Heights: uniformHeights(6, 50)})
	if cmd != nil {
		t.Fatal("no more-above must never preload")
	}
	m, cmd = Update(m, ChatScrolled{DeltaY: 20})
	if cmd != nil {
		t.Fatal("no more-above must never preload on scroll")
	}
}

func TestChatPreloadScrollTriggerAndBoundary(t *testing.T) {
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 120})
	m, _ = Update(m, ChatLoaded{Items: preloadItems(4), MoreAbove: true})
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(4, 50)})
	m, _ = Update(m, ChatPrepended{Items: preloadItems(20), MoreAbove: true})
	m, cmd := Update(m, ChatMeasured{Heights: uniformHeights(24, 50)})
	if m.ChatScroll.Top != 1000 {
		t.Fatalf("compensated top = %d, want 1000", m.ChatScroll.Top)
	}
	if cmd != nil {
		t.Fatal("far from top must not preload")
	}
	m, cmd = Update(m, ChatScrolled{DeltaY: -760})
	if m.ChatScroll.Top != 240 {
		t.Fatalf("boundary scroll top = %d, want 240", m.ChatScroll.Top)
	}
	if cmd != nil {
		t.Fatal("top exactly 2 screens must not preload (strict <)")
	}
	m, cmd = Update(m, ChatScrolled{DeltaY: -1})
	if cmd == nil {
		t.Fatal("scroll inside the 2-screen zone must preload")
	}
}

func TestChatWheelAndTrackpadPreload(t *testing.T) {
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 120})
	m, _ = Update(m, ChatLoaded{Items: preloadItems(4), MoreAbove: true})
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(4, 50)})
	m, _ = Update(m, ChatPrepended{Items: preloadItems(20), MoreAbove: true})
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(24, 50)})
	if m.ChatScroll.Top != 1000 {
		t.Fatalf("setup: top = %d, want 1000", m.ChatScroll.Top)
	}
	m, cmd := Update(m, ChatWheel{AngleY: 12000})
	if m.ChatScroll.Top != 0 {
		t.Fatalf("wheel up lands at top, got %d", m.ChatScroll.Top)
	}
	if cmd == nil {
		t.Fatal("wheel fling to top must fire the preload cmd")
	}
	m, _ = Update(m, ChatPrepended{Items: preloadItems(20), MoreAbove: true})
	m, cmd = Update(m, ChatMeasured{Heights: uniformHeights(44, 50)})
	if m.ChatScroll.Top != 1000 {
		t.Fatalf("setup: compensated top = %d, want 1000 (0 + 20*50)", m.ChatScroll.Top)
	}
	m, cmd = Update(m, ChatTrackpadScrolled{PixelY: 2000})
	if cmd == nil {
		t.Fatal("trackpad fling to top must fire the preload cmd")
	}
}

func TestChatTickPreloadDuringFling(t *testing.T) {
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 120})
	m, _ = Update(m, ChatLoaded{Items: preloadItems(4), MoreAbove: true})
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(4, 50)})
	m, _ = Update(m, ChatPrepended{Items: preloadItems(20), MoreAbove: true})
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(24, 50)})
	m, _ = Update(m, ChatScrolled{DeltaY: -760})
	if m.ChatScroll.Top != 240 {
		t.Fatalf("setup: top = %d, want 240", m.ChatScroll.Top)
	}
	m.ChatTouch = TouchDrag{State: dialogs.TouchScrollAuto, Speed: dialogs.TouchSpeed{Y: 2000},
		TouchTime: 100, LastY: 0}
	m, cmd := Update(m, ChatTick{Now: 115})
	if m.ChatScroll.Top != 210 {
		t.Fatalf("fling top = %d, want 210 (240 - 2000*15/1000)", m.ChatScroll.Top)
	}
	if cmd == nil {
		t.Fatal("kinetic fling into the 2-screen zone must preload")
	}
}

func TestChatDragPreloadDuringTouchScroll(t *testing.T) {
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 120})
	m, _ = Update(m, ChatLoaded{Items: preloadItems(4), MoreAbove: true})
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(4, 50)})
	m, _ = Update(m, ChatPrepended{Items: preloadItems(20), MoreAbove: true})
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(24, 50)})
	m, _ = Update(m, ChatScrolled{DeltaY: -760})
	m.ChatTouch = TouchDrag{Active: true, Scrolling: true, State: dialogs.TouchScrollManual,
		LastX: 300, LastY: 300}
	m, cmd := Update(m, ChatDragged{X: 300, Y: 400, Now: 100})
	if m.ChatScroll.Top != 140 {
		t.Fatalf("touch-drag top = %d, want 140 (240 - 100)", m.ChatScroll.Top)
	}
	if cmd == nil {
		t.Fatal("touch drag into the 2-screen zone must preload")
	}
}

func TestChatResizedPreload(t *testing.T) {
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 120})
	m, _ = Update(m, ChatLoaded{Items: preloadItems(4), MoreAbove: true})
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(4, 50)})
	m, _ = Update(m, ChatPrepended{Items: preloadItems(20), MoreAbove: true})
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(24, 50)})
	m, _ = Update(m, ChatScrolled{DeltaY: -850})
	if m.ChatScroll.Top != 150 {
		t.Fatalf("setup: top = %d, want 150", m.ChatScroll.Top)
	}
	m, cmd := Update(m, Resized{Width: 800, Height: 500})
	if m.ChatScroll.Top != 150 {
		t.Fatalf("resize must keep top 150 (content 1200 - 500), got %d", m.ChatScroll.Top)
	}
	if cmd == nil {
		t.Fatal("viewport growth past the top edge must re-arm the preload (150 < 2*500)")
	}
}

func TestChatScrollCmdPriority(t *testing.T) {
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 120})
	m, _ = Update(m, ChatLoaded{Items: preloadItems(4), MoreAbove: true})
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(4, 50)})
	if m.ChatScroll.Top != 0 {
		t.Fatalf("setup: top = %d, want 0", m.ChatScroll.Top)
	}
	m, _ = Update(m, ChatWheel{AngleY: -160})
	if m.ChatScroll.Top != 80 {
		t.Fatalf("setup: wheel down to bottom = %d, want 80", m.ChatScroll.Top)
	}
	m, cmd := Update(m, ChatWheel{AngleY: -120})
	if _, ok := cmd().(ChatBottomRequested); !ok {
		t.Fatalf("at bottom edge the bottom request wins the cmd slot, got %T", cmd())
	}
}

func TestChatPrependCompensation(t *testing.T) {
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 120})
	m, _ = Update(m, ChatLoaded{Items: preloadItems(6), MoreAbove: true})
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(6, 50)})
	m, _ = Update(m, ChatScrolled{DeltaY: 60})
	if m.ChatScroll.Top != 60 {
		t.Fatalf("setup: top = %d, want 60", m.ChatScroll.Top)
	}
	m, _ = Update(m, ChatPrepended{Items: preloadItems(3), MoreAbove: true})
	if !m.ChatDirty || m.Chat.Heights != nil || m.Chat.Hits != nil {
		t.Fatal("prepend must invalidate measurement")
	}
	if len(m.Chat.Items) != 9 {
		t.Fatalf("prepended items = %d, want 9", len(m.Chat.Items))
	}
	if m.ChatSelection != nil {
		t.Fatal("prepend must clear the row-index selection")
	}
	if m.ChatPress.Row != -1 {
		t.Fatal("prepend must drop the shifted press row")
	}
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(9, 50)})
	if m.ChatScroll.Top != 210 {
		t.Fatalf("compensated top = %d, want 210 (60 + 3*50)", m.ChatScroll.Top)
	}
	if m.Chat.RowAt(m.ChatScroll.Top) != 4 {
		t.Fatalf("viewport top row = %d, want 4 (old row 1 stays first visible)",
			m.Chat.RowAt(m.ChatScroll.Top))
	}
}

func TestChatPrependEmptyReply(t *testing.T) {
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 120})
	m, _ = Update(m, ChatLoaded{Items: preloadItems(6), MoreAbove: true})
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(6, 50)})
	m, _ = Update(m, ChatScrolled{DeltaY: 30})
	m, cmd := Update(m, ChatPrepended{MoreAbove: false})
	if cmd != nil {
		t.Fatal("empty reply must not fire")
	}
	if m.ChatMoreAbove {
		t.Fatal("empty reply must clear more-above")
	}
	if len(m.Chat.Items) != 6 || m.ChatDirty || m.Chat.Heights == nil {
		t.Fatal("empty reply must not touch the loaded window")
	}
	if m.ChatScroll.Top != 30 {
		t.Fatalf("empty reply must keep top, got %d", m.ChatScroll.Top)
	}
	m, cmd = Update(m, ChatScrolled{DeltaY: -30})
	if cmd != nil {
		t.Fatal("more-above cleared: no further preload")
	}
}

func TestChatLoadedResetsPreloadState(t *testing.T) {
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 120})
	m, _ = Update(m, ChatLoaded{Items: preloadItems(4), MoreAbove: true})
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(4, 50)})
	m, _ = Update(m, ChatPrepended{Items: preloadItems(3), MoreAbove: true})
	m, _ = Update(m, ChatLoaded{Items: preloadItems(2), MoreAbove: false})
	if m.ChatMoreAbove {
		t.Fatal("reload must take more-above from the message")
	}
	if m.ChatPrependRows != 0 || m.ChatPrependTop != 0 {
		t.Fatalf("reload must clear the pending prepend: rows %d top %d",
			m.ChatPrependRows, m.ChatPrependTop)
	}
	if len(m.Chat.Items) != 2 {
		t.Fatalf("reload must replace items, got %d", len(m.Chat.Items))
	}
	m, cmd := Update(m, ChatMeasured{Heights: uniformHeights(2, 50)})
	if cmd != nil {
		t.Fatal("no more-above after reload: measure must not preload")
	}
	if m.ChatScroll.Top != 0 {
		t.Fatalf("reload must land at top, got %d", m.ChatScroll.Top)
	}
}
