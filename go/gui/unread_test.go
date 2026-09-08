package gui

import (
	"testing"

	"uniclient/engine"
)

// Per-account unread dots (AyuGram parity slice 36).

func TestAccountUnread(t *testing.T) {
	chats := []engine.ChatInfo{
		{AccountID: "a1", UnreadCount: 3},
		{AccountID: "a1", UnreadCount: 2},
		{AccountID: "a2", UnreadCount: 7},
		{AccountID: "a2"},
	}
	if got := accountUnread(chats, "a1"); got != 5 {
		t.Errorf("a1 unread = %d, want 5", got)
	}
	if got := accountUnread(chats, "a2"); got != 7 {
		t.Errorf("a2 unread = %d, want 7", got)
	}
	if got := accountUnread(chats, "a3"); got != 0 {
		t.Errorf("unknown account unread = %d, want 0", got)
	}
	if got := accountUnread(nil, "a1"); got != 0 {
		t.Errorf("nil chats unread = %d, want 0", got)
	}
}
