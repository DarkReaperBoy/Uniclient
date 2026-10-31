package gui

import (
	"sync"
	"testing"

	"uniclient/engine"
)

// TestProfileEdSyncedIsAtomic pins R41: profileEdSynced was a plain
// package bool — the profile loader's tail (a background goroutine) wrote
// `profileEdSynced = false` when a fresh state landed while the GUI loop
// read/ wrote it in layoutProfileEdit's priming block — R32's exact
// write-races-layout class. It is now an atomic.Bool (R32's fix shape);
// this pin hammers both sides through the real variable, which fails to
// COMPILE against the pre-fix plain bool (Load/Store undefined — the
// R24/R32 compile-seam pattern).
func TestProfileEdSyncedIsAtomic(t *testing.T) {
	var wg sync.WaitGroup
	// The load-tail side: a fresh state lands, the priming must re-run.
	wg.Add(1)
	go func() {
		defer wg.Done()
		for j := 0; j < 3000; j++ {
			profileEdSynced.Store(false)
		}
	}()
	// The GUI-loop side: prime (read + set true).
	for j := 0; j < 3000; j++ {
		if !profileEdSynced.Load() {
			profileEdSynced.Store(true)
		}
	}
	wg.Wait()
}

// TestProfileEditLoadReplacesState pins the loader's install discipline
// (the one part of profileedit.go that was already right): loadProfileEdit
// builds a FRESH state and REPLACES a.profileEdit under a.mu with an
// accountID staleness guard — never an in-place mutation. On the bare
// engine harness every fetch returns empty/error, so the fresh state is
// the zero-value-plus-loaded shape.
func TestProfileEditLoadReplacesState(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	old := &profileEditState{accountID: "accA", loaded: true, username: "keepme"}
	a.profileEdit = old

	// A load for another account must not touch the installed state.
	a.loadProfileEdit("accB")
	a.mu.Lock()
	if a.profileEdit != old {
		t.Fatal("a load for a different account must leave the head untouched")
	}
	a.mu.Unlock()

	// A load for the open account replaces the head with a FRESH struct.
	a.loadProfileEdit("accA")
	a.mu.Lock()
	head := a.profileEdit
	a.mu.Unlock()
	if head == nil || head == old {
		t.Fatal("a live load must replace the head with a fresh struct")
	}
	if !head.loaded {
		t.Fatal("the fresh state must be loaded")
	}
	if head.accountID != "accA" {
		t.Fatalf("fresh state account: want accA, got %q", head.accountID)
	}
	if head.username != "" {
		t.Fatalf("the bare harness yields no username, got %q", head.username)
	}
	// The previous head stays frozen (frame safety).
	if old.username != "keepme" || !old.loaded {
		t.Fatal("the replaced head must stay frozen")
	}
}

// TestProfileEditOpenClearsSiblings completes R39's exclusivity-matrix pin:
// openProfileEdit was the last opener with gaps (it nilled only
// businessPage).
func TestProfileEditOpenClearsSiblings(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	a.mu.Lock()
	a.stickerMgr = &stickerMgrState{}
	a.folderMgr = &folderMgrState{}
	a.businessPage = &businessPageState{}
	a.premiumPage = &premiumPageState{}
	a.starsPage = &starsPageState{}
	a.mu.Unlock()
	a.openProfileEdit("acc")
	a.mu.Lock()
	if a.stickerMgr != nil || a.folderMgr != nil || a.businessPage != nil ||
		a.premiumPage != nil || a.starsPage != nil {
		t.Fatal("openProfileEdit must clear every sibling sub-page")
	}
	if a.profileEdit == nil || a.profileEdit.accountID != "acc" {
		t.Fatal("openProfileEdit must install its own page")
	}
	a.mu.Unlock()
}
