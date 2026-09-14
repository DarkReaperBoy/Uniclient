package engine

import (
	"testing"
	"time"

	"uniclient/cores"
)

// timeOf builds a Timestamp for constructed core messages (cache stores
// UnixMilli).
func timeOf(sec int64) time.Time { return time.Unix(sec, 0).UTC() }

// Saved Messages sublists (slice 197): the engine surface — the
// saved_peer scoped message page, the cold-start server feed, and the
// capability probe. Stubs mirror the core interfaces (the LIST flows
// through the pre-existing SavedSublistsFetcher shape).

// savedDialogsStub: a core exposing the slice-197 surface.
type savedDialogsStub struct {
	cores.StubCore
	selfID  string
	dialogs []cores.SavedSublistInfo
	history map[string][]cores.Message // peerID → messages

	// slice-204 call logs (pointer fields — the account holds the core
	// by value, so the stub's method receivers record through them).
	reorderLog *[][]string
	delLog     *[]string
}

func (s savedDialogsStub) SelfUserID() string { return s.selfID }

func (s savedDialogsStub) GetSavedSublists(limit, offsetDate, offsetID int, excludePinned bool) ([]cores.SavedSublistInfo, int, error) {
	out := s.dialogs
	if limit > 0 && len(out) > limit {
		out = out[:limit]
	}
	return out, len(s.dialogs), nil
}

func (s savedDialogsStub) GetSavedHistory(peerID string, offsetID, limit int) ([]cores.Message, error) {
	msgs := s.history[peerID]
	if offsetID > 0 {
		// Emulate the server's offsetID paging: strictly older ids.
		var filtered []cores.Message
		for _, m := range msgs {
			if id := parseInt64(m.ID); id < int64(offsetID) {
				filtered = append(filtered, m)
			}
		}
		msgs = filtered
	}
	if limit > 0 && len(msgs) > limit {
		msgs = msgs[:limit]
	}
	return msgs, nil
}

func (s savedDialogsStub) ToggleSavedDialogPin(peerID string, pinned bool) error {
	return nil
}

func parseInt64(s string) int64 {
	var n int64
	for _, c := range s {
		if c < '0' || c > '9' {
			return -1
		}
		n = n*10 + int64(c-'0')
	}
	return n
}

func newSavedSublistEngine(t *testing.T) *Engine {
	t.Helper()
	e := newTestEngine(t)
	if _, err := e.db.Exec(
		`INSERT OR IGNORE INTO accounts (id, platform, display_name, sort_order, created_at)
                 VALUES ('tg', 'telegram', 'Test', 0, 0)`); err != nil {
		t.Fatal(err)
	}
	return e
}

func TestSavedSublistsSupported(t *testing.T) {
	e := newSavedSublistEngine(t)
	e.accounts = map[string]*Account{
		"tg":  {ID: "tg", Core: savedDialogsStub{selfID: "42"}},
		"irc": {ID: "irc", Core: plainStub{}},
	}
	if !e.SavedSublistsSupported("tg") {
		t.Error("saved-dialogs core reported unsupported")
	}
	if e.SavedSublistsSupported("irc") {
		t.Error("plain core reported sublists support")
	}
	if e.SavedSublistsSupported("missing") {
		t.Error("missing account reported support")
	}
}

func TestGetSavedSublistsPassthrough(t *testing.T) {
	e := newSavedSublistEngine(t)
	stub := savedDialogsStub{
		selfID: "42",
		dialogs: []cores.SavedSublistInfo{
			{PeerID: "-1000000001234", PeerName: "My Channel", IsPinned: true, TopMessage: 100},
			{PeerID: "42", PeerName: "My Notes", TopMessage: 7},
		},
	}
	e.accounts = map[string]*Account{"tg": {ID: "tg", Core: stub}}

	lists, total, err := e.GetSavedSublists("tg", 50, 0, 0, false)
	if err != nil {
		t.Fatalf("GetSavedSublists: %v", err)
	}
	if len(lists) != 2 || total != 2 {
		t.Fatalf("len/total = %d/%d, want 2/2", len(lists), total)
	}
	if lists[0].PeerID != "-1000000001234" || lists[0].PeerName != "My Channel" || !lists[0].IsPinned {
		t.Errorf("sublist[0] = %+v", lists[0])
	}
	if lists[1].PeerID != "42" || lists[1].IsPinned {
		t.Errorf("sublist[1] = %+v", lists[1])
	}
}

