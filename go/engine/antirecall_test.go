package engine

import (
	"testing"

	"uniclient/utils"
)

// newAntiRecallEngine: in-memory DB + temp-dir vault (config bridge path
// needs both).
func newAntiRecallEngine(t *testing.T) *Engine {
	e := newTestEngine(t)
	dir := t.TempDir()
	v, err := utils.CreateVault(dir+"/vault.db", "test")
	if err != nil {
		t.Fatal(err)
	}
	cfg := utils.DefaultConfig()
	e.vault = v
	e.config = &cfg
	return e
}

// Anti-recall (AyuGram §52, slice 80): settings round-trip + persistence
// through the config bridge, and per-chat clearing of saved deleted
// messages.

func TestAntiRecallSettingsRoundTrip(t *testing.T) {
	e := newAntiRecallEngine(t)
	e.saveDeletedMessages, e.saveMessagesHistory, e.saveForBots = true, true, false

	d, h, b := e.GetAntiRecallSettings()
	if !d || !h || b {
		t.Fatalf("defaults = %v/%v/%v, want true/true/false", d, h, b)
	}

	off, on := false, true
	if err := e.UpdateConfigFromBridge(&ConfigChanges{AyuSaveDeleted: &off, AyuSaveForBots: &on}); err != nil {
		t.Fatal(err)
	}
	d, h, b = e.GetAntiRecallSettings()
	if d || !h || !b {
		t.Fatalf("after bridge = %v/%v/%v, want false/true/true", d, h, b)
	}
	// The change persisted into the config snapshot.
	if e.GetConfig().AyuSaveDeleted == nil || *e.GetConfig().AyuSaveDeleted {
		t.Error("config AyuSaveDeleted not persisted as false")
	}
	if e.GetConfig().AyuSaveForBots == nil || !*e.GetConfig().AyuSaveForBots {
		t.Error("config AyuSaveForBots not persisted as true")
	}
}

func TestClearDeletedMessages(t *testing.T) {
	e := newTestEngine(t)
	// Two deleted, one live in c1; one deleted in c2.
	for i, msg := range []struct {
		id, chat string
		deleted  bool
	}{
		{"m1", "c1", true},
		{"m2", "c1", true},
		{"m3", "c1", false},
		{"m4", "c2", true},
	} {
		_, err := e.db.Exec(
			`INSERT INTO messages (account_id, chat_id, msg_id, content_text, timestamp, is_deleted)
                         VALUES ('a1', ?, ?, ?, ?, ?)`,
			msg.chat, msg.id, msg.id, int64(1000+i), msg.deleted)
		if err != nil {
			t.Fatal(err)
		}
		if msg.deleted {
			if _, err := e.db.Exec(
				`INSERT INTO media (account_id, chat_id, msg_id, seq, media_type)
                                 VALUES ('a1', ?, ?, 0, 1)`, msg.chat, msg.id); err != nil {
				t.Fatal(err)
			}
		}
	}

	n, err := e.ClearDeletedMessages("a1", "c1")
	if err != nil {
		t.Fatal(err)
	}
	if n != 2 {
		t.Fatalf("cleared = %d, want 2", n)
	}

	msgs, err := e.GetMessages("a1", "c1", 0, 0, 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(msgs) != 1 || msgs[0].MsgID != "m3" {
		t.Fatalf("c1 after clear = %+v, want only m3", msgs)
	}
	// The other chat keeps its deleted copy.
	msgs, err = e.GetMessages("a1", "c2", 0, 0, 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(msgs) != 1 || msgs[0].MsgID != "m4" || !msgs[0].IsDeleted {
		t.Fatalf("c2 = %+v, want deleted m4", msgs)
	}
	// Media rows for c1's deleted messages went too.
	var mediaCount int
	if err := e.db.QueryRow(
		`SELECT COUNT(*) FROM media WHERE account_id = 'a1' AND chat_id = 'c1'`).Scan(&mediaCount); err != nil {
		t.Fatal(err)
	}
	if mediaCount != 0 {
		t.Fatalf("c1 media rows = %d, want 0", mediaCount)
	}

	// Idempotent: second clear reports zero.
	if n, err = e.ClearDeletedMessages("a1", "c1"); err != nil || n != 0 {
		t.Fatalf("second clear = %d/%v, want 0/nil", n, err)
	}
}
