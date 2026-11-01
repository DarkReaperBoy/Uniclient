package gui

import (
	"errors"
	"testing"
	"time"

	"uniclient/engine"
)

func seedCallsBoxSession(a *App, accountID string, gen int) {
	a.mu.Lock()
	a.callsBoxOpen = true
	a.callsBoxFor = accountID
	a.callsBoxGen = gen
	a.mu.Unlock()
}

func r49Row(id, peer string, ts int64) callBoxRow {
	return callBoxRow{
		PeerID:   peer,
		PeerName: "User " + peer,
		Dir:      callDirIn,
		Last:     engine.CallHistoryEntry{MsgID: id, PeerID: peer, Timestamp: ts},
		MsgIDs:   []string{id},
		Count:    1,
	}
}

func TestCallsBoxPageMergeBuildsFreshSlice(t *testing.T) {
	a := &App{}
	seedCallsBoxSession(a, "acc1", 1)
	day := time.Date(2026, 9, 10, 15, 0, 0, 0, time.Local)
	full := make([]callBoxRow, 3, 5)
	full[0] = r49Row("30", "7", day.Unix())
	full[1] = r49Row("20", "8", day.Unix())
	full[2] = r49Row("10", "9", day.Unix())
	a.mu.Lock()
	a.callsBoxRows = full
	frozen := a.callsBoxRows
	a.mu.Unlock()
	oldPtr := &frozen[0]
	frozenCopy := append([]callBoxRow(nil), frozen...)

	a.applyCallsBoxPage("acc1", 1, 30, 100, []engine.CallHistoryEntry{
		mkCall("25", "8", day.Add(-time.Hour).Unix(), false, false, false),
	}, nil)

	a.mu.Lock()
	got := a.callsBoxRows
	a.mu.Unlock()
	if len(got) != 4 {
		t.Fatalf("rows = %d, want 4 (3 seeded + 1 fetched)", len(got))
	}
	if &got[0] == oldPtr {
		t.Fatalf("merge reused the shared backing array — R49 requires a fresh slice")
	}
	want := []string{"30", "25", "20", "10"}
	for i, w := range want {
		if got[i].Last.MsgID != w {
			t.Fatalf("row %d = %s, want %s (newest first)", i, got[i].Last.MsgID, w)
		}
	}
	for i := range frozenCopy {
		if frozen[i].Last.MsgID != frozenCopy[i].Last.MsgID {
			t.Fatalf("frozen row %d permuted (%s != %s) — the old array must stay intact",
				i, frozen[i].Last.MsgID, frozenCopy[i].Last.MsgID)
		}
	}
}

func TestCallsBoxLoadTailSessionGuarded(t *testing.T) {
	page := []engine.CallHistoryEntry{
		mkCall("5", "7", time.Now().Add(-2*time.Hour).Unix(), false, false, false),
	}

	a := &App{}
	seedCallsBoxSession(a, "acc1", 2)
	a.mu.Lock()
	a.callsBoxRows = nil
	a.callsBoxBusy = true
	a.mu.Unlock()
	a.applyCallsBoxPage("acc1", 1, 10, 100, page, nil)
	a.mu.Lock()
	if a.callsBoxRows != nil {
		t.Fatalf("stale gen: cleared rows resurrected")
	}
	if !a.callsBoxBusy {
		t.Fatalf("stale gen: busy reset — the newer session owns it")
	}
	a.mu.Unlock()

	a2 := &App{}
	seedCallsBoxSession(a2, "acc2", 1)
	a2.mu.Lock()
	a2.callsBoxBusy = true
	a2.mu.Unlock()
	a2.applyCallsBoxPage("acc1", 1, 0, 20, page, nil)
	a2.mu.Lock()
	if a2.callsBoxRows != nil {
		t.Fatalf("foreign account: rows installed under the wrong account")
	}
	if !a2.callsBoxBusy {
		t.Fatalf("foreign account: busy reset")
	}
	a2.mu.Unlock()

	a3 := &App{}
	seedCallsBoxSession(a3, "acc1", 1)
	a3.mu.Lock()
	a3.callsBoxOpen = false
	a3.callsBoxBusy = true
	a3.mu.Unlock()
	a3.applyCallsBoxPage("acc1", 1, 0, 20, page, nil)
	a3.mu.Lock()
	if a3.callsBoxRows != nil || !a3.callsBoxBusy {
		t.Fatalf("closed box: tail applied (%d rows, busy=%v)", len(a3.callsBoxRows), a3.callsBoxBusy)
	}
	a3.mu.Unlock()

	a4 := &App{}
	seedCallsBoxSession(a4, "acc1", 2)
	a4.applyCallsBoxPage("acc1", 1, 0, 20, nil, errors.New("stale boom"))
	a4.mu.Lock()
	if a4.toast != "" {
		t.Fatalf("stale error toasted: %q", a4.toast)
	}
	a4.mu.Unlock()

	a5 := &App{}
	seedCallsBoxSession(a5, "acc1", 3)
	a5.mu.Lock()
	a5.callsBoxBusy = true
	a5.callsBoxLoad = true
	a5.mu.Unlock()
	a5.applyCallsBoxPage("acc1", 3, 0, 20, nil, errors.New("boom"))
	a5.mu.Lock()
	if a5.toast != "Calls: boom" {
		t.Fatalf("current-session error: toast = %q", a5.toast)
	}
	if a5.callsBoxBusy || a5.callsBoxLoad {
		t.Fatalf("current-session error: flags not recovered")
	}
	a5.mu.Unlock()

	a6 := &App{}
	seedCallsBoxSession(a6, "acc1", 3)
	a6.mu.Lock()
	a6.callsBoxBusy = true
	a6.callsBoxLoad = true
	a6.mu.Unlock()
	a6.applyCallsBoxPage("acc1", 3, 0, 20, page, nil)
	a6.mu.Lock()
	rows := a6.callsBoxRows
	busy, load, done := a6.callsBoxBusy, a6.callsBoxLoad, a6.callsBoxDone
	a6.mu.Unlock()
	if len(rows) != 1 || rows[0].Last.MsgID != "5" {
		t.Fatalf("current session: rows = %v, want the fetched page", rows)
	}
	if busy || load {
		t.Fatalf("current session: busy/load not cleared")
	}
	if !done {
		t.Fatalf("short page: done not set (1 < 20)")
	}
}

