package gui

import (
	"testing"

	"uniclient/engine"
)

// Chat-row context menu (AyuGram parity §2): action rows derive from the
// chat's flags — locked here.

func chatForMenu() engine.ChatInfo {
	return engine.ChatInfo{AccountID: "a", ChatID: "1", Type: engine.ChatTypeDMVal, Title: "Test"}
}

func TestChatMenuItemsDefault(t *testing.T) {
	items := chatMenuItems(chatForMenu())
	want := []string{"Mute for 1 hour", "Mute for 8 hours", "Mute forever", "Pin", "Mark as unread", "Archive", "Delete chat"}
	if len(items) != len(want) {
		t.Fatalf("items len = %d, want %d: %v", len(items), len(want), items)
	}
	for i, w := range want {
		if items[i].label != w {
			t.Errorf("items[%d] = %q, want %q", i, items[i].label, w)
		}
	}
}

func TestChatMenuItemsInverted(t *testing.T) {
	c := chatForMenu()
	c.IsMuted = true
	c.IsPinned = true
	c.UnreadCount = 4
	c.IsArchived = true
	items := chatMenuItems(c)
	want := []string{"Unmute", "Unpin", "Mark as read", "Unarchive", "Delete chat"}
	if len(items) != len(want) {
		t.Fatalf("items len = %d, want %d", len(items), len(want))
	}
	for i, w := range want {
		if items[i].label != w {
			t.Errorf("items[%d] = %q, want %q", i, items[i].label, w)
		}
	}
}
