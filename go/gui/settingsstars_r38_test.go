package gui

import (
	"sync"
	"testing"

	"uniclient/cores"
)

func TestStarsPageStateIsCopyOnWrite(t *testing.T) {
	a := &App{}
	a.starsPage = &starsPageState{accountID: "acc", loading: true, filter: ""}
	a.mu.Lock()
	frameSt := a.starsPage
	a.mu.Unlock()

	var wg sync.WaitGroup
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			for j := 0; j < 1500; j++ {
				a.updateStarsPage(func(n *starsPageState) bool {
					if n.accountID != "acc" {
						return false
					}
					n.loading = false
					n.loaded = true
					n.err = ""
					n.status = &cores.StarsStatus{
						BalanceNano: int64(j),
						Txns:        []cores.StarsTxn{{ID: "t", NanoStars: int64(j)}},
						NextOffset:  "off",
					}
					n.nextPage = "off"
					return true
				})
				a.updateStarsPage(func(n *starsPageState) bool {
					n.filter = ""
					n.loading = true
					return true
				})
				a.updateStarsPage(func(n *starsPageState) bool {
					n.appending = j%2 == 0
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
			_ = frameSt.filter == ""
			_ = frameSt.appending
			_ = frameSt.nextPage != ""
			if frameSt.status != nil {
				_ = frameSt.status.BalanceNano
				for _, txn := range frameSt.status.Txns {
					_ = txn.ID != ""
				}
			}
			_ = frameSt.accountID
		}
	}()

	wg.Wait()
	<-readDone

	a.mu.Lock()
	head := a.starsPage
	a.mu.Unlock()
	if head == nil || head == frameSt {
		t.Fatal("head must be an installed copy distinct from the frame-held struct")
	}
	if frameSt.loaded || !frameSt.loading {
		t.Fatalf("frame-held struct must stay frozen: loading=%v loaded=%v",
			frameSt.loading, frameSt.loaded)
	}
}

func TestStarsAppendBuildsFreshSlice(t *testing.T) {
	a := &App{}
	a.starsPage = &starsPageState{accountID: "acc", loaded: true, status: &cores.StarsStatus{
		BalanceNano: 750,
		Txns:        []cores.StarsTxn{{ID: "p1a"}, {ID: "p1b"}},
		NextOffset:  "off1",
	}, nextPage: "off1"}

	a.mu.Lock()
	frameSt := a.starsPage
	frameTxns := frameSt.status.Txns
	frameStatus := frameSt.status
	a.mu.Unlock()

	page2 := &cores.StarsStatus{
		BalanceNano: 999,
		Txns:        []cores.StarsTxn{{ID: "p2a"}, {ID: "p2b"}, {ID: "p2c"}},
		NextOffset:  "",
	}
	head := a.updateStarsPage(func(n *starsPageState) bool {
		if n.accountID != "acc" || n.status == nil {
			return false
		}
		merged := &cores.StarsStatus{
			BalanceNano: n.status.BalanceNano,
			NextOffset:  page2.NextOffset,
		}
		merged.Txns = make([]cores.StarsTxn, 0, len(n.status.Txns)+len(page2.Txns))
		merged.Txns = append(merged.Txns, n.status.Txns...)
		merged.Txns = append(merged.Txns, page2.Txns...)
		n.status = merged
		n.nextPage = page2.NextOffset
		n.appending = false
		return true
	})
	if head == nil {
		t.Fatal("append install must succeed")
	}
	if head.status == frameStatus {
		t.Fatal("append must install a NEW StarsStatus, not mutate the old pointer")
	}
	if len(head.status.Txns) != 5 {
		t.Fatalf("merged history must have 5 rows, got %d", len(head.status.Txns))
	}
	if head.status.Txns[2].ID != "p2a" || head.status.Txns[4].ID != "p2c" {
		t.Fatalf("merge order broken: %v", head.status.Txns)
	}
	if head.status.BalanceNano != 750 {
		t.Fatalf("append keeps the loaded balance (old behavior), got %d", head.status.BalanceNano)
	}
	if len(frameStatus.Txns) != 2 || frameStatus.Txns[0].ID != "p1a" || frameStatus.Txns[1].ID != "p1b" {
		t.Fatalf("the frame-held status must keep its own rows: %v", frameStatus.Txns)
	}
	if &frameTxns[0] != &frameStatus.Txns[0] || cap(frameTxns) != cap(frameStatus.Txns) {
		t.Fatal("the frame-held slice header/backing must be untouched")
	}
}

func TestUpdateStarsPageContract(t *testing.T) {
	a := &App{}
	if got := a.updateStarsPage(func(n *starsPageState) bool { return true }); got != nil {
		t.Fatalf("closed page must return nil, got %+v", got)
	}

	a.starsPage = &starsPageState{accountID: "acc", loaded: true, filter: "in"}
	head := a.starsPage

	if got := a.updateStarsPage(func(n *starsPageState) bool { return false }); got != nil {
		t.Fatal("fn=false must return nil")
	}
	if a.starsPage != head {
		t.Fatal("fn=false must leave the head untouched")
	}

	got := a.updateStarsPage(func(n *starsPageState) bool {
		if n.accountID != "acc" {
			return false
		}
		n.loading = true
		return true
	})
	if got == nil || a.starsPage != got || got == head {
		t.Fatal("fn=true must install a copy that becomes the head")
	}
	if !got.loaded || got.filter != "in" {
		t.Fatal("untouched fields must carry over to the copy")
	}
	if !got.loading {
		t.Fatal("the mutation must be visible on the installed copy")
	}
	if head.loading {
		t.Fatal("the previous head must stay frozen (frame safety)")
	}
}