func TestGetSavedSublistsUnsupported(t *testing.T) {
	e := newSavedSublistEngine(t)
	e.accounts = map[string]*Account{"irc": {ID: "irc", Core: plainStub{}}}
	if _, _, err := e.GetSavedSublists("irc", 50, 0, 0, false); err == nil {
		t.Fatal("plain core must not support sublists")
	}
}

// TestGetSavedSublistMessages: the scoped page — the core fetch lands in
// the messages cache under the SAVED chat id with saved_peer recorded,
// and the saved_peer filter returns exactly that sublist's rows,
// newest-first, with beforeMs paging.
func TestGetSavedSublistMessages(t *testing.T) {
	e := newSavedSublistEngine(t)
	stub := savedDialogsStub{
		selfID: "42",
		dialogs: []cores.SavedSublistInfo{
			{PeerID: "-1000000001234", PeerName: "My Channel", TopMessage: 300},
		},
		history: map[string][]cores.Message{
			"-1000000001234": {
				{ID: "300", ChatID: "42", Text: "third", Timestamp: timeOf(3000), SavedPeerID: "-1000000001234"},
				{ID: "200", ChatID: "42", Text: "second", Timestamp: timeOf(2000), SavedPeerID: "-1000000001234"},
				{ID: "100", ChatID: "42", Text: "first", Timestamp: timeOf(1000), SavedPeerID: "-1000000001234"},
			},
			"42": {
				{ID: "50", ChatID: "42", Text: "own note", Timestamp: timeOf(500), SavedPeerID: "42"},
			},
		},
	}
	e.accounts = map[string]*Account{"tg": {ID: "tg", Core: stub}}

	msgs, err := e.GetSavedSublistMessages("tg", "42", "-1000000001234", 0, 50)
	if err != nil {
		t.Fatalf("GetSavedSublistMessages: %v", err)
	}
	if len(msgs) != 3 {
		t.Fatalf("len = %d, want 3 (only the sublist's rows)", len(msgs))
	}
	if msgs[0].MsgID != "300" || msgs[2].MsgID != "100" {
		t.Errorf("order = %v…%v, want newest-first 300→100", msgs[0].MsgID, msgs[2].MsgID)
	}
	if msgs[0].SavedPeerID != "-1000000001234" {
		t.Errorf("SavedPeerID = %q, want the sublist peer", msgs[0].SavedPeerID)
	}

	// The own-notes sublist feeds its own rows on ITS first open…
	own, err := e.GetSavedSublistMessages("tg", "42", "42", 0, 50)
	if err != nil {
		t.Fatalf("own sublist: %v", err)
	}
	if len(own) != 1 || own[0].MsgID != "50" {
		t.Fatalf("own sublist = %+v, want only msg 50", own)
	}
	// …and the plain saved-chat page (no sublist scope) then returns
	// everything cached (both sublists' rows).
	all, err := e.GetSavedSublistMessages("tg", "42", "", 0, 50)
	if err != nil {
		t.Fatalf("unscoped: %v", err)
	}
	if len(all) != 4 {
		t.Fatalf("unscoped len = %d, want 4 (all saved rows)", len(all))
	}

	// beforeMs paging: strictly older than the 2000-mark → one row.
	older, err := e.GetSavedSublistMessages("tg", "42", "-1000000001234", timeOf(2000).UnixMilli(), 50)
	if err != nil {
		t.Fatalf("paged: %v", err)
	}
	if len(older) != 1 || older[0].MsgID != "100" {
		t.Errorf("paged = %+v, want only msg 100", older)
	}
}

// TestSavedPeerColumnRoundTrip: messages cached through the normal chat
// path record saved_peer, so sublist views stay fed without a scoped
// fetch.
func TestSavedPeerColumnRoundTrip(t *testing.T) {
	e := newSavedSublistEngine(t)
	e.accounts = map[string]*Account{"tg": {ID: "tg", Core: plainStub{}}}
	e.cacheMessage("tg", "42", &cores.Message{ID: "9", ChatID: "42", Text: "saved note", Timestamp: timeOf(900), SavedPeerID: "77"})
	msgs, err := e.GetSavedSublistMessages("tg", "42", "77", 0, 10)
	if err != nil {
		t.Fatalf("scoped read: %v", err)
	}
	if len(msgs) != 1 || msgs[0].MsgID != "9" {
		t.Fatalf("round-trip = %+v, want msg 9 under sublist 77", msgs)
	}
}

