package gui

import (
	"sync"
	"testing"
	"time"

	"uniclient/engine"
)

func TestIVStateIsCopyOnWrite(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	orig := &ivState{accountID: "acc", url: "https://telegra.ph/root", loading: true, openID: ivOpenSeq.Add(1)}
	a.mu.Lock()
	a.iv = orig
	a.mu.Unlock()

	var wg sync.WaitGroup
	stop := make(chan struct{})
	wg.Add(1)
	go func() {
		defer wg.Done()
		for {
			select {
			case <-stop:
				return
			default:
			}
			a.mu.Lock()
			h := a.iv
			a.mu.Unlock()
			if h != nil {
				_ = h.loading
				_ = h.err
				_ = h.page
				_ = h.gen
				_ = h.url
				_ = h.hist
			}
		}
	}()
	for i := 0; i < 3; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < 120; j++ {
				a.openInstantView("acc", "https://telegra.ph/x")
				a.ivOpenRelated("acc", "https://telegra.ph/y")
				a.ivBack()
			}
		}()
	}
	go func() {
		time.Sleep(120 * time.Millisecond)
		close(stop)
	}()
	wg.Wait()
	time.Sleep(100 * time.Millisecond)
	if !orig.loading || orig.err != "" || orig.page != nil || orig.gen != 0 || orig.url != "https://telegra.ph/root" || orig.hist != nil {
		t.Fatal("the original head was mutated in place — the R34/R46 write-races-layout class")
	}
}

func TestUpdateIVContract(t *testing.T) {
	a := &App{}
	ran := false
	if head := a.updateIV(func(cur *ivState) bool { ran = true; return true }); head != nil || ran {
		t.Fatal("a nil head must be a no-op — fn must never run")
	}

	orig := &ivState{accountID: "acc", loading: true, openID: 3}
	a.mu.Lock()
	a.iv = orig
	a.mu.Unlock()
	if head := a.updateIV(func(cur *ivState) bool { return false }); head != nil {
		t.Fatal("an aborted update must return nil")
	}
	a.mu.Lock()
	got := a.iv
	a.mu.Unlock()
	if got != orig {
		t.Fatal("an aborted update must leave the head pointer untouched")
	}

	if head := a.updateIV(func(cur *ivState) bool {
		if cur.accountID != "acc" || cur.openID != 3 {
			return false
		}
		cur.loading = false
		cur.err = "done"
		return true
	}); head == nil || head == orig {
		t.Fatal("an accepted update must install and return a fresh head")
	} else {
		if head.loading || head.err != "done" {
			t.Fatal("the installed copy must carry fn's changes")
		}
	}
	a.mu.Lock()
	got = a.iv
	a.mu.Unlock()
	if got == orig || got.loading || got.err != "done" {
		t.Fatal("the new head must be installed with fn's changes")
	}
	if !orig.loading || orig.err != "" {
		t.Fatal("the replaced head must stay frozen (frame safety)")
	}
}

func TestIVOpenTailLandsCopyOnWrite(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	a.openInstantView("ghost", "https://telegra.ph/page")
	a.mu.Lock()
	opened := a.iv
	a.mu.Unlock()
	if opened == nil || opened.accountID != "ghost" || !opened.loading || opened.openID == 0 {
		t.Fatal("open must install a loading reader with a fresh openID")
	}
	deadline := time.Now().Add(5 * time.Second)
	for {
		a.mu.Lock()
		cur := a.iv
		a.mu.Unlock()
		if cur != nil && !cur.loading && cur.err != "" {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the open tail never landed")
		}
		time.Sleep(2 * time.Millisecond)
	}
	if !opened.loading || opened.err != "" || opened.page != nil {
		t.Fatal("the open-time head must stay frozen while the tail lands")
	}
}

func TestIVOpenIDsRetireStragglers(t *testing.T) {
	a := &App{}
	first := &ivState{accountID: "acc", gen: 4, openID: ivOpenSeq.Add(1), loading: true}
	a.mu.Lock()
	a.iv = first
	a.mu.Unlock()
	second := &ivState{accountID: "acc", gen: 4, openID: ivOpenSeq.Add(1), loading: true}
	a.mu.Lock()
	a.iv = second
	a.mu.Unlock()
	if landed, _ := a.ivLandRelated(first.openID, 4, ivPageJSON("https://telegra.ph/straggler"), nil); landed {
		t.Fatal("a straggler from a previous reader session must be dropped (R46 openID guard)")
	}
	a.mu.Lock()
	h := a.iv
	a.mu.Unlock()
	if h != second || h.page != nil || h.loading != true {
		t.Fatal("the dropped straggler must leave the reopened reader untouched")
	}
	if landed, _ := a.ivLandRelated(second.openID, 4, ivPageJSON("https://telegra.ph/now"), nil); !landed {
		t.Fatal("the current session's fetch must land")
	}
	a.mu.Lock()
	h = a.iv
	a.mu.Unlock()
	if h.page == nil || h.page.URL != "https://telegra.ph/now" {
		t.Fatal("the landed page must be shown")
	}
}

func TestIVPushHistoryBuildsFreshSlice(t *testing.T) {
	first := &ivPage{URL: "https://telegra.ph/first"}
	second := &ivPage{URL: "https://telegra.ph/second"}
	root := &ivPage{URL: "https://telegra.ph/root"}
	next := &ivPage{URL: "https://telegra.ph/next"}
	backing := []*ivPage{first, second}
	old := &ivState{accountID: "acc", page: root, hist: backing[:1], openID: 1}

	cp := *old
	cp.pushHistory(next)

	if len(cp.hist) != 2 || cp.hist[0] != first || cp.hist[1] != root || cp.page != next {
		t.Fatalf("pushHistory's observable semantics must hold (push old, show new): len=%d page=%v", len(cp.hist), cp.page)
	}
	if &cp.hist[0] == &old.hist[0] {
		t.Fatal("pushHistory appended into the shared backing array — the R38 class")
	}
	if backing[1] != second {
		t.Fatal("the pre-fix append wrote into the head's backing array")
	}
	if len(old.hist) != 1 || old.page != root {
		t.Fatal("the original head must stay frozen")
	}
}
