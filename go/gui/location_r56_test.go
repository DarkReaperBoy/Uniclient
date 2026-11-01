package gui

import (
	"errors"
	"sync"
	"testing"

	"uniclient/engine"
)

// R56 + R57 pins (chunk 3, iteration 35 — location.go read in full).

// attachTestHead installs an attach-dialog head directly (the GUI-loop
// stand-in for openAttachDialog's install).
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

	// Concurrent installer hammer: every install is a fresh struct; the
	// frozen head never changes under any of them.
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

// R57 pin: a frame's attachDlg snapshot must stay immutable while the
// contact-list load lands. The reader loop plays the GUI loop — lock-free
// field reads, exactly what layoutAttachDialog/contactDlgList do through
// f.attachDlg; the hammer plays the background load tail (attachContactsDone
// is the extracted open goroutine tail). Pre-fix (in-place writes under
// a.mu) the race detector fires AND the frozen-snapshot assert fails —
// TRUE tool-proven RED against the stage-1 extraction-only build; the
// copy-on-write installs leave the captured snapshot untouched.
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

	// The real entry point installs a head per open (identity fields).
	a.mu.Lock()
	a.selected = &chatKey{AccountID: "acc", ChatID: "chat"}
	a.mu.Unlock()
	a.openAttachDialog("contact")
	h1 := attachCurrentHead(a)
	if h1 == nil || h1.kind != "contact" || h1.account != "acc" {
		t.Fatalf("open head wrong: %+v", h1)
	}
	// Retire the real open's in-flight tail (bare-harness engine errors
	// land async) by moving the head to another account.
	attachTestHead(a, &attachDlgState{kind: "contact", account: "other"})
	frozen := attachCurrentHead(a)

	// Foreign account / foreign kind never touch the live head.
	a.attachContactsDone("acc", "contact", []engine.ContactInfo{{UserID: "x"}}, nil)
	a.attachContactsDone("other", "location", []engine.ContactInfo{{UserID: "x"}}, nil)
	if attachCurrentHead(a) != frozen || frozen.loaded || len(frozen.contacts) != 0 || frozen.err != "" {
		t.Fatalf("foreign tail touched the head: %+v", *attachCurrentHead(a))
	}

	// The live identity installs: fresh head, contacts loaded.
	contacts := []engine.ContactInfo{{UserID: "u1"}, {UserID: "u2"}}
	a.attachContactsDone("other", "contact", contacts, nil)
	live := attachCurrentHead(a)
	if live == frozen || !live.loaded || len(live.contacts) != 2 || live.err != "" {
		t.Fatalf("live tail did not install: %+v", *live)
	}

	// Error path is honest and does not wipe a loaded list's structure.
	a.attachContactsDone("other", "contact", nil, errors.New("boom"))
	if live = attachCurrentHead(a); live.err != "boom" {
		t.Fatalf("engine error not surfaced: %q", live.err)
	}

	// A closed dialog stays closed.
	a.closeAttachDialog()
	if attachCurrentHead(a) != nil {
		t.Fatalf("close left a head")
	}
	a.attachContactsDone("other", "contact", contacts, nil)
	if attachCurrentHead(a) != nil {
		t.Fatalf("tail resurrected a closed dialog")
	}
}

// R56 pin: the live-location dialog state is per-window (per-App) — two
// windows arm independent dialogs, and the open resets its own. Pre-fix
// the state was PACKAGE-level: two GUI goroutines raced one bool/int and
// window A's toggle flipped window B's dialog (RED pre-fix = the compile
// seam — the fields did not exist).
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

	// The open resets its own window's state (live mode never leaks
	// across dialog opens).
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

	// Cross-window hammer under -race: each goroutine only its own App.
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
