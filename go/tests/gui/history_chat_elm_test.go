package tests

import (
	"testing"

	. "uniclient/ui/app"
	"uniclient/ui/history"
)

func chatModel(t *testing.T, w, h int, items []history.Item, heights []int) Model {
	t.Helper()
	m, _ := Update(InitialModel(), Resized{Width: w, Height: h})
	m, _ = Update(m, ChatLoaded{Items: items})
	m, _ = Update(m, ChatMeasured{Heights: heights})
	return m
}

func TestChatLoadedStoresItems(t *testing.T) {
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 600})
	items := []history.Item{
		{Kind: history.ItemMessage, Text: "hi", Out: false, TimeText: "10:00"},
		{Kind: history.ItemService, Text: "today"},
	}
	m, _ = Update(m, ChatLoaded{Items: items})
	if len(m.Chat.Items) != 2 || m.Chat.Items[1].Kind != history.ItemService {
		t.Fatalf("items not stored: %+v", m.Chat.Items)
	}
	if m.Chat.Heights != nil {
		t.Fatalf("heights not invalidated on reload: %+v", m.Chat.Heights)
	}
	m, _ = Update(m, ChatMeasured{Heights: []int{40, 25}})
	if len(m.Chat.Heights) != 2 || m.Chat.Heights[0] != 40 {
		t.Fatalf("heights not stored: %+v", m.Chat.Heights)
	}
}

func TestChatScrolledClamp(t *testing.T) {
	items := make([]history.Item, 4)
	heights := []int{50, 50, 50, 50}
	m := chatModel(t, 800, 120, items, heights)
	if m.ChatScroll.Height != 120 {
		t.Fatalf("viewport height = %d, want 120", m.ChatScroll.Height)
	}
	m, _ = Update(m, ChatScrolled{DeltaY: 50})
	if m.ChatScroll.Top != 50 {
		t.Fatalf("scroll +50 = %d", m.ChatScroll.Top)
	}
	m, _ = Update(m, ChatScrolled{DeltaY: 1000})
	if m.ChatScroll.Top != 80 {
		t.Fatalf("scroll past end = %d, want 80", m.ChatScroll.Top)
	}
	m, _ = Update(m, ChatScrolled{DeltaY: -1000})
	if m.ChatScroll.Top != 0 {
		t.Fatalf("scroll above top = %d", m.ChatScroll.Top)
	}
}

func TestChatScrolledBeforeMeasured(t *testing.T) {
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 120})
	m, _ = Update(m, ChatLoaded{Items: make([]history.Item, 4)})
	m, _ = Update(m, ChatScrolled{DeltaY: 1000})
	if m.ChatScroll.Top != 0 {
		t.Fatalf("scroll before measure = %d, want 0", m.ChatScroll.Top)
	}
}

func TestChatResizedClamps(t *testing.T) {
	items := make([]history.Item, 4)
	heights := []int{50, 50, 50, 50}
	m := chatModel(t, 800, 120, items, heights)
	m, _ = Update(m, ChatScrolled{DeltaY: 1000})
	if m.ChatScroll.Top != 80 {
		t.Fatalf("setup: top = %d, want 80", m.ChatScroll.Top)
	}
	m, _ = Update(m, Resized{Width: 800, Height: 400})
	if m.ChatScroll.Height != 400 || m.ChatScroll.Top != 0 {
		t.Fatalf("resize: %+v, want height 400 top 0", m.ChatScroll)
	}
}

func TestSceneChatPane(t *testing.T) {
	items := []history.Item{
		{Kind: history.ItemMessage, Text: "one"},
		{Kind: history.ItemMessage, Text: "two"},
		{Kind: history.ItemMessage, Text: "three"},
	}
	heights := []int{60, 60, 60}
	m := chatModel(t, 800, 100, items, heights)
	m, _ = Update(m, ChatScrolled{DeltaY: 1000})
	if m.ChatScroll.Top != 80 {
		t.Fatalf("setup: top = %d, want 80", m.ChatScroll.Top)
	}
	s := View(m)
	if s.Chat.First != 1 || s.Chat.Count != 2 {
		t.Fatalf("chat pane rows = %d %d, want 1 2", s.Chat.First, s.Chat.Count)
	}
	if s.Chat.Ys[0] != 60 {
		t.Fatalf("chat pane ys = %v", s.Chat.Ys)
	}
	if s.Chat.View.Top != 80 {
		t.Fatalf("chat pane view = %+v", s.Chat.View)
	}
}

func TestSceneChatPaneSingleColumn(t *testing.T) {
	items := []history.Item{{Kind: history.ItemMessage, Text: "one"}}
	m := chatModel(t, 500, 300, items, []int{40})
	s := View(m)
	if s.Chat.Width != 500 {
		t.Fatalf("single column chat width = %d, want 500", s.Chat.Width)
	}
}
