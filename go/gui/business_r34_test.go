package gui

import (
	"fmt"
	"sync"
	"testing"
)

func TestBusinessPageStateIsCopyOnWrite(t *testing.T) {
	a := &App{}
	a.businessPage = &businessPageState{accountID: "acc", loading: true, editor: "hours"}
	a.mu.Lock()
	frameSt := a.businessPage
	a.mu.Unlock()

	var wg sync.WaitGroup
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			for j := 0; j < 1500; j++ {
				a.updateBusinessPage(func(n *businessPageState) bool {
					if n.accountID != "acc" {
						return false
					}
					n.loading = false
					n.loaded = true
					n.err = fmt.Sprintf("e%d", j)
					n.info = map[string]interface{}{"k": j}
					n.timezones = nil
					n.tzLoaded = j%2 == 0
					n.replies = nil
					return true
				})
				a.updateBusinessPage(func(n *businessPageState) bool {
					if n.accountID != "acc" {
						return false
					}
					n.busy = j%2 == 0
					n.editorErr = fmt.Sprintf("b%d", j)
					if j%3 == 0 {
						n.editor = ""
					}
					return true
				})
				a.updateBusinessPage(func(n *businessPageState) bool {
					n.qrNewOpen = j%2 == 0
					n.qrRenameID = j
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
			_ = len(frameSt.info)
			_ = frameSt.tzLoaded
			_ = frameSt.editor == "hours"
			_ = frameSt.editorErr != ""
			_ = frameSt.busy
			_ = frameSt.qrNewOpen
			_ = frameSt.qrRenameID
			_ = frameSt.accountID
		}
	}()

	wg.Wait()
	<-readDone

	a.mu.Lock()
	head := a.businessPage
	a.mu.Unlock()
	if head == nil {
		t.Fatal("business page must survive the hammering")
	}
	if head == frameSt {
		t.Fatal("head must be an installed copy, not the frame-held struct")
	}
	if head.qrRenameID != 1499 {
		t.Fatalf("last QR install must win: want qrRenameID=1499, got %d", head.qrRenameID)
	}
	if !head.loaded || head.loading {
		t.Fatalf("load-tail fields must survive: loaded=%v loading=%v", head.loaded, head.loading)
	}
	if frameSt.editor != "hours" || !frameSt.loading || frameSt.loaded {
		t.Fatalf("frame-held struct must stay frozen at install time: editor=%q loading=%v loaded=%v",
			frameSt.editor, frameSt.loading, frameSt.loaded)
	}
}

func TestUpdateBusinessPageContract(t *testing.T) {
	a := &App{}
	if got := a.updateBusinessPage(func(n *businessPageState) bool { return true }); got != nil {
		t.Fatalf("closed page must return nil, got %+v", got)
	}

	a.businessPage = &businessPageState{accountID: "acc", editor: "hours", tzPick: "UTC", busy: false}
	head := a.businessPage

	got := a.updateBusinessPage(func(n *businessPageState) bool { return false })
	if got != nil {
		t.Fatal("fn=false must return nil")
	}
	if a.businessPage != head {
		t.Fatal("fn=false must leave the head untouched")
	}

	got = a.updateBusinessPage(func(n *businessPageState) bool {
		if n.accountID != "acc" || n.busy {
			return false
		}
		n.busy = true
		n.editorErr = "boom"
		return true
	})
	if got == nil {
		t.Fatal("fn=true must install")
	}
	if a.businessPage != got {
		t.Fatal("installed copy must become the head")
	}
	if got == head {
		t.Fatal("install must be a copy, not an in-place write")
	}
	if got.tzPick != "UTC" || got.editor != "hours" {
		t.Fatal("untouched fields must carry over to the copy")
	}
	if !got.busy || got.editorErr != "boom" {
		t.Fatal("mutations must be visible on the installed copy")
	}
	if head.busy || head.editorErr != "" {
		t.Fatal("the previous head must stay frozen (frame safety)")
	}
}
