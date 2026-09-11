package gui

import (
	"testing"

	"uniclient/engine"
)

func searchFixtureRows() []sbRow {
	visible := []engine.ChatInfo{{ChatID: "c1"}, {ChatID: "c2"}}
	msgs := []engine.SearchResult{{MsgID: "m1"}, {MsgID: "m2"}}
	global := []engine.ChatInfo{{ChatID: "g1"}}
	return buildSearchRows(visible, msgs, nil, global, "")
}

// Search results tabs (slice 57): All keeps the unified sections, Chats
// keeps chat+global sections, the message tabs keep only message rows,
// and the invite row survives everywhere.
func TestFilterSearchRows(t *testing.T) {
	rows := searchFixtureRows()

	all := filterSearchRows(rows, searchTabAll)
	if len(all) != len(rows) {
		t.Fatalf("all = %d rows, want %d", len(all), len(rows))
	}

	chats := filterSearchRows(rows, searchTabChats)
	if len(chats) != 5 { // Chats header + 2 chats + Global header + 1 global
		t.Fatalf("chats tab = %d rows: %+v", len(chats), chats)
	}
	for _, r := range chats {
		if r.kind == sbRowMsg {
			t.Fatalf("message row leaked into chats tab: %+v", r)
		}
	}

	msgs := filterSearchRows(rows, searchTabMsgs)
	if len(msgs) != 3 { // Messages header + 2 hits
		t.Fatalf("messages tab = %d rows: %+v", len(msgs), msgs)
	}
	for _, r := range msgs {
		if r.kind != sbRowHeader && r.kind != sbRowMsg {
			t.Fatalf("non-message row leaked: %+v", r)
		}
	}

	links := filterSearchRows(rows, searchTabLinks)
	if len(links) != 3 {
		t.Fatalf("links tab = %d rows", len(links))
	}

	withInvite := append([]sbRow{{kind: sbRowInvite, title: "abc"}}, rows...)
	inv := filterSearchRows(withInvite, searchTabFiles)
	if len(inv) == 0 || inv[0].kind != sbRowInvite {
		t.Fatalf("invite row lost: %+v", inv)
	}
	if len(inv) != 4 { // invite + Messages header + 2 hits
		t.Fatalf("files tab w/ invite = %d rows", len(inv))
	}
}

func TestSearchTabKind(t *testing.T) {
	if got := searchTabKind(searchTabAll); got != "" {
		t.Errorf("all = %q", got)
	}
	if got := searchTabKind(searchTabMsgs); got != "" {
		t.Errorf("messages = %q", got)
	}
	if got := searchTabKind(searchTabLinks); got != engine.SearchFilterLinks {
		t.Errorf("links = %q", got)
	}
	if got := searchTabKind(searchTabFiles); got != engine.SearchFilterFiles {
		t.Errorf("files = %q", got)
	}
}
