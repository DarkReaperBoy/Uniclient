package gui

import (
	"testing"

	"uniclient/engine"
)

// Archived-chats collapsed row (AyuGram parity slice 67): archived chats hide
// behind one collapsed row at the top of the chat list with an aggregate
// unread badge; opening it filters the list to archived chats only. The
// split/aggregate/filter rules are pure and locked here.

func TestSplitArchived(t *testing.T) {
	chats := []engine.ChatInfo{
		{ChatID: "1", Title: "main"},
		{ChatID: "2", Title: "arch", IsArchived: true},
		{ChatID: "3", Title: "main2"},
		{ChatID: "4", Title: "arch2", IsArchived: true},
	}
	main, arch := splitArchived(chats)
	if len(main) != 2 || main[0].ChatID != "1" || main[1].ChatID != "3" {
		t.Fatalf("main = %+v", main)
	}
	if len(arch) != 2 || arch[0].ChatID != "2" || arch[1].ChatID != "4" {
		t.Fatalf("arch = %+v", arch)
	}
}

func TestSplitArchivedEmpty(t *testing.T) {
	main, arch := splitArchived(nil)
	if len(main) != 0 || len(arch) != 0 {
		t.Fatalf("split(nil) = %d/%d", len(main), len(arch))
	}
}

func TestArchiveAggregateUnread(t *testing.T) {
	arch := []engine.ChatInfo{
		{ChatID: "1", UnreadCount: 3},
		{ChatID: "2", UnreadCount: 5, IsMuted: true}, // muted chats don't count
		{ChatID: "3", UnreadCount: 0},
	}
	if n := archiveAggregateUnread(arch); n != 3 {
		t.Fatalf("aggregate = %d, want 3", n)
	}
	if n := archiveAggregateUnread(nil); n != 0 {
		t.Fatalf("aggregate(nil) = %d, want 0", n)
	}
}

func archiveTestFrame() frame {
	return frame{
		chats: []engine.ChatInfo{
			{AccountID: "a", ChatID: "1", Title: "main chat"},
			{AccountID: "a", ChatID: "2", Title: "archived chat", IsArchived: true},
		},
	}
}

func TestFilterChatsHidesArchivedByDefault(t *testing.T) {
	visible := filterChats(archiveTestFrame())
	if len(visible) != 1 || visible[0].ChatID != "1" {
		t.Fatalf("default view must hide archived chats, got %+v", visible)
	}
}

func TestFilterChatsArchiveViewOnlyArchived(t *testing.T) {
	f := archiveTestFrame()
	f.archiveView = true
	visible := filterChats(f)
	if len(visible) != 1 || visible[0].ChatID != "2" {
		t.Fatalf("archive view must show only archived chats, got %+v", visible)
	}
}

func TestFilterChatsSearchIncludesArchived(t *testing.T) {
	f := archiveTestFrame()
	f.search = "archived"
	visible := filterChats(f)
	if len(visible) != 1 || visible[0].ChatID != "2" {
		t.Fatalf("search must include archived chats, got %+v", visible)
	}
	// …and inside the archive view, search still only sees archived chats.
	f.archiveView = true
	f.search = "main"
	if visible := filterChats(f); len(visible) != 0 {
		t.Fatalf("archive-view search must not surface main chats, got %+v", visible)
	}
}

func TestFilterChatsArchiveViewScopedToAccount(t *testing.T) {
	f := archiveTestFrame()
	f.chats = append(f.chats, engine.ChatInfo{AccountID: "b", ChatID: "3", Title: "other acct", IsArchived: true})
	f.archiveView = true
	f.acctFilter = "a"
	visible := filterChats(f)
	if len(visible) != 1 || visible[0].ChatID != "2" {
		t.Fatalf("account filter must apply in archive view, got %+v", visible)
	}
}
