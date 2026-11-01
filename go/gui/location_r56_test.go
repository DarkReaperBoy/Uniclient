package gui

import (
	"errors"
	"sync"
	"testing"

	"uniclient/engine"
)

func attachTestHead(a *App, st *attachDlgState) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.attachDlg = st
}

func attachCurrentHead(a *App) *attachDlgState {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.attachDlg
}

func TestUpdateAttachDlgContract(t *testing.T) {
	a := &App{}
	if a.updateAttachDlg(func(st *attachDlgState) bool { st.loaded = true; return true }) {
		t.Fatalf("nil head: installer reports an install")
	}
	attachTestHead(a, &attachDlgState{kind: "contact", account: "acc"})
	frozen := attachCurrentHead(a)

	if a.updateAttachDlg(func(st *attachDlgState) bool { return false }) {
		t.Fatalf("abort: installer reports an install")
	}
	if attachCurrentHead(a) != frozen {
		t.Fatalf("abort: head replaced anyway")
	}

	if !a.updateAttachDlg(func(st *attachDlgState) bool { st.loaded = true; return true }) {
		t.Fatalf("install: installer reports no install")
	}
	live := attachCurrentHead(a)
	if live == frozen || !live.loaded || frozen.loaded {
		t.Fatalf("install: loaded=%v frozen.loaded=%v fresh=%v", live.loaded, frozen.loaded, live == frozen)
	}

	var wg sync.WaitGroup
	for w := 0; w < 4; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := 0; i < 250; i++ {
				a.updateAttachDlg(func(st *attachDlgState) bool {
					st.loaded = i%2 == 0
					return true
				})
			}
		}()
	}
	wg.Wait()
	if frozen.loaded || frozen.err != "" || len(frozen.contacts) != 0 {
		t.Fatalf("frozen head mutated by hammer: %+v", *frozen)
	}
	if attachCurrentHead(a) == nil {
		t.Fatalf("hammer lost the head")
	}
}

func TestAttachDlgSnapshotImmutableUnderTails(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	a.mu.Lock()
	a.attachDlg = &attachDlgState{kind: "contact", account: "acc"}
	frozen := a.attachDlg
	a.mu.Unlock()

	stop := make(chan struct{})
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		for {
			select {
			case <-stop:
				return
			default:
				_ = frozen.loaded
				_ = frozen.err
				_ = len(frozen.contacts)
			}
		}
	}()
	contacts := []engine.ContactInfo{{UserID: "u1", DisplayName: "One"}}
	for i := 0; i < 300; i++ {
		a.attachContactsDone("acc", "contact", contacts, nil)
	}
	close(stop)
	wg.Wait()

	a.mu.Lock()
	defer a.mu.Unlock()
	if frozen.loaded || frozen.err != "" || len(frozen.contacts) != 0 {
		t.Fatalf("frozen head mutated: loaded=%v err=%q contacts=%d",
			frozen.loaded, frozen.err, len(frozen.contacts))
	}
}

func TestAttachContactsTailGuarded(t *testing.T) {
	a := &App{eng: &engine.Engine{}}

	a.mu.Lock()
	a.selected = &chatKey{AccountID: "acc", ChatID: "chat"}
	a.mu.Unlock()
	a.openAttachDialog("contact")
	h1 := attachCurrentHead(a)
	if h1 == nil || h1.kind != "contact" || h1.account != "acc" {
		t.Fatalf("open head wrong: %+v", h1)
	}
	attachTestHead(a, &attachDlgState{kind: "contact", account: "other"})
	frozen := attachCurrentHead(a)

	a.attachContactsDone("acc", "contact", []engine.ContactInfo{{UserID: "x"}}, nil)
	a.attachContactsDone("other", "location", []engine.ContactInfo{{UserID: "x"}}, nil)
	if attachCurrentHead(a) != frozen || frozen.loaded || len(frozen.contacts) != 0 || frozen.err != "" {
		t.Fatalf("foreign tail touched the head: %+v", *attachCurrentHead(a))
	}

	contacts := []engine.ContactInfo{{UserID: "u1"}, {UserID: "u2"}}
	a.attachContactsDone("other", "contact", contacts, nil)
	live := attachCurrentHead(a)
	if live == frozen || !live.loaded || len(live.contacts) != 2 || live.err != "" {
		t.Fatalf("live tail did not install: %+v", *live)
	}

	a.attachContactsDone("other", "contact", nil, errors.New("boom"))
	if live = attachCurrentHead(a); live.err != "boom" {
		t.Fatalf("engine error not surfaced: %q", live.err)
	}

	a.closeAttachDialog()
	if attachCurrentHead(a) != nil {
		t.Fatalf("close left a head")
	}
	a.attachContactsDone("other", "contact", contacts, nil)
	if attachCurrentHead(a) != nil {
		t.Fatalf("tail resurrected a closed dialog")
	}
}

func TestAttachLiveStateIsPerWindow(t *testing.T) {
	a1 := &App{}
	a2 := &App{}

	a1.attachLiveOn = true
	a1.attachLiveSel = 2
	a2.attachLiveOn = false
	a2.attachLiveSel = 0
	if a2.attachLiveOn || a2.attachLiveSel != 0 {
		t.Fatalf("window 2 inherited window 1's live state")
	}
	if !a1.attachLiveOn || a1.attachLiveSel != 2 {
		t.Fatalf("window 1 lost its live state")
	}

	a1.mu.Lock()
	a1.selected = &chatKey{AccountID: "acc", ChatID: "chat"}
	a1.mu.Unlock()
	a1.openAttachDialog("location")
	if a1.attachLiveOn || a1.attachLiveSel != 0 {
		t.Fatalf("open did not reset the live state: on=%v sel=%d", a1.attachLiveOn, a1.attachLiveSel)
	}
	if a2.attachLiveOn || a2.attachLiveSel != 0 {
		t.Fatalf("window 1's open touched window 2's state")
	}
	if attachCurrentHead(a1) == nil || attachCurrentHead(a1).kind != "location" {
		t.Fatalf("location open missing its head")
	}

	var wg sync.WaitGroup
	for _, a := range []*App{a1, a2} {
		wg.Add(1)
		go func(a *App) {
			defer wg.Done()
			for i := 0; i < 500; i++ {
				a.attachLiveOn = i%2 == 0
				a.attachLiveSel = i % 3
			}
		}(a)
	}
	wg.Wait()
}
