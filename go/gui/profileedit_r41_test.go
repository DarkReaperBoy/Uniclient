package gui

import (
	"sync"
	"testing"

	"uniclient/engine"
)

func TestProfileEdSyncedIsAtomic(t *testing.T) {
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		for j := 0; j < 3000; j++ {
			profileEdSynced.Store(false)
		}
	}()
	for j := 0; j < 3000; j++ {
		if !profileEdSynced.Load() {
			profileEdSynced.Store(true)
		}
	}
	wg.Wait()
}

func TestProfileEditLoadReplacesState(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	old := &profileEditState{accountID: "accA", loaded: true, username: "keepme"}
	a.profileEdit = old

	a.loadProfileEdit("accB")
	a.mu.Lock()
	if a.profileEdit != old {
		t.Fatal("a load for a different account must leave the head untouched")
	}
	a.mu.Unlock()

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
	if old.username != "keepme" || !old.loaded {
		t.Fatal("the replaced head must stay frozen")
	}
}

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