func TestCallsBoxPageMergeDedupeGuard(t *testing.T) {
	a := &App{}
	seedCallsBoxSession(a, "acc1", 1)
	now := time.Now()
	a.mu.Lock()
	a.callsBoxRows = []callBoxRow{r49Row("50", "7", now.Add(-time.Hour).Unix())}
	a.mu.Unlock()
	a.applyCallsBoxPage("acc1", 1, 50, 100, []engine.CallHistoryEntry{
		mkCall("60", "8", now.Add(-30*time.Minute).Unix(), false, false, false),
		mkCall("50", "7", now.Add(-time.Hour).Unix(), false, false, false),
		mkCall("40", "9", now.Add(-2*time.Hour).Unix(), false, false, false),
	}, nil)
	a.mu.Lock()
	defer a.mu.Unlock()
	if len(a.callsBoxRows) != 2 {
		t.Fatalf("rows = %d, want 2 (offset filter drops 60 and 50)", len(a.callsBoxRows))
	}
	if a.callsBoxRows[0].Last.MsgID != "50" || a.callsBoxRows[1].Last.MsgID != "40" {
		t.Fatalf("order = %s,%s, want 50,40 (newest first)",
			a.callsBoxRows[0].Last.MsgID, a.callsBoxRows[1].Last.MsgID)
	}
}

func TestCallsBoxSessionGenBumps(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	if a.callsBoxGen != 0 {
		t.Fatalf("fresh App gen = %d, want 0", a.callsBoxGen)
	}
	a.openCallsBox("acc1")
	if a.callsBoxGen != 1 {
		t.Fatalf("after open: gen = %d, want 1", a.callsBoxGen)
	}
	a.clearCallsBoxAll(false)
	if a.callsBoxGen != 2 {
		t.Fatalf("after clear: gen = %d, want 2", a.callsBoxGen)
	}
}

func TestCallsBoxClearFailedRecovers(t *testing.T) {
	a := &App{}
	seedCallsBoxSession(a, "acc1", 4)
	a.mu.Lock()
	a.callsBoxBusy = true
	a.callsBoxLoad = true
	a.mu.Unlock()
	a.callsBoxClearFailed("acc1", 4)
	a.mu.Lock()
	if a.callsBoxBusy || a.callsBoxLoad {
		t.Fatalf("matching session: flags not recovered (busy=%v load=%v)", a.callsBoxBusy, a.callsBoxLoad)
	}
	a.mu.Unlock()

	b := &App{}
	seedCallsBoxSession(b, "acc1", 5)
	b.mu.Lock()
	b.callsBoxBusy = true
	b.callsBoxLoad = true
	b.mu.Unlock()
	b.callsBoxClearFailed("acc1", 4)
	b.mu.Lock()
	if !b.callsBoxBusy || !b.callsBoxLoad {
		t.Fatalf("stale session: flags stomped (busy=%v load=%v)", b.callsBoxBusy, b.callsBoxLoad)
	}
	b.mu.Unlock()
}
