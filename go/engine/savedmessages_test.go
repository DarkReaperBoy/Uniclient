package engine

import (
	"testing"

	"uniclient/cores"
)

// selfStub: a core exposing SelfUserID (the Saved-Messages capability).
type selfStub struct {
	cores.StubCore
	selfID string
}

func (s selfStub) SelfUserID() string { return s.selfID }

func TestSavedMessagesSupported(t *testing.T) {
	e := newTestEngine(t)
	e.accounts = map[string]*Account{
		"tg":  {ID: "tg", Core: selfStub{selfID: "42"}},
		"irc": {ID: "irc", Core: plainStub{}},
	}
	if !e.SavedMessagesSupported("tg") {
		t.Error("self-capable core reported unsupported")
	}
	if e.SavedMessagesSupported("irc") {
		t.Error("plain core reported saved-messages support")
	}
	if e.SavedMessagesSupported("missing") {
		t.Error("missing account reported support")
	}
}

func TestSavedMessagesChatID(t *testing.T) {
	e := newTestEngine(t)
	e.accounts = map[string]*Account{
		"tg":  {ID: "tg", Core: selfStub{selfID: "42"}},
		"irc": {ID: "irc", Core: plainStub{}},
	}
	if got := e.SavedMessagesChatID("tg"); got != "42" {
		t.Errorf("chatID = %q, want 42", got)
	}
	if got := e.SavedMessagesChatID("irc"); got != "" {
		t.Errorf("plain core chatID = %q, want empty", got)
	}
	if got := e.SavedMessagesChatID("missing"); got != "" {
		t.Errorf("missing account chatID = %q, want empty", got)
	}
}

func TestOpenSavedMessagesIdempotent(t *testing.T) {
	e := newTestEngine(t)
	e.accounts = map[string]*Account{"tg": {ID: "tg", Core: selfStub{selfID: "42"}}}
	// The chats table references accounts(id); ConnectAccount inserts that
	// row in real flows — mirror it here.
	if _, err := e.db.Exec(
		`INSERT OR IGNORE INTO accounts (id, platform, display_name, sort_order, created_at)
                 VALUES ('tg', 'telegram', 'Test', 0, 0)`); err != nil {
		t.Fatal(err)
	}

	id1, err := e.OpenSavedMessages("tg")
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	id2, err := e.OpenSavedMessages("tg")
	if err != nil {
		t.Fatalf("second open: %v", err)
	}
	if id1 != id2 || id1 != "42" {
		t.Errorf("ids = (%q, %q), want (42, 42)", id1, id2)
	}

	var n int
	if err := e.db.QueryRow(
		`SELECT COUNT(*) FROM chats WHERE account_id = ? AND chat_id = ?`,
		"tg", "42").Scan(&n); err != nil {
		t.Fatal(err)
	}
	if n != 1 {
		t.Errorf("chat rows = %d, want 1", n)
	}
	var title string
	if err := e.db.QueryRow(
		`SELECT title FROM chats WHERE account_id = ? AND chat_id = ?`,
		"tg", "42").Scan(&title); err != nil {
		t.Fatal(err)
	}
	if title != "Saved Messages" {
		t.Errorf("title = %q", title)
	}
}
