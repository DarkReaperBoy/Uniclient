package gui

import (
	"testing"

	"uniclient/engine"
)

// Header "..." menu (gui/headermenu.go, slice 15).

func dmChat() engine.ChatInfo {
	return engine.ChatInfo{AccountID: "a", ChatID: "u1", Type: engine.ChatTypeDMVal, Title: "Alice"}
}

func TestHeaderMenuItemsDM(t *testing.T) {
	t.Run("default", func(t *testing.T) {
		items := headerMenuItems(dmChat(), false, false)
		labels := make([]string, len(items))
		for i, it := range items {
			labels[i] = it.label
		}
		want := []string{"Mute notifications", "View profile", "Scheduled messages", "Auto-delete…", "Block user", "Clear history", "Delete chat"}
		if len(labels) != len(want) {
			t.Fatalf("labels = %v, want %v", labels, want)
		}
		for i := range want {
			if labels[i] != want[i] {
				t.Fatalf("labels = %v, want %v", labels, want)
			}
		}
	})

	t.Run("muted swaps label", func(t *testing.T) {
		c := dmChat()
		c.IsMuted = true
		items := headerMenuItems(c, false, false)
		if items[0].label != "Unmute" || items[0].action != "unmute" {
			t.Fatalf("first item = %+v", items[0])
		}
	})

	t.Run("blocked known swaps to unblock", func(t *testing.T) {
		items := headerMenuItems(dmChat(), true, true)
		found := false
		for _, it := range items {
			if it.action == "unblock" {
				found = true
			}
			if it.action == "block" {
				t.Fatal("block should not appear when blocked state is known")
			}
		}
		if !found {
			t.Fatal("unblock missing")
		}
	})
}

func TestHeaderMenuItemsGroupChannel(t *testing.T) {
	g := engine.ChatInfo{AccountID: "a", ChatID: "g1", Type: engine.ChatTypeGroupVal}
	items := headerMenuItems(g, false, false)
	actions := map[string]bool{}
	for _, it := range items {
		actions[it.action] = true
	}
	if actions["block"] || actions["delete"] {
		t.Fatalf("group menu has DM-only rows: %v", actions)
	}
	if !actions["leave"] || !actions["clear"] || !actions["profile"] {
		t.Fatalf("group menu missing rows: %v", actions)
	}

	c := engine.ChatInfo{AccountID: "a", ChatID: "c1", Type: engine.ChatTypeChanVal}
	if items := headerMenuItems(c, false, false); !containsAction(items, "leave") {
		t.Fatalf("channel menu = %+v", items)
	}
}

func containsAction(items []chatMenuAction, action string) bool {
	for _, it := range items {
		if it.action == action {
			return true
		}
	}
	return false
}

func TestHeaderMenuConfirmText(t *testing.T) {
	for _, id := range []string{"clear", "leave", "delete"} {
		title, hint := headerMenuConfirmText(id)
		if title == "" || hint == "" {
			t.Errorf("confirm(%q) = %q, %q — both must be set", id, title, hint)
		}
	}
	if title, hint := headerMenuConfirmText("zz"); title != "" || hint != "" {
		t.Errorf("unknown confirm should be empty")
	}
}