// Slice 204: pin reorder + delete flow — the engine surface. The stub
// records the calls (through pointer fields — the account stores the
// core by value) so the tests pin the peer order / delete target the
// engine forwards; the delete must also purge the scoped cache rows.

func (s savedDialogsStub) ReorderPinnedSavedDialogs(peerIDs []string) error {
	if s.reorderLog != nil {
		*s.reorderLog = append(*s.reorderLog, append([]string(nil), peerIDs...))
	}
	return nil
}

func (s savedDialogsStub) DeleteSavedHistory(peerID string) error {
	if s.delLog != nil {
		*s.delLog = append(*s.delLog, peerID)
	}
	return nil
}

// TestSavedSublistReorder: the engine forwards the full pinned order to
// messages.reorderPinnedSavedDialogs; a core without the surface (or a
// missing account) is an honest error, not a silent pass.
func TestSavedSublistReorder(t *testing.T) {
	e := newSavedSublistEngine(t)
	var log [][]string
	stub := savedDialogsStub{selfID: "42"}
	e.accounts = map[string]*Account{"tg": {ID: "tg", Core: stub}}
	e.accounts["tg"].Core = savedDialogsStub{selfID: "42", reorderLog: &log}
	if err := e.ReorderSavedSublists("tg", []string{"a", "b", "c"}); err != nil {
		t.Fatalf("ReorderSavedSublists: %v", err)
	}
	if len(log) != 1 || len(log[0]) != 3 || log[0][0] != "a" || log[0][2] != "c" {
		t.Fatalf("reorder forwarded = %v", log)
	}
	e.accounts["irc"] = &Account{ID: "irc", Core: plainStub{}}
	if err := e.ReorderSavedSublists("irc", []string{"a"}); err == nil {
		t.Fatal("plain core must not support saved reorder")
	}
	if err := e.ReorderSavedSublists("missing", nil); err == nil {
		t.Fatal("missing account must error")
	}
}

// TestSavedSublistDeletePurgesCache: delete forwards the peer to the
// core AND wipes the scoped rows from the self-chat cache (other
// sublists' rows survive; the whole-chat rows for other peers stay).
func TestSavedSublistDeletePurgesCache(t *testing.T) {
	e := newSavedSublistEngine(t)
	var del []string
	e.accounts = map[string]*Account{"tg": {ID: "tg", Core: savedDialogsStub{selfID: "42", delLog: &del}}}
	self := e.SavedMessagesChatID("tg")
	if self == "" {
		t.Fatal("no saved chat id for the stub self account")
	}
	seed := func(peer string, ids ...string) {
		for _, id := range ids {
			m := cores.Message{ID: id, Text: "m " + id, Timestamp: timeOf(1700000000)}
			e.cacheMessage("tg", self, &m)
			e.db.Exec(`UPDATE messages SET saved_peer = ? WHERE account_id = ? AND chat_id = ? AND msg_id = ?`,
				peer, "tg", self, id)
		}
	}
	seed("100", "1", "2")
	seed("200", "3")
	if got := e.countSavedRows("tg", self, ""); got != 3 {
		t.Fatalf("seeded rows = %d, want 3", got)
	}
	if err := e.DeleteSavedSublistHistory("tg", "100"); err != nil {
		t.Fatalf("DeleteSavedSublistHistory: %v", err)
	}
	if len(del) != 1 || del[0] != "100" {
		t.Fatalf("core delete calls = %v", del)
	}
	if got := e.countSavedRows("tg", self, "100"); got != 0 {
		t.Fatalf("deleted sublist rows = %d, want 0", got)
	}
	if got := e.countSavedRows("tg", self, "200"); got != 1 {
		t.Fatalf("other sublist rows = %d, want 1", got)
	}
	if got := e.countSavedRows("tg", self, ""); got != 1 {
		t.Fatalf("whole-chat rows = %d, want 1 (only the surviving sublist)", got)
	}
}
