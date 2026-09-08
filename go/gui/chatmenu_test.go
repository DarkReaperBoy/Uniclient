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

func TestChatMenuItemsNonDMNoBlock(t *testing.T) {
	c := chatForMenu()
	c.Type = engine.ChatTypeGroupVal
	items := chatMenuItems(c)
	for _, it := range items {
		if it.action == "block" {
			t.Errorf("groups/channels must not offer Block user")
		}
	}
}

func TestChatMenuItemsDefault(t *testing.T) {
	items := chatMenuItems(chatForMenu())
	want := []string{"Mute for 1 hour", "Mute for 8 hours", "Mute forever", "Pin", "Mark as unread", "Archive", "Block user", "Delete chat"}
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
	want := []string{"Unmute", "Unpin", "Mark as read", "Unarchive", "Block user", "Delete chat"}
	if len(items) != len(want) {
		t.Fatalf("items len = %d, want %d", len(items), len(want))
	}
	for i, w := range want {
		if items[i].label != w {
			t.Errorf("items[%d] = %q, want %q", i, items[i].label, w)
		}
	}
}

// Add-to-folder picker (slice 27): the frame's server folders are scoped to
// one account; the menu only offers folders loaded for the chat's account.

func TestFoldersForAccountScope(t *testing.T) {
	fls := []engine.FolderInfo{{ID: "2", Name: "Work"}}
	f := frame{folders: fls, foldersFor: "a", foldersSupported: true}

	if got := foldersForAccount(f, "a"); len(got) != 1 || got[0].ID != "2" {
		t.Errorf("foldersForAccount(same account) = %v, want the one folder", got)
	}
	if got := foldersForAccount(f, "b"); got != nil {
		t.Errorf("foldersForAccount(other account) = %v, want nil", got)
	}
	f2 := f
	f2.foldersFor = ""
	if got := foldersForAccount(f2, ""); got != nil {
		t.Errorf("foldersForAccount(empty scope) = %v, want nil", got)
	}
}

func TestFolderNames(t *testing.T) {
	fls := []engine.FolderInfo{
		{ID: "1", Name: "Work", Emoticon: "💼"},
		{ID: "2", Name: ""},
	}
	got := folderNames(fls)
	if len(got) != 2 || got[0] != "💼 Work" || got[1] != "Folder" {
		t.Errorf("folderNames = %q, want [\"💼 Work\" \"Folder\"]", got)
	}
}
