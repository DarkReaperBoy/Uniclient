package gui

// R42/R43 pins (chunk 3 iteration 27, the R34 sibling sweep #6 —
// exportdlg.go read in full):
//
//   - R42: exportDlgState was R34's pre-fix shape — the engine event
//     goroutine (onExportProgress/onExportError/onExportComplete) and
//     startExport's failure tail mutated running/progress/err/done IN
//     PLACE under a.mu while layoutExportDialog read the same fields
//     through the frame pointer under frameMu only. Now every writer
//     goes through updateExportDlg (copy-on-write, the R34/R40 shape)
//     with accountID staleness guards on the tails.
//   - R43: exportOptsSynced was never reset — the checkbox pool seeded
//     once per PROCESS, so the second open showed the previous session's
//     toggles while the fresh checked map held the defaults (Start would
//     export the map, not the display). Reset at open+close, R41's
//     profileEdSynced shape minus the atomic (no background writer here).

import (
	"sync"
	"testing"
	"time"

	"uniclient/engine"
)

// TestExportDlgStateIsCopyOnWrite pins R42's core: the engine-goroutine
// handlers must swap the head, never mutate the frame-visible struct in
// place. A reader holds the ORIGINAL head pointer (what a captured frame
// holds) while three writers hammer through the real handlers — under the
// pre-fix in-place writes this is a -race report on running/progress/err/
// done; under the fix the frozen head is never touched.
func TestExportDlgStateIsCopyOnWrite(t *testing.T) {
	a := &App{}
	a.mu.Lock()
	a.exportDlg = &exportDlgState{accountID: "acc", checked: map[string]bool{"personal_info": true}}
	a.mu.Unlock()
	head := a.exportDlg // the frame-captured pointer

	var wg sync.WaitGroup
	stop := make(chan struct{})
	wg.Add(1)
	go func() { // the GUI-loop reader stand-in: no a.mu, frameMu only
		defer wg.Done()
		for {
			select {
			case <-stop:
				return
			default:
			}
			_ = head.running
			_ = head.progress
			_ = head.err
			_ = head.done
			_ = head.checked["personal_info"]
		}
	}()
	for i := 0; i < 3; i++ { // the engine-goroutine writers
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < 300; j++ {
				a.onExportProgress(engine.ExportProgressEvent{StepIndex: j, TotalSteps: 4}, "acc")
				a.onExportError(engine.ExportErrorEvent{ErrorType: "disk_io"}, "acc")
				a.onExportComplete(engine.ExportCompleteEvent{TotalFiles: j}, "acc")
			}
		}()
	}
	// Let the writers finish, then release the reader.
	go func() {
		time.Sleep(50 * time.Millisecond)
		close(stop)
	}()
	wg.Wait()
	if head.running || head.progress != nil || head.err != nil || head.done != nil {
		t.Fatal("the frame-captured head was mutated in place — the R34/R42 write-races-layout class")
	}
}

// TestUpdateExportDlgContract pins the installer semantics: nil head is a
// no-op (fn never runs), a false return leaves the head alone (same
// pointer), a true return installs a FRESH struct and the replaced head
// stays frozen. (Compile seam: updateExportDlg does not exist pre-fix.)
func TestUpdateExportDlgContract(t *testing.T) {
	a := &App{}
	ran := false
	a.updateExportDlg(func(cur *exportDlgState) bool { ran = true; return true })
	if ran {
		t.Fatal("a nil head must be a no-op — fn must never run")
	}

	head := &exportDlgState{accountID: "acc", running: true}
	a.mu.Lock()
	a.exportDlg = head
	a.mu.Unlock()
	a.updateExportDlg(func(cur *exportDlgState) bool { return false })
	a.mu.Lock()
	got := a.exportDlg
	a.mu.Unlock()
	if got != head {
		t.Fatal("an aborted update must leave the head pointer untouched")
	}

	a.updateExportDlg(func(cur *exportDlgState) bool {
		if cur != nil && cur.accountID != "acc" {
			t.Fatal("fn must receive the current head's copy")
		}
		cur.running = false
		return true
	})
	a.mu.Lock()
	next := a.exportDlg
	a.mu.Unlock()
	if next == nil || next == head {
		t.Fatal("an accepted update must install a fresh struct")
	}
	if next.running {
		t.Fatal("the installed copy must carry fn's changes")
	}
	if !head.running {
		t.Fatal("the replaced head must stay frozen (frame safety)")
	}
}

