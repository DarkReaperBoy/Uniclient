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
		want := []string{"Mute notifications", "View profile", "Search", "Scheduled messages", "Auto-delete…", "Shadow-banned users…", "Clear deleted messages", "Change colors…", "Block user", "Clear history", "Delete chat"}
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
	// slice 79: search + add-members on groups/channels, never DMs.
	if !actions["search"] || !actions["addmember"] {
		t.Fatalf("group menu missing slice-79 rows: %v", actions)
	}
	if items := headerMenuItems(dmChat(), false, false); containsAction(items, "addmember") {
		t.Fatal("DM menu must not offer Add members")
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

func TestAddMemFilter(t *testing.T) {
	contacts := []engine.ContactInfo{
		{UserID: "1", DisplayName: "Alice Smith", Username: "asmith", Phone: "+111"},
		{UserID: "2", DisplayName: "Bob", Username: "bob", Phone: "+222"},
		{UserID: "3", DisplayName: "Carol", Username: "carol"},
	}
	if got := addMemFilter(contacts, ""); len(got) != 3 {
		t.Errorf("empty query → %d, want all 3", len(got))
	}
	if got := addMemFilter(contacts, "alice"); len(got) != 1 || got[0].UserID != "1" {
		t.Errorf("name filter → %+v", got)
	}
	if got := addMemFilter(contacts, "BOB"); len(got) != 1 || got[0].UserID != "2" {
		t.Errorf("case-insensitive filter → %+v", got)
	}
	if got := addMemFilter(contacts, "+222"); len(got) != 1 || got[0].UserID != "2" {
		t.Errorf("phone filter → %+v", got)
	}
	if got := addMemFilter(contacts, "  zz "); len(got) != 0 {
		t.Errorf("no match → %d, want 0", len(got))
	}
}

func TestPluralS(t *testing.T) {
	if pluralS(1) != "" || pluralS(2) != "s" || pluralS(0) != "s" {
		t.Errorf("pluralS broken: %q %q %q", pluralS(1), pluralS(2), pluralS(0))
	}
}
