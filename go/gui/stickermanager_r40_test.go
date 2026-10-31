package gui

import (
	"sync"
	"testing"

	"uniclient/cores"
	"uniclient/engine"
)

// TestStickerMgrStateIsCopyOnWrite pins R40 (the fourth R34 sibling sweep):
// stickerMgrState was mutated IN PLACE by loadStickerMgr's and
// loadStickerMgrEmoji's completions, reloadStickerMgr, the search head+tail
// and setStickerMgrTab — all under a.mu — while the GUI loop read the same
// fields through the frame pointer under frameMu only (the tabs' st.tab,
// the rows' st.packs/featured/searchRes, the emoji tab's st.emoji*). R34's
// class (the class-level scratch repro is the RED evidence). The installer
// now installs copies.
func TestStickerMgrStateIsCopyOnWrite(t *testing.T) {
	a := &App{}
	a.stickerMgr = &stickerMgrState{accountID: "acc", loading: true, tab: stickerMgrTabStickers}
	// The frame's pointer, taken the way snapshot() takes it.
	a.mu.Lock()
	frameSt := a.stickerMgr
	a.mu.Unlock()

	var wg sync.WaitGroup
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			for j := 0; j < 1500; j++ {
				// The stickers-load tail's fields.
				a.updateStickerMgr(func(n *stickerMgrState) bool {
					if n.accountID != "acc" {
						return false
					}
					n.loading = false
					if j%2 == 0 {
						n.err = ""
						n.packs = []cores.StickerPackSummary{{SetID: int64(j)}}
						n.loaded = true
					} else {
						n.err = "boom"
					}
					if j%3 == 0 {
						n.featured = []cores.StickerPackSummary{{SetID: int64(j)}}
					}
					return true
				})
				// The emoji-load tail's fields.
				a.updateStickerMgr(func(n *stickerMgrState) bool {
					n.emojiLoading = false
					if j%2 == 0 {
						n.emojiErr = ""
						n.emojiSets = []cores.EmojiSetSummary{{SetID: int64(j)}}
						n.emojiLoaded = true
					} else {
						n.emojiErr = "boom"
					}
					return true
				})
				// The search tail's fields (with the stale-run key shape).
				a.updateStickerMgr(func(n *stickerMgrState) bool {
					n.searchRes = []cores.StickerPackSummary{{SetID: int64(j)}}
					n.searching = j%2 == 0
					return true
				})
			}
		}(i)
	}

	// The layout reader: the HELD pointer, no lock — what layoutStickerMgr
	// does under frameMu.
	readDone := make(chan struct{})
	go func() {
		defer close(readDone)
		for j := 0; j < 6000; j++ {
			_ = frameSt.loading && !frameSt.loaded
			_ = frameSt.err != ""
			_ = frameSt.tab
			_ = frameSt.searching
			for _, p := range frameSt.packs {
				_ = p.SetID
			}
			for _, p := range frameSt.featured {
				_ = p.SetID
			}
			for _, p := range frameSt.searchRes {
				_ = p.SetID
			}
			_ = frameSt.emojiLoading
			_ = frameSt.emojiErr != ""
			for _, s := range frameSt.emojiSets {
				_ = s.SetID
			}
			_ = frameSt.accountID
		}
	}()

	wg.Wait()
	<-readDone

	a.mu.Lock()
	head := a.stickerMgr
	a.mu.Unlock()
	if head == nil || head == frameSt {
		t.Fatal("head must be an installed copy distinct from the frame-held struct")
	}
	if frameSt.loaded || !frameSt.loading {
		t.Fatalf("frame-held struct must stay frozen: loading=%v loaded=%v",
			frameSt.loading, frameSt.loaded)
	}
}

// TestUpdateStickerMgrContract pins the installer: closed page → nil;
// fn=false → nil with the head untouched; fn=true → a NEW struct installed
// (untouched fields carried, mutations visible, previous head frozen).
func TestUpdateStickerMgrContract(t *testing.T) {
	a := &App{}
	if got := a.updateStickerMgr(func(n *stickerMgrState) bool { return true }); got != nil {
		t.Fatalf("closed page must return nil, got %+v", got)
	}

	a.stickerMgr = &stickerMgrState{accountID: "acc", loaded: true, tab: stickerMgrTabStickers, searchFor: "acc|cat"}
	head := a.stickerMgr

	if got := a.updateStickerMgr(func(n *stickerMgrState) bool { return false }); got != nil {
		t.Fatal("fn=false must return nil")
	}
	if a.stickerMgr != head {
		t.Fatal("fn=false must leave the head untouched")
	}

	got := a.updateStickerMgr(func(n *stickerMgrState) bool {
		if n.accountID != "acc" {
			return false // the accountID staleness guard
		}
		n.loading = true
		return true
	})
	if got == nil || a.stickerMgr != got || got == head {
		t.Fatal("fn=true must install a copy that becomes the head")
	}
	if !got.loaded || got.tab != stickerMgrTabStickers || got.searchFor != "acc|cat" {
		t.Fatal("untouched fields must carry over to the copy")
	}
	if !got.loading {
		t.Fatal("the mutation must be visible on the installed copy")
	}
	if head.loading {
		t.Fatal("the previous head must stay frozen (frame safety)")
	}

	// The search tail's staleness shape: a fn keyed on searchFor must abort
	// when a newer query superseded the run.
	if got := a.updateStickerMgr(func(n *stickerMgrState) bool {
		return n.searchFor == "acc|dog" // head still carries acc|cat
	}); got != nil {
		t.Fatal("a superseded search run must abort the install")
	}
}

// TestStickerMgrOpenClearsSiblings extends R39's exclusivity-matrix pin to
// the completed openStickerMgr (it used to miss folderMgr/premium/stars).
func TestStickerMgrOpenClearsSiblings(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	a.mu.Lock()
	a.profileEdit = &profileEditState{}
	a.folderMgr = &folderMgrState{}
	a.businessPage = &businessPageState{}
	a.premiumPage = &premiumPageState{}
	a.starsPage = &starsPageState{}
	a.mu.Unlock()
	a.openStickerMgr("acc")
	a.mu.Lock()
	if a.profileEdit != nil || a.folderMgr != nil || a.businessPage != nil ||
		a.premiumPage != nil || a.starsPage != nil {
		t.Fatal("openStickerMgr must clear every sibling sub-page")
	}
	if a.stickerMgr == nil || a.stickerMgr.accountID != "acc" {
		t.Fatal("openStickerMgr must install its own page")
	}
	a.mu.Unlock()
}
