package gui

import (
	"sync"
	"testing"

	"uniclient/engine"
)

// TestFolderMgrStateIsCopyOnWrite pins R39 (the third R34 sibling sweep):
// folderMgrState was mutated IN PLACE by loadFolderMgr's completion
// (loading/err/loaded/folders/suggested under a.mu, from the background
// load goroutine) while the GUI loop read the same fields through the
// frame pointer under frameMu only — R34's class (RED-proven at R34 with
// the dependency-free scratch repro). updateFolderMgr now installs copies.
func TestFolderMgrStateIsCopyOnWrite(t *testing.T) {
	a := &App{}
	a.folderMgr = &folderMgrState{accountID: "acc", loading: true}
	// The frame's pointer, taken the way snapshot() takes it.
	a.mu.Lock()
	frameSt := a.folderMgr
	a.mu.Unlock()

	var wg sync.WaitGroup
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			for j := 0; j < 1500; j++ {
				// The load tail's fields, through the real installer.
				a.updateFolderMgr(func(n *folderMgrState) bool {
					if n.accountID != "acc" {
						return false
					}
					n.loading = false
					if j%2 == 0 {
						n.err = ""
						n.loaded = true
						n.folders = []engine.FolderInfo{{ID: "f", Name: "n"}}
					} else {
						n.err = "boom"
					}
					if j%3 == 0 {
						n.suggested = []engine.SuggestedFolderInfo{{Name: "s"}}
					}
					return true
				})
				// The reload path's field.
				a.updateFolderMgr(func(n *folderMgrState) bool {
					n.loading = true
					return true
				})
			}
		}(i)
	}

	// The layout reader: the HELD pointer, no lock — what layoutFolderMgr
	// does under frameMu.
	readDone := make(chan struct{})
	go func() {
		defer close(readDone)
		for j := 0; j < 6000; j++ {
			_ = frameSt.loading && !frameSt.loaded
			_ = frameSt.err != ""
			_ = len(frameSt.err)
			for _, f := range frameSt.folders {
				_ = f.ID != ""
			}
			for _, s := range frameSt.suggested {
				_ = s.Name != ""
			}
			_ = frameSt.accountID
		}
	}()

	wg.Wait()
	<-readDone

	a.mu.Lock()
	head := a.folderMgr
	a.mu.Unlock()
	if head == nil || head == frameSt {
		t.Fatal("head must be an installed copy distinct from the frame-held struct")
	}
	if !head.loading {
		t.Fatal("the last install (reload's loading=true) must win")
	}
	if frameSt.loaded || !frameSt.loading {
		t.Fatalf("frame-held struct must stay frozen: loading=%v loaded=%v",
			frameSt.loading, frameSt.loaded)
	}
}

// TestUpdateFolderMgrContract pins the installer: closed page → nil; fn=false
// → nil with the head untouched; fn=true → a NEW struct installed (untouched
// fields carried, mutations visible, previous head frozen).
func TestUpdateFolderMgrContract(t *testing.T) {
	a := &App{}
	if got := a.updateFolderMgr(func(n *folderMgrState) bool { return true }); got != nil {
		t.Fatalf("closed page must return nil, got %+v", got)
	}

	a.folderMgr = &folderMgrState{accountID: "acc", loaded: true, folders: []engine.FolderInfo{{ID: "f1"}}}
	head := a.folderMgr

	if got := a.updateFolderMgr(func(n *folderMgrState) bool { return false }); got != nil {
		t.Fatal("fn=false must return nil")
	}
	if a.folderMgr != head {
		t.Fatal("fn=false must leave the head untouched")
	}

	got := a.updateFolderMgr(func(n *folderMgrState) bool {
		if n.accountID != "acc" {
			return false // the staleness guard the load tail relies on
		}
		n.loading = true
		return true
	})
	if got == nil || a.folderMgr != got || got == head {
		t.Fatal("fn=true must install a copy that becomes the head")
	}
	if !got.loaded || len(got.folders) != 1 || got.folders[0].ID != "f1" {
		t.Fatal("untouched fields must carry over to the copy")
	}
	if !got.loading {
		t.Fatal("the mutation must be visible on the installed copy")
	}
	if head.loading {
		t.Fatal("the previous head must stay frozen (frame safety)")
	}
}

// TestSettingsSubPagesAreExclusive pins R39's matrix completion: every
// open<Page> nils every sibling. The gap was reachable in one direction
// (suggestionbar's premium upsell opens Premium while another sub-page is
// open); the settings shell's shadow order made it benign, but closing the
// shadowing page resurrected the stale one. The assertion covers the
// synchronous install under a.mu — the spawned load goroutine touches only
// the page's own state (and fails fast on the bare harness).
func TestSettingsSubPagesAreExclusive(t *testing.T) {
	a := &App{eng: &engine.Engine{}}

	// openFolderMgr clears ALL five siblings (the R39 fix).
	a.mu.Lock()
	a.profileEdit = &profileEditState{}
	a.stickerMgr = &stickerMgrState{}
	a.businessPage = &businessPageState{}
	a.premiumPage = &premiumPageState{}
	a.starsPage = &starsPageState{}
	a.mu.Unlock()
	a.openFolderMgr("acc")
	a.mu.Lock()
	if a.profileEdit != nil || a.stickerMgr != nil || a.businessPage != nil ||
		a.premiumPage != nil || a.starsPage != nil {
		t.Fatal("openFolderMgr must clear every sibling sub-page")
	}
	if a.folderMgr == nil || a.folderMgr.accountID != "acc" {
		t.Fatal("openFolderMgr must install its own page")
	}
	a.mu.Unlock()

	// openPremiumPage clears starsPage (the R39 completion).
	a.mu.Lock()
	a.starsPage = &starsPageState{}
	a.mu.Unlock()
	a.openPremiumPage("acc")
	a.mu.Lock()
	if a.starsPage != nil {
		t.Fatal("openPremiumPage must clear starsPage")
	}
	if a.premiumPage == nil {
		t.Fatal("openPremiumPage must install its own page")
	}
	a.mu.Unlock()
}
