package tests

import (
	"testing"

	. "uniclient/ui/app"
	"uniclient/ui/history"
)

func chatDragModel(t *testing.T) (Model, int) {
	t.Helper()
	items := make([]history.Item, 6)
	heights := []int{60, 60, 60, 60, 60, 60}
	m := chatModel(t, 800, 300, items, heights)
	return m, m.Columns().Chat
}

func TestChatBarPressOnThumbDrags(t *testing.T) {
	m, chatW := chatDragModel(t)
	m, _ = Update(m, ChatPressed{X: chatW - 5, Y: 150})
	if !m.ChatBar.Dragging {
		t.Fatal("press on the thumb must start a bar drag")
	}
	if m.ChatScroll.Top != 0 {
		t.Fatalf("on-thumb press must not jump: top = %d", m.ChatScroll.Top)
	}

	m, _ = Update(m, ChatDragged{X: chatW - 5, Y: 100})
	if m.ChatScroll.Top != 0 || m.ChatBar.Overscroll != -61 {
		t.Fatalf("edge drag = %d/%d, want 0/-61", m.ChatScroll.Top, m.ChatBar.Overscroll)
	}
	m, _ = Update(m, ChatDragged{X: chatW - 5, Y: 120})
	if m.ChatScroll.Top != 0 || m.ChatBar.Overscroll != -37 {
		t.Fatalf("partial reversal = %d/%d, want 0/-37", m.ChatScroll.Top, m.ChatBar.Overscroll)
	}
	m, _ = Update(m, ChatDragged{X: chatW - 5, Y: 160})
	if m.ChatScroll.Top != 11 || m.ChatBar.Overscroll != 0 {
		t.Fatalf("reversal release = %d/%d, want 11/0", m.ChatScroll.Top, m.ChatBar.Overscroll)
	}

	s := View(m)
	if !s.Chat.ThumbDragging {
		t.Fatal("scene must mark the thumb dragging while the bar drag lives")
	}
	m, _ = Update(m, ChatReleased{X: chatW - 5, Y: 160})
	if m.ChatBar.Dragging {
		t.Fatal("release must end the bar drag")
	}
	if m.ChatScroll.Top != 11 {
		t.Fatalf("release must keep the scroll: top = %d", m.ChatScroll.Top)
	}
	s = View(m)
	if s.Chat.ThumbDragging {
		t.Fatal("scene must clear the thumb dragging mark after release")
	}
}

func TestChatBarPressOffThumbJumps(t *testing.T) {
	m, chatW := chatDragModel(t)
	m, _ = Update(m, ChatPressed{X: chatW - 5, Y: 260})
	if !m.ChatBar.Dragging {
		t.Fatal("off-thumb press must still start a bar drag")
	}
	if m.ChatScroll.Top != 60 {
		t.Fatalf("track jump = %d, want 60 (middle clamps to the track end)", m.ChatScroll.Top)
	}
	m, _ = Update(m, ChatDragged{X: chatW - 5, Y: 258})
	if m.ChatScroll.Top != 58 || m.ChatBar.Overscroll != 0 {
		t.Fatalf("drag off the end = %d/%d, want 58/0", m.ChatScroll.Top, m.ChatBar.Overscroll)
	}
}

func TestChatBarPressOutsideStrip(t *testing.T) {
	m, chatW := chatDragModel(t)
	m, _ = Update(m, ChatPressed{X: chatW / 2, Y: 100})
	if m.ChatBar.Dragging {
		t.Fatal("a press outside the scrollbar strip must not drag the bar")
	}
	m, _ = Update(m, ChatDragged{X: chatW / 2, Y: 40})
	if m.ChatScroll.Top != 0 {
		t.Fatalf("drag outside the strip must not scroll: top = %d", m.ChatScroll.Top)
	}
	m, _ = Update(m, ChatPressed{X: chatW - 5, Y: 150, Touch: true})
	if m.ChatBar.Dragging {
		t.Fatal("touch press in the strip must stay with the touch machine")
	}
	if !m.ChatTouch.Active {
		t.Fatal("touch press must arm the touch drag")
	}
}

func TestChatBarPressCanceled(t *testing.T) {
	m, chatW := chatDragModel(t)
	m, _ = Update(m, ChatPressed{X: chatW - 5, Y: 150})
	m, _ = Update(m, ChatDragged{X: chatW - 5, Y: 120})
	m, _ = Update(m, ChatPressCanceled{})
	if m.ChatBar.Dragging || m.ChatBar.Overscroll != 0 {
		t.Fatalf("cancel must clear the bar drag: %+v", m.ChatBar)
	}
}

func TestChatBarPressHiddenThumb(t *testing.T) {
	m := chatModel(t, 800, 300, make([]history.Item, 1), []int{100})
	chatW := m.Columns().Chat
	m, _ = Update(m, ChatPressed{X: chatW - 5, Y: 150})
	if m.ChatBar.Dragging {
		t.Fatal("press with a hidden thumb (content fits the view) must not drag")
	}
	m, _ = Update(m, ChatDragged{X: chatW - 5, Y: 100})
	if m.ChatScroll.Top != 0 {
		t.Fatalf("drag with a hidden thumb must not scroll: top = %d", m.ChatScroll.Top)
	}
}

func TestSceneChatThumb(t *testing.T) {
	m, _ := chatDragModel(t)
	s := View(m)
	if s.Chat.Thumb.Hidden || s.Chat.Thumb.Y != 3 || s.Chat.Thumb.H != 245 {
		t.Fatalf("scene thumb = %+v, want Y 3 H 245", s.Chat.Thumb)
	}
	m, _ = Update(m, ChatScrolled{DeltaY: 1000})
	if m.ChatScroll.Top != 60 {
		t.Fatalf("setup: top = %d, want 60", m.ChatScroll.Top)
	}
	s = View(m)
	if s.Chat.Thumb.Hidden || s.Chat.Thumb.Y != 52 || s.Chat.Thumb.H != 245 {
		t.Fatalf("scene thumb at max = %+v, want Y 52 H 245", s.Chat.Thumb)
	}
}
