package gui

import (
	"errors"
	"sync"
	"testing"
	"time"

	"uniclient/cores"
	"uniclient/engine"
)

func TestTwoFADlgStateIsCopyOnWrite(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	a.mu.Lock()
	a.twofaDlg = &twofaDlgState{accountID: "acc", step: twofaStepNew}
	a.mu.Unlock()
	head := a.twofaDlg

	var wg sync.WaitGroup
	stop := make(chan struct{})
	wg.Add(1)
	go func() {
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
	for i := 0; i < 3; i++ {
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
