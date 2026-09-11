package gui

import (
	"testing"

	"uniclient/engine"
)

// TestTraySnapshotFrom: the pure snapshot builder fed from app state —
// per-account unread sums, total, ghost/streamer from the config.
func TestTraySnapshotFrom(t *testing.T) {
	accs := []engine.AccountInfo{
		{ID: "a1", Platform: "tg", Username: "alice"},
		{ID: "a2", Platform: "tg", Username: "bob"},
	}
	chats := []engine.ChatInfo{
		{AccountID: "a1", ChatID: "1", UnreadCount: 3},
		{AccountID: "a1", ChatID: "2", UnreadCount: 2, IsArchived: true},
		{AccountID: "a2", ChatID: "3", UnreadCount: 5},
		{AccountID: "a2", ChatID: "4", UnreadCount: 0},
	}
	cfg := cfgSnapshot{Streamer: true}
	cfg.SendReadReceipts = true
	cfg.SendUploadProgress = true
	cfg.SendReadStories = true
	cfg.SendOnlinePackets = true
	cfg.SendOfflineAfterOnline = true
	cfg.MarkReadAfterAction = true
	cfg.UseScheduledMessages = true
	cfg.SendWithoutSound = true

	snap := traySnapshotFrom(accs, chats, cfg)
	if snap.TotalUnread != 10 {
		t.Fatalf("TotalUnread = %d, want 10", snap.TotalUnread)
	}
	if !snap.Ghost || !snap.Streamer {
		t.Fatalf("ghost=%v streamer=%v, want true/true", snap.Ghost, snap.Streamer)
	}
	if len(snap.Accounts) != 2 {
		t.Fatalf("accounts = %d, want 2", len(snap.Accounts))
	}
	if snap.Accounts[0].Unread != 5 || snap.Accounts[1].Unread != 5 {
		t.Fatalf("per-account unread = %d/%d, want 5/5", snap.Accounts[0].Unread, snap.Accounts[1].Unread)
	}

	// Names: username with @, platform fallback.
	if snap.Accounts[0].Name != "@alice" {
		t.Fatalf("name[0] = %q, want @alice", snap.Accounts[0].Name)
	}

	// Ghost off when any flag is off.
	cfg.SendTyping = false // unrelated flag, still on
	cfg.SendWithoutSound = false
	snap = traySnapshotFrom(accs, chats, cfg)
	if snap.Ghost {
		t.Fatal("ghost should be off when a flag is off")
	}

	// Accounts without chats still list with zero unread.
	snap = traySnapshotFrom(accs[:1], nil, cfg)
	if len(snap.Accounts) != 1 || snap.Accounts[0].Unread != 0 {
		t.Fatalf("chatless account row = %+v", snap.Accounts)
	}
}

// TestTrayAccountLabel: the tray menu label for an account row.
func TestTrayAccountLabel(t *testing.T) {
	cases := []struct {
		name   string
		unread int
		want   string
	}{
		{"@alice", 0, "@alice"},
		{"@alice", 3, "@alice (3)"},
		{"@alice", 100, "@alice (99+)"},
	}
	for _, c := range cases {
		if got := trayAccountLabel(c.name, c.unread); got != c.want {
			t.Errorf("trayAccountLabel(%q,%d) = %q, want %q", c.name, c.unread, got, c.want)
		}
	}
}
