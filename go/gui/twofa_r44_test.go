package gui

// R44/R45 pins (chunk 3 iteration 28, the R34 sibling sweep #7 — twofa.go
// read in full):
//
//   - R44: twofaDlgState was R34's pre-fix shape — FOUR background tails
//     (openTwoFADialog's load, twofaFinish's mutation+refresh,
//     twofaFinishSendEmail's submit, the cancel-email tail) and every
//     GUI-loop writer (Back, action rows, form validations, emailSent)
//     mutated the frame-carried struct in place; the pointer-identity
//     guards (cur == d) did not stop the frameMu-side reads. Now every
//     writer goes through updateTwoFADlg (copy-on-write, R34/R40 shape)
//     with accountID staleness guards (identity guards break under
//     copy-on-write — every install swaps the pointer).
//   - R45: the settings-row map (twofaStates) was never refreshed after a
//     mutation — the row behind the dialog kept the pre-mutation On/Off
//     until settings was reopened, while twofaFinish's own comment
//     promised "server truth wins". The refresh now installs a FRESH map
//     (the R38 fresh-map rule — the frame carries the map).

import (
	"errors"
	"sync"
	"testing"
	"time"

	"uniclient/cores"
	"uniclient/engine"
)

// TestTwoFADlgStateIsCopyOnWrite pins R44's core: the mutation tails must
// swap the head, never mutate the frame-visible struct in place. A reader
// holds the ORIGINAL head pointer (what a captured frame holds) while
// three writers hammer twofaFinish/twofaFinishSendEmail through the real
// entry points — under the pre-fix in-place writes this is a -race report
// on busy/errMsg/step/state; under the fix the frozen head is never
// touched.
func TestTwoFADlgStateIsCopyOnWrite(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	a.mu.Lock()
	a.twofaDlg = &twofaDlgState{accountID: "acc", step: twofaStepNew}
	a.mu.Unlock()
	head := a.twofaDlg // the frame-captured pointer

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
			_ = head.step
			_ = head.loading
			_ = head.busy
			_ = head.errMsg
			_ = head.state
			_ = head.emailSent
		}
	}()
	for i := 0; i < 3; i++ { // the background writers
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < 150; j++ {
				a.twofaFinish(head, "Password updated", func() error { return nil })
				a.twofaFinish(head, "Password updated", func() error { return errors.New("boom") })
				a.twofaFinishSendEmail(head, "cur", "a@b.co")
			}
		}()
	}
	go func() {
		time.Sleep(80 * time.Millisecond)
		close(stop)
	}()
	wg.Wait()
	// Let every spawned tail land before the frozen-head assertion.
	deadline := time.Now().Add(5 * time.Second)
	for {
		a.mu.Lock()
		cur := a.twofaDlg
		a.mu.Unlock()
		if cur != nil && !cur.busy {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the mutation tails never landed")
		}
		time.Sleep(2 * time.Millisecond)
	}
	if head.busy || head.errMsg != "" || head.step != twofaStepNew || head.state != nil || head.emailSent != "" || head.loading {
		t.Fatal("the frame-captured head was mutated in place — the R34/R44 write-races-layout class")
	}
}

// TestUpdateTwoFADlgContract pins the installer semantics: nil head is a
// no-op (fn never runs), a false return leaves the head alone (same
// pointer), a true return installs a FRESH struct, and the accountID guard
// aborts a foreign dialog's update. (Compile seam: updateTwoFADlg does not
// exist pre-fix.)
func TestUpdateTwoFADlgContract(t *testing.T) {
	a := &App{}
	ran := false
	a.updateTwoFADlg(func(cur *twofaDlgState) bool { ran = true; return true })
	if ran {
		t.Fatal("a nil head must be a no-op — fn must never run")
	}

	head := &twofaDlgState{accountID: "acc", busy: true, step: twofaStepNew}
	a.mu.Lock()
	a.twofaDlg = head
	a.mu.Unlock()
	a.updateTwoFADlg(func(cur *twofaDlgState) bool { return false })
	a.mu.Lock()
	got := a.twofaDlg
	a.mu.Unlock()
	if got != head {
		t.Fatal("an aborted update must leave the head pointer untouched")
	}

	// A foreign account's update must not touch the open dialog.
	a.updateTwoFADlg(func(cur *twofaDlgState) bool {
		if cur.accountID != "other" {
			return false
		}
		return true
	})
	a.mu.Lock()
	got = a.twofaDlg
	a.mu.Unlock()
	if got != head {
		t.Fatal("a foreign-account update must abort")
	}

	a.updateTwoFADlg(func(cur *twofaDlgState) bool {
		if cur.accountID != "acc" {
			return false
		}
		cur.busy = false
		cur.step = twofaStepMain
		return true
	})
	a.mu.Lock()
	next := a.twofaDlg
	a.mu.Unlock()
	if next == nil || next == head {
		t.Fatal("an accepted update must install a fresh struct")
	}
	if next.busy || next.step != twofaStepMain {
		t.Fatal("the installed copy must carry fn's changes")
	}
	if !head.busy || head.step != twofaStepNew {
		t.Fatal("the replaced head must stay frozen (frame safety)")
	}
}

