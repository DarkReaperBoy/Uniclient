package gui

import (
	"testing"

	"uniclient/engine"
)

// Floating next-unread button (AyuGram parity slice 30).

func unreadChat(id string, n int) engine.ChatInfo {
	return engine.ChatInfo{ChatID: id, UnreadCount: n}
}

func TestNextUnreadIndex(t *testing.T) {
	chats := []engine.ChatInfo{
		unreadChat("a", 0),
		unreadChat("b", 3),
		unreadChat("c", 0),
		unreadChat("d", 1),
	}
	if got := nextUnreadIndex(chats, 0); got != 1 {
		t.Errorf("from 0 = %d, want 1", got)
	}
	if got := nextUnreadIndex(chats, 2); got != 3 {
		t.Errorf("from 2 = %d, want 3", got)
	}
	if got := nextUnreadIndex(chats, 3); got != 3 { // starts at from
		t.Errorf("from 3 = %d, want 3", got)
	}
	if got := nextUnreadIndex(chats, 4); got != 1 { // wraps to first unread
		t.Errorf("from 4 = %d, want 1 (wrap)", got)
	}
	if got := nextUnreadIndex(chats, 100); got != 1 { // clamps + wraps
		t.Errorf("from 100 = %d, want 1", got)
	}
	if got := nextUnreadIndex(nil, 0); got != -1 {
		t.Errorf("empty = %d, want -1", got)
	}
	if got := nextUnreadIndex([]engine.ChatInfo{unreadChat("x", 0)}, 0); got != -1 {
		t.Errorf("no unread = %d, want -1", got)
	}
}

func TestNextUnreadIndexMark(t *testing.T) {
	chats := []engine.ChatInfo{
		{ChatID: "a", UnreadMark: true},
	}
	if got := nextUnreadIndex(chats, 0); got != 0 {
		t.Errorf("unread-mark chat = %d, want 0", got)
	}
}

func TestHasUnreadChats(t *testing.T) {
	if hasUnreadChats(nil) {
		t.Error("nil slice reports unread")
	}
	if hasUnreadChats([]engine.ChatInfo{unreadChat("a", 0)}) {
		t.Error("read-only slice reports unread")
	}
	if !hasUnreadChats([]engine.ChatInfo{unreadChat("a", 0), unreadChat("b", 2)}) {
		t.Error("unread chat not detected")
	}
	if !hasUnreadChats([]engine.ChatInfo{{ChatID: "a", UnreadMark: true}}) {
		t.Error("unread mark not detected")
	}
}
