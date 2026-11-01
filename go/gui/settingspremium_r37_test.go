package gui

import (
	"fmt"
	"sync"
	"testing"

	"uniclient/cores"
)

func TestPremiumPageStateIsCopyOnWrite(t *testing.T) {
	a := &App{}
	a.premiumPage = &premiumPageState{accountID: "acc", loading: true}
	a.mu.Lock()
	frameSt := a.premiumPage
	a.mu.Unlock()

	var wg sync.WaitGroup
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			for j := 0; j < 1500; j++ {
				a.updatePremiumPage(func(n *premiumPageState) bool {
					if n.accountID != "acc" {
						return false
					}
					n.loading = false
					if j%2 == 0 {
						n.err = ""
						n.loaded = true
						n.promo = &cores.PremiumPromo{StatusText: fmt.Sprintf("s%d", j)}
					} else {
						n.err = fmt.Sprintf("e%d", j)
					}
					if j%3 == 0 {
						n.limits = map[string]int{"free_limit": j}
					}
					return true
				})
				a.updatePremiumPage(func(n *premiumPageState) bool {
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
			if frameSt.promo != nil {
				_ = frameSt.promo.StatusText != ""
			}
			if frameSt.limits != nil {
				_ = frameSt.limits["free_limit"]
			}
			_ = frameSt.accountID
		}
	}()

	wg.Wait()
	<-readDone

	a.mu.Lock()
	head := a.premiumPage
	a.mu.Unlock()
	if head == nil {
		t.Fatal("premium page must survive the hammering")
	}
	if head == frameSt {
		t.Fatal("head must be an installed copy, not the frame-held struct")
	}
	if !head.loading {
		t.Fatal("the last install (reload's loading=true) must win")
	}
	if frameSt.loaded || !frameSt.loading {
		t.Fatalf("frame-held struct must stay frozen: loading=%v loaded=%v",
			frameSt.loading, frameSt.loaded)
	}
}

func TestUpdatePremiumPageContract(t *testing.T) {
	a := &App{}
	if got := a.updatePremiumPage(func(n *premiumPageState) bool { return true }); got != nil {
		t.Fatalf("closed page must return nil, got %+v", got)
	}

	a.premiumPage = &premiumPageState{accountID: "acc", loaded: true, limits: map[string]int{"free_limit": 10}}
	head := a.premiumPage

	if got := a.updatePremiumPage(func(n *premiumPageState) bool { return false }); got != nil {
		t.Fatal("fn=false must return nil")
	}
	if a.premiumPage != head {
		t.Fatal("fn=false must leave the head untouched")
	}

	got := a.updatePremiumPage(func(n *premiumPageState) bool {
		if n.accountID != "acc" {
			return false
		}
		n.loading = true
		return true
	})
	if got == nil {
		t.Fatal("fn=true must install")
	}
	if a.premiumPage != got || got == head {
		t.Fatal("install must be a copy that becomes the head")
	}
	if !got.loaded || got.limits["free_limit"] != 10 {
		t.Fatal("untouched fields must carry over to the copy")
	}
	if !got.loading {
		t.Fatal("the mutation must be visible on the installed copy")
	}
	if head.loading {
		t.Fatal("the previous head must stay frozen (frame safety)")
	}
}