// TestTwoFALoadTailLandsCopyOnWrite pins openTwoFADialog's load: the open
// installs the editor, the tail (GetCloudPasswordState errors immediately
// on the bare engine harness) lands through the installer with loading
// cleared and the error shown, and the OPEN-TIME struct stays frozen.
func TestTwoFALoadTailLandsCopyOnWrite(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	a.openTwoFADialog("ghost")
	a.mu.Lock()
	opened := a.twofaDlg
	a.mu.Unlock()
	if opened == nil || opened.accountID != "ghost" || !opened.loading {
		t.Fatal("open must install a loading editor for the account")
	}
	deadline := time.Now().Add(5 * time.Second)
	for {
		a.mu.Lock()
		cur := a.twofaDlg
		a.mu.Unlock()
		if cur != nil && !cur.loading && cur.errMsg != "" {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the load tail never landed")
		}
		time.Sleep(2 * time.Millisecond)
	}
	if !opened.loading || opened.errMsg != "" || opened.state != nil {
		t.Fatal("the open-time head must stay frozen while the tail lands")
	}
}

// TestTwoFAFinishTailLandsCopyOnWrite pins twofaFinish's two halves: the
// head installs a FRESH busy struct (synchronously, on the GUI loop) and
// the tail lands busy=false + step=main + errMsg cleared on success —
// every install through the installer, the original head frozen.
func TestTwoFAFinishTailLandsCopyOnWrite(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	d := &twofaDlgState{accountID: "acc", step: twofaStepNew, errMsg: "old"}
	a.mu.Lock()
	a.twofaDlg = d
	a.mu.Unlock()
	a.twofaFinish(d, "Password updated", func() error { return nil })

	a.mu.Lock()
	cur := a.twofaDlg
	a.mu.Unlock()
	if cur == nil || cur == d {
		t.Fatal("twofaFinish must install a fresh busy struct")
	}
	if !cur.busy {
		t.Fatal("the fresh state must be busy")
	}
	deadline := time.Now().Add(5 * time.Second)
	for {
		a.mu.Lock()
		c := a.twofaDlg
		a.mu.Unlock()
		if c != nil && !c.busy && c.step == twofaStepMain && c.errMsg == "" {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the finish tail never landed")
		}
		time.Sleep(2 * time.Millisecond)
	}
	if d.busy || d.step != twofaStepNew || d.errMsg != "old" {
		t.Fatal("the frozen head must never be mutated")
	}
}

// TestTwoFARowMapRefreshIsCopyOnWrite pins R45: refreshTwoFARowState
// replaces the settings-row map with a FRESH map (the R38 fresh-map rule —
// frames hold the old map), preserves unrelated accounts, and leaves a
// nil map (privacy not loaded yet) alone.
func TestTwoFARowMapRefreshIsCopyOnWrite(t *testing.T) {
	a := &App{}
	old := map[string]cores.CloudPasswordState{
		"acc":   {HasPassword: false},
		"other": {HasPassword: true},
	}
	a.mu.Lock()
	a.twofaStates = old
	a.mu.Unlock()
	a.refreshTwoFARowState("acc", cores.CloudPasswordState{HasPassword: true})
	a.mu.Lock()
	got := a.twofaStates
	a.mu.Unlock()
	if got == nil {
		t.Fatal("the row map must be replaced with a fresh map")
	}
	if !got["acc"].HasPassword {
		t.Fatal("the refreshed account must carry the server truth")
	}
	if !got["other"].HasPassword {
		t.Fatal("unrelated accounts must survive the copy")
	}
	if old["acc"].HasPassword {
		t.Fatal("the previous map must stay frozen for frames holding it")
	}

	a.mu.Lock()
	a.twofaStates = nil
	a.mu.Unlock()
	a.refreshTwoFARowState("acc", cores.CloudPasswordState{HasPassword: true})
	a.mu.Lock()
	if a.twofaStates != nil {
		t.Fatal("a nil row map must stay nil (privacy not loaded yet)")
	}
	a.mu.Unlock()
}
