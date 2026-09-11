package engine

import (
	"testing"
	"time"

	"uniclient/cores"
)

// seedChat inserts a minimal chat row for mute tests.
func seedChatRow(t *testing.T, e *Engine, chatID string) {
	t.Helper()
	_, err := e.db.Exec(
		`INSERT INTO chats (account_id, chat_id, type, title, last_msg_time, updated_at)
                 VALUES ('a1', ?, 1, 'Chat', ?, ?)`, chatID, time.Now().UnixMilli(), time.Now().UnixMilli())
	if err != nil {
		t.Fatal(err)
	}
}

func getChatRow(t *testing.T, e *Engine, chatID string) ChatInfo {
	t.Helper()
	chats, err := e.GetUnifiedChatList(100, 0)
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range chats {
		if c.ChatID == chatID {
			return c
		}
	}
	t.Fatalf("chat %s not found", chatID)
	return ChatInfo{}
}

// TestMuteChatTimedStoresUntil: a timed mute must persist mute_until ≈
// now + duration so the UI can show the remaining time.
func TestMuteChatTimedStoresUntil(t *testing.T) {
	e := newTestEngine(t)
	seedChatRow(t, e, "100")
	before := time.Now().Unix()

	if err := e.MuteChat("a1", "100", true, 3600); err != nil {
		t.Fatal(err)
	}
	c := getChatRow(t, e, "100")
	if !c.IsMuted {
		t.Fatal("chat should be muted")
	}
	if c.MuteUntil < before+3600-5 || c.MuteUntil > time.Now().Unix()+3600+5 {
		t.Fatalf("MuteUntil = %d, want ≈ now+3600", c.MuteUntil)
	}
}

// TestMuteChatForeverClearsUntil: muting forever must clear any expiry.
func TestMuteChatForeverClearsUntil(t *testing.T) {
	e := newTestEngine(t)
	seedChatRow(t, e, "100")
	if err := e.MuteChat("a1", "100", true, 3600); err != nil {
		t.Fatal(err)
	}
	if err := e.MuteChat("a1", "100", true, 0); err != nil {
		t.Fatal(err)
	}
	c := getChatRow(t, e, "100")
	if !c.IsMuted || c.MuteUntil != 0 {
		t.Fatalf("forever mute: muted=%v until=%d, want muted/0", c.IsMuted, c.MuteUntil)
	}
}

// TestMuteChatUnmuteClearsUntil: unmuting clears both flag and expiry.
func TestMuteChatUnmuteClearsUntil(t *testing.T) {
	e := newTestEngine(t)
	seedChatRow(t, e, "100")
	if err := e.MuteChat("a1", "100", true, 3600); err != nil {
		t.Fatal(err)
	}
	if err := e.MuteChat("a1", "100", false, 0); err != nil {
		t.Fatal(err)
	}
	c := getChatRow(t, e, "100")
	if c.IsMuted || c.MuteUntil != 0 {
		t.Fatalf("unmuted: muted=%v until=%d, want false/0", c.IsMuted, c.MuteUntil)
	}
}

// TestTimedMuteExpiresSweep: a timed mute whose deadline has passed must
// read back as unmuted (the server unmutes automatically at mute_until).
func TestTimedMuteExpiresSweep(t *testing.T) {
	e := newTestEngine(t)
	seedChatRow(t, e, "100")
	_, err := e.db.Exec(
		`UPDATE chats SET is_muted = 1, mute_until = ? WHERE account_id = 'a1' AND chat_id = '100'`,
		time.Now().Unix()-10)
	if err != nil {
		t.Fatal(err)
	}
	c := getChatRow(t, e, "100")
	if c.IsMuted || c.MuteUntil != 0 {
		t.Fatalf("expired mute: muted=%v until=%d, want false/0 (auto-unmuted)", c.IsMuted, c.MuteUntil)
	}
}

// TestTimedMuteNotExpired: an unexpired timed mute stays muted.
func TestTimedMuteNotExpired(t *testing.T) {
	e := newTestEngine(t)
	seedChatRow(t, e, "100")
	_, err := e.db.Exec(
		`UPDATE chats SET is_muted = 1, mute_until = ? WHERE account_id = 'a1' AND chat_id = '100'`,
		time.Now().Unix()+3600)
	if err != nil {
		t.Fatal(err)
	}
	c := getChatRow(t, e, "100")
	if !c.IsMuted || c.MuteUntil == 0 {
		t.Fatalf("active timed mute: muted=%v until=%d, want true/>0", c.IsMuted, c.MuteUntil)
	}
}

// TestNotifyPeerChatID: the notify-settings peer mapping (tg peer kinds →
// engine chat-id conventions).
func TestNotifyPeerChatID(t *testing.T) {
	cases := []struct {
		peerType string
		peerID   int64
		want     string
	}{
		{"user", 12345, "12345"},
		{"group", 678, "-678"},
		{"channel", 999, "-1000000000999"},
		{"default_private", 0, ""},
		{"default_group", 0, ""},
		{"", 5, ""},
	}
	for _, c := range cases {
		if got := notifyPeerChatID(c.peerType, c.peerID); got != c.want {
			t.Errorf("notifyPeerChatID(%q,%d) = %q, want %q", c.peerType, c.peerID, got, c.want)
		}
	}
}

// TestHandleNotifySettingsTimedMute: a server-pushed notify-settings
// update (cross-device sync) must update the cache, including the expiry.
func TestHandleNotifySettingsTimedMute(t *testing.T) {
	e := newTestEngine(t)
	seedChatRow(t, e, "12345")
	seedChatRow(t, e, "-678")

	until := int32(time.Now().Unix() + 7200)
	e.handleUpdate("a1", notifySettingsUpdateForTest("user", 12345, true, until))
	c := getChatRow(t, e, "12345")
	if !c.IsMuted {
		t.Fatal("user chat should be muted after notify-settings update")
	}
	if c.MuteUntil != int64(until) {
		t.Fatalf("MuteUntil = %d, want %d", c.MuteUntil, until)
	}

	// Unmute push clears it.
	e.handleUpdate("a1", notifySettingsUpdateForTest("user", 12345, false, 0))
	c = getChatRow(t, e, "12345")
	if c.IsMuted || c.MuteUntil != 0 {
		t.Fatalf("unmute push: muted=%v until=%d, want false/0", c.IsMuted, c.MuteUntil)
	}

	// Group peer maps to the negative chat-id convention.
	e.handleUpdate("a1", notifySettingsUpdateForTest("group", 678, true, until))
	c = getChatRow(t, e, "-678")
	if !c.IsMuted {
		t.Fatal("group chat should be muted after notify-settings update")
	}

	// Default-scope pushes (no chat row) must not crash or touch rows.
	e.handleUpdate("a1", notifySettingsUpdateForTest("default_group", 0, true, until))
}

// notifySettingsUpdateForTest builds a cores.Update for the notify-settings
// path (test seam around the dispatcher payload).
func notifySettingsUpdateForTest(peerType string, peerID int64, muted bool, until int32) cores.Update {
	return cores.Update{
		Type: cores.UpdateNotifySettings,
		NotifySettings: &cores.NotifySettingsUpdate{
			PeerType:  peerType,
			PeerID:    peerID,
			Muted:     muted,
			MuteUntil: until,
		},
	}
}
