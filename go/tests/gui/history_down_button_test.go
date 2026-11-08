package tests

import (
	"testing"

	. "uniclient/ui/app"
	"uniclient/ui/history"
)

func downChatItems(n int) []history.Item {
	items := make([]history.Item, n)
	for i := range items {
		items[i] = history.Item{
			Kind:     history.ItemMessage,
			Text:     "m",
			TimeText: "10:00",
			DateText: "Jan 1",
		}
	}
	return items
}

func downModel(t *testing.T, items []history.Item) Model {
	t.Helper()
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 120})
	m.HasDialogs = false
	m, _ = Update(m, ChatLoaded{Items: items})
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(len(items), 50)})
	return m
}

func chatScrollTo(m Model, top, now int) Model {
	m, _ = Update(m, ChatScrolled{DeltaY: top - m.ChatScroll.Top, Now: now})
	return m
}

func settleDownAnim(m Model, now int) Model {
	m, _ = Update(m, ChatTick{Now: now})
	return m
}

func TestChatDownShowsOnScrollUp(t *testing.T) {
	m := downModel(t, downChatItems(40))
	m = chatScrollTo(m, 1880, 1000)
	m = settleDownAnim(m, 1150)
	if m.ChatDown.Shown || m.ChatDown.Progress != 0 || m.ChatDown.Anim {
		t.Fatalf("at bottom: %+v, want hidden and settled", m.ChatDown)
	}
	m, _ = Update(m, ChatScrolled{DeltaY: -500, Now: 1200})
	if !m.ChatDown.Shown || !m.ChatDown.Anim || m.ChatDown.Progress != 0 || m.ChatDown.From != 0 || m.ChatDown.To != 1 {
		t.Fatalf("after scroll up: %+v, want shown animating from 0 to 1", m.ChatDown)
	}
	if !m.ChatDownActive() {
		t.Fatalf("ChatDownActive false while animating")
	}
}

func TestChatDownAnimates(t *testing.T) {
	m := downModel(t, downChatItems(40))
	m = chatScrollTo(m, 1880, 1000)
	m = settleDownAnim(m, 1150)
	m = chatScrollTo(m, 1380, 1200)
	m = settleDownAnim(m, 1275)
	if m.ChatDown.Progress != 0.5 {
		t.Fatalf("mid progress = %v, want 0.5", m.ChatDown.Progress)
	}
	m = settleDownAnim(m, 1350)
	if m.ChatDown.Progress != 1 || m.ChatDown.Anim || m.ChatDownActive() {
		t.Fatalf("end progress = %v anim=%v, want 1 settled", m.ChatDown.Progress, m.ChatDown.Anim)
	}
	m = chatScrollTo(m, 1880, 1400)
	if m.ChatDown.Shown || !m.ChatDown.Anim || m.ChatDown.From != 1 || m.ChatDown.To != 0 {
		t.Fatalf("hide at bottom: %+v, want hidden animating from 1 to 0", m.ChatDown)
	}
	m = settleDownAnim(m, 1550)
	if m.ChatDown.Progress != 0 || m.ChatDown.Anim {
		t.Fatalf("hidden end: %+v, want progress 0 settled", m.ChatDown)
	}
}

func TestChatDownUnreadBelowFold(t *testing.T) {
	items := downChatItems(40)
	items[39].UnreadBar = "Unread messages"
	m := downModel(t, items)
	m = chatScrollTo(m, 1880, 1000)
	m = settleDownAnim(m, 1150)
	m = chatScrollTo(m, 1830, 1200)
	if !m.ChatDown.Shown {
		t.Fatalf("unread below fold within 480px of bottom: hidden, want shown")
	}
}

func TestChatDownClickJumpsToBottom(t *testing.T) {
	m := downModel(t, downChatItems(40))
	m = chatScrollTo(m, 1880, 1000)
	m = settleDownAnim(m, 1150)
	m = chatScrollTo(m, 1380, 1200)
	m = settleDownAnim(m, 1350)
	m, _ = Update(m, ChatPressed{X: 750, Y: 80, Now: 1400})
	m, _ = Update(m, ChatReleased{X: 750, Y: 80, Now: 1410})
	if m.ChatScroll.Top != 1880 {
		t.Fatalf("after click top = %d, want 1880", m.ChatScroll.Top)
	}
	if m.ChatDown.Shown {
		t.Fatalf("after click to bottom: shown, want hidden")
	}
}

func TestChatDownClickJumpsToUnread(t *testing.T) {
	items := downChatItems(40)
	items[35].UnreadBar = "Unread messages"
	m := downModel(t, items)
	m = chatScrollTo(m, 1880, 1000)
	m = settleDownAnim(m, 1150)
	m = chatScrollTo(m, 1380, 1200)
	m = settleDownAnim(m, 1350)
	m, _ = Update(m, ChatPressed{X: 750, Y: 80, Now: 1400})
	m, _ = Update(m, ChatReleased{X: 750, Y: 80, Now: 1410})
	if m.ChatScroll.Top != 1750 {
		t.Fatalf("after click top = %d, want 1750 (first unread row)", m.ChatScroll.Top)
	}
	if m.ChatDown.Shown {
		t.Fatalf("after jump to unread: shown, want hidden")
	}
}

