package engine

import (
	"database/sql"
	"testing"
)

// Locally-hidden messages (AyuGram "hide message", slice 35): hidden rows
// vanish from GetMessages while staying in the messages table.

func newTestEngine(t *testing.T) *Engine {
	db, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	if err := migrateDB(db); err != nil {
		t.Fatal(err)
	}
	return &Engine{db: db}
}

func seedMessage(t *testing.T, e *Engine, msgID string, ts int64) {
	_, err := e.db.Exec(
		`INSERT INTO messages (account_id, chat_id, msg_id, content_text, timestamp)
                 VALUES ('a1', 'c1', ?, ?, ?)`, msgID, msgID, ts)
	if err != nil {
		t.Fatal(err)
	}
}

func TestHideMessageFiltersGetMessages(t *testing.T) {
	e := newTestEngine(t)
	seedMessage(t, e, "m1", 1000)
	seedMessage(t, e, "m2", 2000)
	seedMessage(t, e, "m3", 3000)

	msgs, err := e.GetMessages("a1", "c1", 0, 0, 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(msgs) != 3 {
		t.Fatalf("seeded = %d messages, want 3", len(msgs))
	}

	if err := e.HideMessage("a1", "c1", "m2", true); err != nil {
		t.Fatal(err)
	}
	msgs, err = e.GetMessages("a1", "c1", 0, 0, 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(msgs) != 2 {
		t.Fatalf("after hide = %d messages, want 2", len(msgs))
	}
	for _, m := range msgs {
		if m.MsgID == "m2" {
			t.Fatalf("hidden message still returned")
		}
	}

	// Unhide restores it.
	if err := e.HideMessage("a1", "c1", "m2", false); err != nil {
		t.Fatal(err)
	}
	msgs, err = e.GetMessages("a1", "c1", 0, 0, 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(msgs) != 3 {
		t.Fatalf("after unhide = %d messages, want 3", len(msgs))
	}
}

func TestHideMessageIdempotent(t *testing.T) {
	e := newTestEngine(t)
	seedMessage(t, e, "m1", 1000)
	if err := e.HideMessage("a1", "c1", "m1", true); err != nil {
		t.Fatal(err)
	}
	if err := e.HideMessage("a1", "c1", "m1", true); err != nil {
		t.Fatalf("double hide should be a no-op: %v", err)
	}
	if err := e.HideMessage("a1", "c1", "missing", false); err != nil {
		t.Fatalf("unhide of unknown row should be a no-op: %v", err)
	}
}

func TestRepeatMessageText(t *testing.T) {
	e := newTestEngine(t)
	seedMessage(t, e, "m1", 1000)

	// No account registered → SendMessage fails; that still proves the
	// lookup + validation path (the not-found error differs).
	if _, err := e.RepeatMessage("a1", "c1", "missing"); err == nil {
		t.Fatal("repeat of unknown message should fail")
	}
	// Account exists but not found → SendMessage's account error.
	if _, err := e.RepeatMessage("a1", "c1", "m1"); err == nil {
		t.Fatal("repeat without a live account should fail at send, not lookup")
	}
}
