package gui

import (
	"sync"
	"testing"

	"uniclient/engine"
)

func TestFolderMgrStateIsCopyOnWrite(t *testing.T) {
	a := &App{}
	a.folderMgr = &folderMgrState{accountID: "acc", loading: true}
	a.mu.Lock()
	frameSt := a.folderMgr
	a.mu.Unlock()

	var wg sync.WaitGroup
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			for j := 0; j < 1500; j++ {
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
				a.updateFolderMgr(func(n *folderMgrState) bool {
					n.loading = true
					return true
				})
			}
		}(i)
	}

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
			return false
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

func TestSettingsSubPagesAreExclusive(t *testing.T) {
	a := &App{eng: &engine.Engine{}}

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