func TestChatDownDragCancelsClick(t *testing.T) {
	m := downModel(t, downChatItems(40))
	m = chatScrollTo(m, 1880, 1000)
	m = settleDownAnim(m, 1150)
	m = chatScrollTo(m, 1380, 1200)
	m = settleDownAnim(m, 1350)
	m, _ = Update(m, ChatPressed{X: 750, Y: 80, Now: 1400})
	m, _ = Update(m, ChatDragged{X: 400, Y: 400, Now: 1420})
	m, _ = Update(m, ChatReleased{X: 400, Y: 400, Now: 1430})
	if m.ChatScroll.Top != 1380 {
		t.Fatalf("drag-cancelled click moved top to %d, want 1380", m.ChatScroll.Top)
	}
}

func TestChatDownReleaseOutsideCancelsClick(t *testing.T) {
	m := downModel(t, downChatItems(40))
	m = chatScrollTo(m, 1880, 1000)
	m = settleDownAnim(m, 1150)
	m = chatScrollTo(m, 1380, 1200)
	m = settleDownAnim(m, 1350)
	m, _ = Update(m, ChatPressed{X: 750, Y: 80, Now: 1400})
	m, _ = Update(m, ChatDragged{X: 750, Y: 79, Now: 1410})
	m, _ = Update(m, ChatReleased{X: 700, Y: 40, Now: 1420})
	if m.ChatScroll.Top != 1380 {
		t.Fatalf("outside release moved top to %d, want 1380", m.ChatScroll.Top)
	}
}

func TestChatDownTouchTapJumps(t *testing.T) {
	m := downModel(t, downChatItems(40))
	m = chatScrollTo(m, 1880, 1000)
	m = settleDownAnim(m, 1150)
	m = chatScrollTo(m, 1380, 1200)
	m = settleDownAnim(m, 1350)
	m, _ = Update(m, ChatPressed{X: 750, Y: 80, Touch: true, Now: 1400})
	if m.ChatTouch.Active {
		t.Fatalf("touch press on button started a touch drag, want button press only")
	}
	m, _ = Update(m, ChatReleased{X: 750, Y: 80, Now: 1440})
	if m.ChatScroll.Top != 1880 {
		t.Fatalf("touch tap top = %d, want 1880", m.ChatScroll.Top)
	}
}

func TestChatDownTouchDragFromButtonDoesNotScroll(t *testing.T) {
	m := downModel(t, downChatItems(40))
	m = chatScrollTo(m, 1880, 1000)
	m = settleDownAnim(m, 1150)
	m = chatScrollTo(m, 1380, 1200)
	m = settleDownAnim(m, 1350)
	m, _ = Update(m, ChatPressed{X: 750, Y: 80, Touch: true, Now: 1400})
	m, _ = Update(m, ChatDragged{X: 750, Y: 260, Now: 1460})
	m, _ = Update(m, ChatReleased{X: 750, Y: 260, Now: 1500})
	if m.ChatScroll.Top != 1380 {
		t.Fatalf("touch drag from button scrolled to %d, want 1380 (button grabs)", m.ChatScroll.Top)
	}
}

func TestChatDownResetsOnChatSwitch(t *testing.T) {
	m := downModel(t, downChatItems(40))
	m = chatScrollTo(m, 1880, 1000)
	m = settleDownAnim(m, 1150)
	m = chatScrollTo(m, 1380, 1200)
	m = settleDownAnim(m, 1350)
	m, _ = Update(m, ChatLoaded{Items: downChatItems(2)})
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(2, 50)})
	if m.ChatDown.Shown || m.ChatDown.Progress != 0 || m.ChatDown.Anim {
		t.Fatalf("after chat switch: %+v, want reset hidden settled", m.ChatDown)
	}
}

func TestChatDownPaneProgress(t *testing.T) {
	m := downModel(t, downChatItems(40))
	m = chatScrollTo(m, 1880, 1000)
	m = settleDownAnim(m, 1150)
	m = chatScrollTo(m, 1380, 1200)
	m = settleDownAnim(m, 1275)
	if s := View(m); s.Chat.DownProgress != m.ChatDown.Progress {
		t.Fatalf("pane progress = %v, want %v", s.Chat.DownProgress, m.ChatDown.Progress)
	}
	m = settleDownAnim(m, 1350)
	if s := View(m); s.Chat.DownProgress != 1 {
		t.Fatalf("pane progress = %v, want 1", s.Chat.DownProgress)
	}
}
