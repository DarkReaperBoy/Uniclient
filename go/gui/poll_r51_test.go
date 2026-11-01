package gui

import (
	"errors"
	"sync"
	"testing"

	"uniclient/engine"
)

func TestUpdatePollDlgContract(t *testing.T) {
	a := &App{}
	if a.updatePollDlg(func(d *pollDlgState) bool { d.busy = true; return true }) {
		t.Fatalf("nil head: installer reports an install")
	}
	a.mu.Lock()
	a.pollDlg = &pollDlgState{}
	a.pollDlgGen++
	a.mu.Unlock()
	a.mu.Lock()
	frozen := a.pollDlg
	a.mu.Unlock()

	if a.updatePollDlg(func(d *pollDlgState) bool { return false }) {
		t.Fatalf("abort: installer reports an install")
	}
	a.mu.Lock()
	same := a.pollDlg == frozen
	a.mu.Unlock()
	if !same {
		t.Fatalf("abort: head replaced anyway")
	}

	if !a.updatePollDlg(func(d *pollDlgState) bool { d.correct = 3; return true }) {
		t.Fatalf("install: installer reports no install")
	}
	a.mu.Lock()
	cur := a.pollDlg
	a.mu.Unlock()
	if cur == frozen {
		t.Fatalf("install: head not replaced — copy-on-write required (R51)")
	}
	if cur.correct != 3 || cur.busy {
		t.Fatalf("install: correct=%d busy=%v, want 3/false", cur.correct, cur.busy)
	}
	if frozen.correct != 0 || frozen.busy {
		t.Fatalf("frozen head mutated: correct=%d busy=%v", frozen.correct, frozen.busy)
	}
}

func TestPollDlgStateIsCopyOnWrite(t *testing.T) {
	a := &App{}
	a.openPollDialog()
	a.mu.Lock()
	frozen := a.pollDlg
	a.mu.Unlock()
	if frozen == nil {
		t.Fatalf("open: no head")
	}
	var wg sync.WaitGroup
	for w := 0; w < 3; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := 0; i < 300; i++ {
				a.updatePollDlg(func(d *pollDlgState) bool {
					d.busy = !d.busy
					d.correct = (d.correct + 1) % 7
					return true
				})
			}
		}()
	}
	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := 0; i < 100; i++ {
			a.openPollDialog()
			a.closePollDialog()
		}
		a.openPollDialog()
	}()
	wg.Wait()
	a.mu.Lock()
	defer a.mu.Unlock()
	if frozen.busy || frozen.correct != 0 {
		t.Fatalf("frozen head mutated: busy=%v correct=%d — copy-on-write required (R51)", frozen.busy, frozen.correct)
	}
}

func TestPollSendTailSessionGuarded(t *testing.T) {
	boom := errors.New("boom")

	a := &App{}
	a.openPollDialog()
	a.mu.Lock()
	gen1 := a.pollDlgGen
	a.mu.Unlock()
	if gen1 != 1 {
		t.Fatalf("first open: gen = %d, want 1", gen1)
	}

	a.updatePollDlg(func(d *pollDlgState) bool { d.busy = true; return true })
	a.pollSendDone(gen1, nil)
	a.mu.Lock()
	closed := a.pollDlg == nil
	a.mu.Unlock()
	if !closed {
		t.Fatalf("matching session + success: dialog not closed")
	}

	a2 := &App{}
	a2.openPollDialog()
	a2.updatePollDlg(func(d *pollDlgState) bool { d.busy = true; return true })
	a2.pollSendDone(1, boom)
	a2.mu.Lock()
	d2 := a2.pollDlg
	a2.mu.Unlock()
	if d2 == nil {
		t.Fatalf("matching session + failure: dialog closed — should stay for a retry")
	}
	if d2.busy {
		t.Fatalf("matching session + failure: busy not cleared")
	}
	if a2.toast != "Poll failed: boom" {
		t.Fatalf("failure toast = %q", a2.toast)
	}

	a3 := &App{}
	a3.openPollDialog()
	a3.updatePollDlg(func(d *pollDlgState) bool { d.busy = true; return true })
	a3.openPollDialog()
	a3.mu.Lock()
	gen2 := a3.pollDlgGen
	a3.mu.Unlock()
	if gen2 != 2 {
		t.Fatalf("reopen: gen = %d, want 2", gen2)
	}
	a3.updatePollDlg(func(d *pollDlgState) bool { d.busy = true; return true })
	a3.pollSendDone(1, nil)
	a3.mu.Lock()
	d3 := a3.pollDlg
	a3.mu.Unlock()
	if d3 == nil {
		t.Fatalf("stale success closed the reopened dialog")
	}
	if !d3.busy {
		t.Fatalf("stale success un-busied the new session's in-flight send")
	}
	a3.pollSendDone(1, boom)
	a3.mu.Lock()
	d4 := a3.pollDlg
	a3.mu.Unlock()
	if d4 == nil || !d4.busy {
		t.Fatalf("stale failure disturbed the new session's state")
	}
	if a3.toast != "Poll failed: boom" {
		t.Fatalf("stale failure toast = %q", a3.toast)
	}
}

func TestPollSubmitCapturesSwitchStateOnGuiLoop(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	a.mu.Lock()
	a.selected = &chatKey{AccountID: "acc1", ChatID: "c1"}
	a.mu.Unlock()
	a.openPollDialog()
	a.wid.pollQEd.SetText("Q?")
	pollOptEds[0].SetText("a")
	pollOptEds[1].SetText("b")

	var flip sync.Mutex
	stop := make(chan struct{})
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		for {
			flip.Lock()
			a.wid.pollAnonSw.Value = !a.wid.pollAnonSw.Value
			a.wid.pollMultiSw.Value = !a.wid.pollMultiSw.Value
			a.wid.pollQuizSw.Value = !a.wid.pollQuizSw.Value
			flip.Unlock()
			select {
			case <-stop:
				return
			default:
			}
		}
	}()
	for i := 0; i < 50; i++ {
		flip.Lock()
		a.updatePollDlg(func(d *pollDlgState) bool { d.busy = false; return true })
		a.submitPollDialog()
		flip.Unlock()
	}
	close(stop)
	wg.Wait()
}