// TestExportDlgForeignAccountGuarded pins the staleness discipline the
// rewrite must not lose: events for another account never touch the open
// dialog; the matching account's events land through the installer.
func TestExportDlgForeignAccountGuarded(t *testing.T) {
	a := &App{}
	a.mu.Lock()
	a.exportDlg = &exportDlgState{accountID: "accA"}
	a.mu.Unlock()
	a.onExportProgress(engine.ExportProgressEvent{Step: "x"}, "accB")
	a.onExportError(engine.ExportErrorEvent{ErrorType: "disk_io"}, "accB")
	a.onExportComplete(engine.ExportCompleteEvent{TotalFiles: 3}, "accB")
	a.mu.Lock()
	d := a.exportDlg
	a.mu.Unlock()
	if d.progress != nil || d.err != nil || d.done != nil || d.running {
		t.Fatal("foreign-account events must not touch the open dialog")
	}

	a.onExportProgress(engine.ExportProgressEvent{Step: "y"}, "accA")
	a.mu.Lock()
	d = a.exportDlg
	a.mu.Unlock()
	if d.progress == nil || d.progress.Step != "y" || !d.running {
		t.Fatal("the matching-account event must land")
	}
}

// TestStartExportReplacesStateAndTailLands pins startExport's two halves:
// the head installs a FRESH running struct (clearing the result fields)
// instead of mutating in place, and the failure tail — StartExport on the
// bare harness misses the account and errors immediately — lands through
// the installer, flipping running back to false without ever touching the
// frozen heads.
func TestStartExportReplacesStateAndTailLands(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	a.mu.Lock()
	a.exportDlg = &exportDlgState{
		accountID: "ghost",
		checked:   map[string]bool{"personal_info": true},
		err:       &engine.ExportErrorEvent{ErrorType: "stale"},
	}
	a.mu.Unlock()
	old := a.exportDlg
	exportSizeEd.SetText("512")
	a.startExport()

	a.mu.Lock()
	cur := a.exportDlg
	a.mu.Unlock()
	if cur == nil || cur == old {
		t.Fatal("startExport must install a fresh struct")
	}
	if !cur.running {
		t.Fatal("the fresh state must be running")
	}
	if cur.err != nil || cur.done != nil || cur.progress != nil {
		t.Fatal("start must clear the result fields")
	}
	if old.running || old.err == nil {
		t.Fatal("the replaced head must stay frozen")
	}

	deadline := time.Now().Add(5 * time.Second)
	for {
		a.mu.Lock()
		head, running := a.exportDlg, a.exportDlg.running
		a.mu.Unlock()
		if head == nil {
			t.Fatal("the dialog must stay open while the tail lands")
		}
		if !running {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the start-failure tail never landed")
		}
		time.Sleep(2 * time.Millisecond)
	}
	a.mu.Lock()
	head := a.exportDlg
	a.mu.Unlock()
	if head.err != nil {
		t.Fatal("the tail clears running only — the toast carries the message")
	}
	if old.running || old.err == nil {
		t.Fatal("the frozen head must never be mutated, tail included")
	}
}

// TestExportOptsSyncedResetsOnOpenClose pins R43: the checkbox-pool seed
// flag must reset on BOTH open and close, and every open installs a fresh
// checked map with the wizard defaults — the pool and the map can never
// desync across opens again.
func TestExportOptsSyncedResetsOnOpenClose(t *testing.T) {
	a := &App{}
	a.exportOptsSynced = true // a previous open already seeded the pool
	a.openExportDialog("acc")
	if a.exportOptsSynced {
		t.Fatal("open must reset the seed flag — the pool re-seeds from the fresh checked map")
	}
	a.mu.Lock()
	d := a.exportDlg
	a.mu.Unlock()
	if d == nil || d.accountID != "acc" {
		t.Fatal("open must install the wizard for the account")
	}
	if !d.checked["personal_info"] || !d.checked["media_video"] {
		t.Fatal("the fresh map must carry the default checks")
	}
	if d.checked["sessions"] || d.checked["media_sticker"] {
		t.Fatal("non-default options must start unchecked")
	}

	a.exportOptsSynced = true // the layout seeded the pool again
	a.closeExportDialog()
	if a.exportOptsSynced {
		t.Fatal("close must reset the seed flag too")
	}
	a.mu.Lock()
	closed := a.exportDlg == nil
	a.mu.Unlock()
	if !closed {
		t.Fatal("close must dismiss the wizard")
	}
}
