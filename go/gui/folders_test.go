package gui

import (
	"testing"

	"uniclient/engine"
)

// Folder tabs (AyuGram parity §2): buildFolderTabs scoping and Telegram
// dialog-filter matching.

func dm(id string) engine.ChatInfo {
	return engine.ChatInfo{AccountID: "acc", ChatID: id, Type: engine.ChatTypeDMVal, Title: id}
}

func TestBuildFolderTabs(t *testing.T) {
	// Unified view: smart tabs, no server folders, no create tab.
	tabs := buildFolderTabs("", nil, true, false)
	if len(tabs) != 5 || tabs[0].name != "All" || tabs[1].name != "Unread" ||
		tabs[2].name != "People" || tabs[3].name != "Groups" || tabs[4].name != "Channels" {
		t.Fatalf("unified tabs = %v", tabs)
	}

	// Scoped account with folder support: server tabs + create tab.
	folders := []engine.FolderInfo{
		{ID: "1", Name: "Work", Emoticon: "💼"},
		{ID: "2", Name: ""},
	}
	tabs = buildFolderTabs("acc", folders, true, false)
	want := []string{"All", "Unread", "💼 Work", "Folder", "+"}
	if len(tabs) != len(want) {
		t.Fatalf("scoped tabs len = %d, want %d", len(tabs), len(want))
	}
	for i, w := range want {
		if tabs[i].name != w {
			t.Errorf("tabs[%d] = %q, want %q", i, tabs[i].name, w)
		}
	}
	if tabs[2].kind != folderTabServer || tabs[2].folder == nil || tabs[2].folder.ID != "1" {
		t.Error("server tab missing folder ref")
	}
	if tabs[4].kind != folderTabNew {
		t.Error("last tab should be the create tab")
	}

	// Scoped account without folder support: smart tabs.
	tabs = buildFolderTabs("acc", nil, false, false)
	if len(tabs) != 5 || tabs[4].kind != folderTabChannels {
		t.Fatalf("unsupported tabs = %v", tabs)
	}
}

func TestTabMatches(t *testing.T) {
	unread := dm("u1")
	unread.UnreadCount = 3
	group := engine.ChatInfo{AccountID: "acc", ChatID: "g1", Type: engine.ChatTypeGroupVal}
	channel := engine.ChatInfo{AccountID: "acc", ChatID: "c1", Type: engine.ChatTypeChanVal}

	cases := []struct {
		tab  folderTab
		chat engine.ChatInfo
		want bool
	}{
		{folderTab{kind: folderTabAll}, dm("x"), true},
		{folderTab{kind: folderTabUnread}, dm("x"), false},
		{folderTab{kind: folderTabUnread}, unread, true},
		{folderTab{kind: folderTabPeople}, group, false},
		{folderTab{kind: folderTabGroups}, group, true},
		{folderTab{kind: folderTabChannels}, channel, true},
		{folderTab{kind: folderTabChannels}, group, false},
		{folderTab{kind: folderTabServer, folder: nil}, dm("x"), true},
	}
	for _, c := range cases {
		if got := tabMatches(c.tab, c.chat); got != c.want {
			t.Errorf("tabMatches(%v, %s) = %v, want %v", c.tab, c.chat.ChatID, got, c.want)
		}
	}
}

func TestFolderContains(t *testing.T) {
	work := engine.ChatInfo{AccountID: "acc", ChatID: "100", Type: engine.ChatTypeGroupVal}
	group := engine.ChatInfo{AccountID: "acc", ChatID: "g1", Type: engine.ChatTypeGroupVal}

	// Explicit include wins even when excluded flags would drop it.
	f := engine.FolderInfo{ChatIDs: []string{"100"}, ExcludeMuted: true}
	work.IsMuted = true
	if !folderContains(f, work) {
		t.Error("explicit include should win")
	}
	work.IsMuted = false

	// Exclude list blocks.
	f = engine.FolderInfo{Groups: true, ExcludeChatIDs: []string{"100"}}
	if folderContains(f, work) {
		t.Error("exclude list should block")
	}

	// Flag match.
	f = engine.FolderInfo{Groups: true}
	if !folderContains(f, work) {
		t.Error("groups flag should match a group")
	}

	// ExcludeRead drops read chats.
	f = engine.FolderInfo{Groups: true, ExcludeRead: true}
	if folderContains(f, work) {
		t.Error("ExcludeRead should drop read chats")
	}
	work.UnreadCount = 2
	if !folderContains(f, work) {
		t.Error("unread group should match")
	}

	// ExcludeArchived.
	work.UnreadCount = 2
	f = engine.FolderInfo{Groups: true, ExcludeArchived: true}
	work.IsArchived = true
	if folderContains(f, work) {
		t.Error("ExcludeArchived should drop archived chats")
	}
	work.IsArchived = false
	if !folderContains(f, work) {
		t.Error("non-archived should match")
	}

	// Contacts / bots flags.
	person := dm("200")
	f = engine.FolderInfo{Contacts: true}
	if folderContains(f, person) {
		t.Error("non-contact should not match Contacts folder")
	}
	person.IsContact = true
	if !folderContains(f, person) {
		t.Error("contact should match Contacts folder")
	}
	bot := dm("300")
	bot.IsBot = true
	f = engine.FolderInfo{Bots: true}
	if !folderContains(f, bot) {
		t.Error("bot should match Bots folder")
	}

	// NonContacts: people only, excluding contacts.
	f = engine.FolderInfo{NonContacts: true}
	if !folderContains(f, dm("400")) {
		t.Error("non-contact person should match NonContacts folder")
	}
	if folderContains(f, person) {
		t.Error("contact person should not match NonContacts folder")
	}
	if folderContains(f, group) {
		t.Error("group should not match NonContacts folder")
	}
}

// Hide All-chats (slice 85): the tab drops, others shift up.

func TestBuildFolderTabsHideAll(t *testing.T) {
	tabs := buildFolderTabs("", nil, true, true)
	if len(tabs) == 0 || tabs[0].kind != folderTabUnread {
		t.Fatalf("hidden-All tabs = %+v, want Unread first", tabs)
	}
	for _, tab := range tabs {
		if tab.kind == folderTabAll {
			t.Fatal("All tab present despite hideAll")
		}
	}
	// With folders: Unread stays first, the server folder follows (All gone).
	folders := []engine.FolderInfo{{ID: "1", Name: "Work"}}
	tabs = buildFolderTabs("acc", folders, true, true)
	if len(tabs) != 3 || tabs[0].kind != folderTabUnread || tabs[1].name != "Work" || tabs[1].kind != folderTabServer {
		t.Fatalf("hidden-All w/ folders = %+v, want [Unread, Work, +]", tabs)
	}
}
