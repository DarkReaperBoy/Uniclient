package gui

import (
	"testing"

	"uniclient/engine"
)

// Global search pure helpers (gui/search.go, slice 16).

func TestBuildSearchRows(t *testing.T) {
	visible := []engine.ChatInfo{{ChatID: "c1", Title: "Local"}}
	msgs := []engine.SearchResult{
		{MsgID: "m1", ChatTitle: "Alpha", Text: "hello"},
		{MsgID: "m2", ChatTitle: "Beta", Text: "hello world"},
	}
	global := []engine.ChatInfo{{ChatID: "g1", Title: "Public"}, {ChatID: "g2", Title: "Room"}}

	t.Run("full model", func(t *testing.T) {
		rows := buildSearchRows(visible, msgs, global, "")
		if len(rows) != 8 { // 3 headers + 1 chat + 2 msgs + 2 globals
			t.Fatalf("rows = %d, want 8", len(rows))
		}
		if rows[0].kind != sbRowHeader || rows[0].title != "Chats" {
			t.Fatalf("first = %+v", rows[0])
		}
		if rows[1].kind != sbRowChat || rows[1].chatIdx != 0 {
			t.Fatalf("chat row = %+v", rows[1])
		}
		if rows[2].title != "Messages" || rows[3].kind != sbRowMsg || rows[3].listIdx != 0 {
			t.Fatalf("msg rows = %+v %+v", rows[2], rows[3])
		}
		if rows[5].title != "Global results" || rows[6].kind != sbRowGlobal || rows[7].listIdx != 1 {
			t.Fatalf("global rows = %+v", rows[5])
		}
	})

	t.Run("only local", func(t *testing.T) {
		rows := buildSearchRows(visible, nil, nil, "")
		if len(rows) != 2 {
			t.Fatalf("rows = %d, want 2", len(rows))
		}
	})

	t.Run("empty search results", func(t *testing.T) {
		if rows := buildSearchRows(nil, nil, nil, ""); len(rows) != 0 {
			t.Fatalf("rows = %d, want 0", len(rows))
		}
	})
}

func TestSearchGlobalScope(t *testing.T) {
	global := []engine.ChatInfo{
		{AccountID: "a1", ChatID: "g1"},
		{AccountID: "a2", ChatID: "g2"},
	}
	if got := searchGlobalScope(global, ""); len(got) != 2 {
		t.Fatalf("unified scope = %d, want 2", len(got))
	}
	if got := searchGlobalScope(global, "a1"); len(got) != 1 || got[0].ChatID != "g1" {
		t.Fatalf("scoped = %+v", got)
	}
	if got := searchGlobalScope(global, "zz"); len(got) != 0 {
		t.Fatalf("unknown scope = %+v", got)
	}
}

func TestOnSearchChangedShortQueryClears(t *testing.T) {
	a := &App{}
	a.searchMsgs = []engine.SearchResult{{MsgID: "m1"}}
	a.searchGlobal = []engine.ChatInfo{{ChatID: "g1"}}
	a.onSearchChanged("x") // below the 2-rune threshold — synchronous clear
	if a.searchMsgs != nil || a.searchGlobal != nil {
		t.Fatalf("short query should clear results, got msgs=%v global=%v", a.searchMsgs, a.searchGlobal)
	}
}
