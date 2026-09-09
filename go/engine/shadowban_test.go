package engine

// Shadow ban (AyuGram matrix row 240, slice 91): per-chat local ignore —
// CRUD, GetMessages exclusion (SQL) + live-page exclusion (Go), and the
// per-chat scoping (a ban in one chat does not leak to another).

import (
	"testing"
)

func seedSenderMessage(t *testing.T, e *Engine, msgID, senderID, senderName string, ts int64) {
	_, err := e.db.Exec(
		`INSERT INTO messages (account_id, chat_id, msg_id, sender_id, sender_name, content_text, timestamp)
                 VALUES ('a1', 'c1', ?, ?, ?, ?, ?)`, msgID, senderID, senderName, msgID, ts)
	if err != nil {
		t.Fatal(err)
	}
}

func TestShadowBanCRUD(t *testing.T) {
	e := newTestEngine(t)

	if got := e.ListShadowBans("a1", "c1"); len(got) != 0 {
		t.Fatalf("fresh engine has %d bans, want 0", len(got))
	}
	if e.IsShadowBanned("a1", "c1", "u1") {
		t.Fatal("fresh engine must report no ban")
	}

	if err := e.ShadowBanSender("a1", "c1", "u1", "Alice", true); err != nil {
		t.Fatal(err)
	}
	if !e.IsShadowBanned("a1", "c1", "u1") {
		t.Fatal("ban not registered")
	}
	if e.IsShadowBanned("a1", "c1", "u2") {
		t.Fatal("other sender must not be banned")
	}

	bans := e.ListShadowBans("a1", "c1")
	if len(bans) != 1 || bans[0].SenderID != "u1" || bans[0].SenderName != "Alice" {
		t.Fatalf("bans = %+v, want one u1/Alice", bans)
	}

	// Replace keeps the name current.
	if err := e.ShadowBanSender("a1", "c1", "u1", "Alice in Chains", true); err != nil {
		t.Fatal(err)
	}
	if bans = e.ListShadowBans("a1", "c1"); len(bans) != 1 || bans[0].SenderName != "Alice in Chains" {
		t.Fatalf("replace = %+v", bans)
	}
	if got := e.CountShadowBans("a1"); got != 1 {
		t.Fatalf("account count = %d, want 1", got)
	}

	if err := e.ShadowBanSender("a1", "c1", "u1", "", false); err != nil {
		t.Fatal(err)
	}
	if e.IsShadowBanned("a1", "c1", "u1") {
		t.Fatal("unban did not clear the ban")
	}
	if got := e.ListShadowBans("a1", "c1"); len(got) != 0 {
		t.Fatalf("after unban = %+v, want empty", got)
	}

	// Empty sender / missing scope rejected.
	if err := e.ShadowBanSender("a1", "c1", "", "x", true); err == nil {
		t.Error("empty sender accepted")
	}
	if err := e.ShadowBanSender("", "c1", "u1", "x", true); err == nil {
		t.Error("missing account accepted (shadow ban is per-chat)")
	}
}

func TestShadowBanFiltersGetMessages(t *testing.T) {
	e := newTestEngine(t)
	seedSenderMessage(t, e, "m1", "u1", "Alice", 1000)
	seedSenderMessage(t, e, "m2", "u2", "Bob", 2000)
	seedSenderMessage(t, e, "m3", "u1", "Alice", 3000)

	msgs, err := e.GetMessages("a1", "c1", 0, 0, 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(msgs) != 3 {
		t.Fatalf("seeded = %d, want 3", len(msgs))
	}

	if err := e.ShadowBanSender("a1", "c1", "u1", "Alice", true); err != nil {
		t.Fatal(err)
	}
	msgs, err = e.GetMessages("a1", "c1", 0, 0, 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(msgs) != 1 || msgs[0].MsgID != "m2" {
		t.Fatalf("after ban = %+v, want only m2", msgs)
	}

	// Windowed reads exclude too (both cursors).
	msgs, err = e.GetMessages("a1", "c1", 0, 2500, 50) // afterMs: > 2500
	if err != nil {
		t.Fatal(err)
	}
	if len(msgs) != 0 {
		t.Fatalf("afterMs window: banned m3 still returned (%d rows)", len(msgs))
	}
	msgs, err = e.GetMessages("a1", "c1", 1500, 0, 50) // beforeMs: < 1500
	if err != nil {
		t.Fatal(err)
	}
	if len(msgs) != 0 {
		t.Fatalf("beforeMs window: banned m1 still returned (%d rows)", len(msgs))
	}

	// Unban restores everything.
	if err := e.ShadowBanSender("a1", "c1", "u1", "Alice", false); err != nil {
		t.Fatal(err)
	}
	msgs, _ = e.GetMessages("a1", "c1", 0, 0, 50)
	if len(msgs) != 3 {
		t.Fatalf("after unban = %d, want 3", len(msgs))
	}
}

func TestShadowBanIsPerChat(t *testing.T) {
	e := newTestEngine(t)
	// Same sender in two chats.
	_, err := e.db.Exec(
		`INSERT INTO messages (account_id, chat_id, msg_id, sender_id, content_text, timestamp)
                 VALUES ('a1', 'c1', 'm1', 'u1', 'x', 1000),
                        ('a1', 'c2', 'm2', 'u1', 'x', 2000)`)
	if err != nil {
		t.Fatal(err)
	}
	if err := e.ShadowBanSender("a1", "c1", "u1", "Alice", true); err != nil {
		t.Fatal(err)
	}

	msgs, _ := e.GetMessages("a1", "c1", 0, 0, 50)
	if len(msgs) != 0 {
		t.Fatalf("banned chat still shows %d rows", len(msgs))
	}
	msgs, _ = e.GetMessages("a1", "c2", 0, 0, 50)
	if len(msgs) != 1 {
		t.Fatalf("other chat = %d rows, want 1 (per-chat scoping)", len(msgs))
	}
}

func TestDropShadowBannedPure(t *testing.T) {
	e := newTestEngine(t)
	if err := e.ShadowBanSender("a1", "c1", "u1", "A", true); err != nil {
		t.Fatal(err)
	}
	page := []CachedMessage{
		{MsgID: "m1", SenderID: "u1"},
		{MsgID: "m2", SenderID: "u2"},
		{MsgID: "m3"}, // no sender (own/service) — survives
	}
	out := e.dropShadowBanned("a1", "c1", page)
	if len(out) != 2 || out[0].MsgID != "m2" || out[1].MsgID != "m3" {
		t.Fatalf("dropShadowBanned = %+v, want m2+m3", out)
	}
	// Empty ban set = passthrough (different chat).
	out = e.dropShadowBanned("a1", "c9", page)
	if len(out) != 3 {
		t.Fatalf("no bans = %d rows, want passthrough 3", len(out))
	}
}
