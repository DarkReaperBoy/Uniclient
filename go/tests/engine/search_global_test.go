package tests

import (
	"errors"
	"testing"
	"time"

	"uniclient/cores"
	"uniclient/ui/appport"
	"uniclient/ui/dialogs"
)

type globalSearchStub struct {
	cores.StubCore
	dialogs []cores.Dialog
	err     error
	query   string
	limit   int
}

func (s *globalSearchStub) SearchGlobal(query string, opts cores.PaginationOpts) ([]cores.Dialog, error) {
	s.query, s.limit = query, opts.Limit
	if s.err != nil {
		return nil, s.err
	}
	return s.dialogs, nil
}

func TestSearchGlobalChatsCarriesUsername(t *testing.T) {
	e := newTestEngine(t)
	stub := &globalSearchStub{dialogs: []cores.Dialog{
		{ID: "u7", Title: "Alice", Type: cores.ChatTypeDM, Username: "alice"},
		{ID: "c9", Title: "Dev Crew", Type: cores.ChatTypeGroup, Username: "devcrew"},
	}}
	if err := e.AttachAccount("a1", "telegram", stub); err != nil {
		t.Fatal(err)
	}
	chats, err := e.SearchGlobalChats("a1", "al", 17)
	if err != nil {
		t.Fatal(err)
	}
	if len(chats) != 2 {
		t.Fatalf("global chats = %d, want 2", len(chats))
	}
	if stub.query != "al" || stub.limit != 17 {
		t.Fatalf("core query/limit = (%q, %d), want (al, 17)", stub.query, stub.limit)
	}
	for _, c := range chats {
		if c.AccountID != "a1" {
			t.Fatalf("chat %s account = %q, want a1", c.ChatID, c.AccountID)
		}
	}
	if chats[0].ChatID != "u7" || chats[0].Title != "Alice" || chats[0].Username != "alice" || chats[0].Type != 1 {
		t.Fatalf("dm row wrong: %+v", chats[0])
	}
	if chats[1].ChatID != "c9" || chats[1].Title != "Dev Crew" || chats[1].Username != "devcrew" || chats[1].Type != 2 {
		t.Fatalf("group row wrong: %+v", chats[1])
	}
}

func TestSearchGlobalChatsCoreErrorIsHonest(t *testing.T) {
	e := newTestEngine(t)
	msgTs := time.Date(2026, time.November, 30, 14, 2, 0, 0, time.Local).UnixMilli()
	if err := e.SyncChats("a1", []cores.Dialog{plainDialog("c1", "Dev Crew", "m1", "release notes", msgTs, 2)}); err != nil {
		t.Fatal(err)
	}
	stub := &globalSearchStub{err: errors.New("search down")}
	if err := e.AttachAccount("a2", "telegram", stub); err != nil {
		t.Fatal(err)
	}
	chats, err := e.SearchGlobalChats("a2", "crew", 20)
	if err == nil {
		t.Fatal("a failing core search must surface its error, not local rows")
	}
	if chats != nil {
		t.Fatalf("failed global search = %d rows, want none", len(chats))
	}
}

func TestSearchChatsScansFullRow(t *testing.T) {
	e := newTestEngine(t)
	msgTs := time.Date(2026, time.November, 30, 14, 2, 0, 0, time.Local).UnixMilli()
	if err := e.SyncChats("a1", []cores.Dialog{
		plainDialog("c1", "Dev Crew", "m1", "release notes", msgTs, 2),
		plainDialog("c2", "Other", "m2", "nope", msgTs, 0),
	}); err != nil {
		t.Fatal(err)
	}
	chats, err := e.SearchChats("crew", 20)
	if err != nil {
		t.Fatalf("the local chat search must scan, not error: %v", err)
	}
	if len(chats) != 1 {
		t.Fatalf("local search rows = %d, want 1 (Dev Crew)", len(chats))
	}
	if chats[0].ChatID != "c1" || chats[0].Title != "Dev Crew" || chats[0].UnreadCount != 2 {
		t.Fatalf("local search row wrong: %+v", chats[0])
	}
}

func TestSearchGlobalPortMapsRows(t *testing.T) {
	e := newTestEngine(t)
	stub := &globalSearchStub{dialogs: []cores.Dialog{
		{ID: "u7", Title: "Alice", Type: cores.ChatTypeDM, Username: "alice"},
		{ID: "u8", Title: "Bob", Type: cores.ChatTypeDM},
		{ID: "c9", Title: "Dev Crew", Type: cores.ChatTypeChannel, Username: "devcrew"},
	}}
	if err := e.AttachAccount("a1", "telegram", stub); err != nil {
		t.Fatal(err)
	}
	port := appport.For(e.Engine)
	rows, ok := port.SearchGlobalChats("a1", "al")
	if !ok {
		t.Fatal("port.SearchGlobalChats must succeed on the stub core")
	}
	if len(rows) != 3 {
		t.Fatalf("port rows = %d, want 3", len(rows))
	}
	alice := rows[0]
	if alice.Account != "a1" || alice.ChatID != "u7" || alice.Name != "Alice" {
		t.Fatalf("alice identity wrong: %+v", alice)
	}
	if alice.Username != "alice" || alice.ChatType != dialogs.ChatPlain {
		t.Fatalf("alice row wrong: %+v", alice)
	}
	if want := "@alice"; alice.Preview != want {
		t.Fatalf("alice preview = %q, want %q (the reference search-row text law)", alice.Preview, want)
	}
	bob := rows[1]
	if want := "ID: u8"; bob.Preview != want {
		t.Fatalf("bob preview = %q, want %q (username-less rows show the id)", bob.Preview, want)
	}
	crew := rows[2]
	if crew.ChatType != dialogs.ChatChannel || crew.Preview != "@devcrew" {
		t.Fatalf("crew row wrong: %+v", crew)
	}
}
