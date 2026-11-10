package tests

import (
	"testing"

	. "uniclient/ui/app"
	"uniclient/ui/dialogs"
)

type searchGlobalPort struct {
	fakeChatPort
	perAccount map[string][]dialogs.Entry
	queries    []string
}

func (p *searchGlobalPort) SearchGlobalChats(accountID, query string) ([]dialogs.Entry, bool) {
	p.queries = append(p.queries, accountID+"/"+query)
	rows, ok := p.perAccount[accountID]
	return rows, ok
}

func globalFeedsModel(t *testing.T) (Model, *searchGlobalPort) {
	t.Helper()
	port := &searchGlobalPort{
		fakeChatPort: fakeChatPort{ok: true},
		perAccount: map[string][]dialogs.Entry{
			"xm_01":   {{Account: "xm_01", ChatID: "u1", Name: "Pal", ChatType: dialogs.ChatPlain}},
			"tele_02": {{Account: "tele_02", ChatID: "u2", Name: "Work", ChatType: dialogs.ChatPlain}},
		},
	}
	m := applyEngineEvent(t, bridgeModel(t, 1440, 900), accountListWire)
	return m.WithPort(port), port
}

func tickSearch(m Model, now int) (Model, Cmd) {
	return Update(m, DialogsTick{Now: now})
}

func firedSearchGlobal(cmd Cmd) (SearchGlobalLoaded, bool) {
	if cmd == nil {
		return SearchGlobalLoaded{}, false
	}
	msg, ok := cmd().(SearchGlobalLoaded)
	return msg, ok
}

func TestSearchGlobalDebounceFiresOnceAndResolves(t *testing.T) {
	m, port := globalFeedsModel(t)
	m, _ = Update(m, SearchTyped{Text: "al", Now: 1000})
	if !m.SearchGlobalPending() {
		t.Fatalf("typed at 1000: the debounce must be armed")
	}
	if !m.SearchGlobalLoading() {
		t.Fatalf("typed at 1000: loading must be true while unresolved")
	}
	m, cmd := tickSearch(m, 1899)
	if _, ok := firedSearchGlobal(cmd); ok {
		t.Fatalf("tick at 1899 fired the search, want the 900ms reference delay")
	}
	m, cmd = tickSearch(m, 1900)
	msg, ok := firedSearchGlobal(cmd)
	if !ok {
		t.Fatalf("tick at 1900 must fire the global search")
	}
	if msg.Query != "al" {
		t.Fatalf("cmd query = %q, want al", msg.Query)
	}
	if len(msg.Rows) != 2 || msg.Rows[0].Name != "Pal" || msg.Rows[1].Name != "Work" {
		t.Fatalf("cmd rows = %+v, want both accounts' rows in account order", msg.Rows)
	}
	m, _ = Update(m, msg)
	if m.GlobalSearch.Query != "al" || len(m.GlobalSearch.Rows) != 2 || !m.GlobalSearch.Resolved {
		t.Fatalf("loaded state wrong: %+v", m.GlobalSearch)
	}
	if m.SearchGlobalLoading() {
		t.Fatalf("resolved search must not stay loading")
	}
	m, cmd = tickSearch(m, 2500)
	if _, ok := firedSearchGlobal(cmd); ok {
		t.Fatalf("a resolved search must not re-fire")
	}
	if len(port.queries) != 2 || port.queries[0] != "xm_01/al" || port.queries[1] != "tele_02/al" {
		t.Fatalf("per-account queries = %v, want both accounts in order", port.queries)
	}
}

func TestSearchGlobalMentionsModeNeverFires(t *testing.T) {
	m, port := globalFeedsModel(t)
	m, _ = Update(m, SearchTyped{Text: "@", Now: 1000})
	m, cmd := tickSearch(m, 6000)
	if _, ok := firedSearchGlobal(cmd); ok {
		t.Fatalf("the '@' mentions mode must not fire a global search")
	}
	if m.SearchGlobalLoading() {
		t.Fatalf("the '@' mentions mode must not show the loading bar")
	}
	if len(port.queries) != 0 {
		t.Fatalf("the '@' mentions mode hit the port: %v", port.queries)
	}
}

func TestSearchGlobalStaleResultsDropped(t *testing.T) {
	m, _ := globalFeedsModel(t)
	m, _ = Update(m, SearchTyped{Text: "al", Now: 1000})
	m, cmd := tickSearch(m, 1900)
	msg, ok := firedSearchGlobal(cmd)
	if !ok {
		t.Fatal("the search must fire")
	}
	m, _ = Update(m, msg)
	if !m.GlobalSearch.Resolved {
		t.Fatalf("results for the live query must resolve")
	}
	m, _ = Update(m, SearchTyped{Text: "x", Now: 2000})
	m, _ = Update(m, msg)
	if m.GlobalSearch.Resolved || m.GlobalSearch.Query != "al" || len(m.GlobalSearch.Rows) != 2 {
		t.Fatalf("stale results must be dropped: %+v", m.GlobalSearch)
	}
	if !m.SearchGlobalLoading() {
		t.Fatalf("the changed query is unresolved and must keep loading")
	}
}

func TestSearchGlobalClearsWithText(t *testing.T) {
	m, _ := globalFeedsModel(t)
	m, _ = Update(m, SearchTyped{Text: "al", Now: 1000})
	m, cmd := tickSearch(m, 1900)
	msg, ok := firedSearchGlobal(cmd)
	if !ok {
		t.Fatal("the search must fire")
	}
	m, _ = Update(m, msg)
	m, _ = Update(m, SearchBackspace{Now: 2000})
	m, _ = Update(m, SearchBackspace{Now: 2000})
	if m.Search.Text != "" {
		t.Fatalf("text = %q, want empty", m.Search.Text)
	}
	if m.GlobalSearch.Query != "" || m.GlobalSearch.Rows != nil || m.GlobalSearch.Fired || m.GlobalSearch.Resolved {
		t.Fatalf("cleared search must reset the global state: %+v", m.GlobalSearch)
	}
	m, cmd = tickSearch(m, 6000)
	if _, ok := firedSearchGlobal(cmd); ok {
		t.Fatalf("no text, no search")
	}
}

func TestSearchGlobalRetypingRefires(t *testing.T) {
	m, _ := globalFeedsModel(t)
	m, _ = Update(m, SearchTyped{Text: "a", Now: 1000})
	m, cmd := tickSearch(m, 1900)
	msg, ok := firedSearchGlobal(cmd)
	if !ok {
		t.Fatal("first query must fire")
	}
	m, _ = Update(m, msg)
	m, _ = Update(m, SearchTyped{Text: "l", Now: 3000})
	if m.GlobalSearch.Fired {
		t.Fatalf("a new keystroke must re-arm the debounce")
	}
	m, cmd = tickSearch(m, 3899)
	if _, ok := firedSearchGlobal(cmd); ok {
		t.Fatalf("re-armed debounce must honor the full delay")
	}
	m, cmd = tickSearch(m, 3900)
	msg, ok = firedSearchGlobal(cmd)
	if !ok {
		t.Fatal("re-armed debounce must fire")
	}
	if msg.Query != "al" {
		t.Fatalf("refired query = %q, want al", msg.Query)
	}
}
