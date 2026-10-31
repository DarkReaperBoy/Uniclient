package gui

// R46 pins (chunk 3 iteration 29 — the LAST item of the R34 systemic
// watch, instantview.go's state lifecycle): the Instant View reader's
// state had R34's pre-fix shape — openInstantView's load tail and
// ivLandRelated (the related-fetch landing) mutated the frame-carried
// ivState IN PLACE under a.mu (with pointer-identity retirement checks
// that do not stop the frameMu-side reads), and ivOpenRelated's head +
// ivBack wrote the same fields in place on the GUI loop (lost-click
// class). Every writer now goes through copy-on-write: the tails via
// updateIV with openID (cross-session) + gen (within-session navigation)
// staleness guards — pointer identity breaks under copy-on-write, since
// every install swaps the pointer — and the GUI-loop heads install
// copies in their own lock section. pushHistory builds a FRESH history
// slice (the R38 rule). The detailsOpen/slideIdx maps stay shared
// (GUI-loop-only writers); docBusy keeps its own ivDocMu (verified this
// iteration — the watch note's claim holds).

import (
	"sync"
	"testing"
	"time"

	"uniclient/engine"
)

// TestIVStateIsCopyOnWrite pins R46's core: the open/related/back writers
// must swap the head, never mutate the frame-visible struct in place. A
// reader continuously captures the current head and reads its fields with
// NO lock (what layout does under frameMu) while three writers churn
// through the real entry points — under the pre-fix in-place writes this
// is a -race report on loading/err/page/gen/url/hist; under the fix every
// installed head is immutable once published.
func TestIVStateIsCopyOnWrite(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	// The original head: installed once, then only ever REPLACED.
	orig := &ivState{accountID: "acc", url: "https://telegra.ph/root", loading: true, openID: ivOpenSeq.Add(1)}
	a.mu.Lock()
	a.iv = orig
	a.mu.Unlock()

	var wg sync.WaitGroup
	stop := make(chan struct{})
	wg.Add(1)
	go func() { // the GUI-loop reader stand-in: unsynchronized field reads
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
	for i := 0; i < 3; i++ { // the writers: open / related / back churn
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
	// Drain: let the last spawned tails finish scheduling (the -race
	// detector has already observed any real overlap during the hammer).
	time.Sleep(100 * time.Millisecond)
	if !orig.loading || orig.err != "" || orig.page != nil || orig.gen != 0 || orig.url != "https://telegra.ph/root" || orig.hist != nil {
		t.Fatal("the original head was mutated in place — the R34/R46 write-races-layout class")
	}
}

// TestUpdateIVContract pins the installer semantics: nil head is a no-op
// (fn never runs, nil returned), a false return leaves the head alone
// (same pointer, nil returned), an accepted update installs a FRESH head
// and the previous head stays frozen. (Compile seam: updateIV does not
// exist pre-fix.)
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

// TestIVOpenTailLandsCopyOnWrite pins openInstantView's load: the open
// installs a loading reader with a fresh openID, the tail (the fetch
// errors immediately on the bare engine harness) lands through the
// installer with loading cleared and the error shown, and the OPEN-TIME
// state stays frozen.
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

// TestIVOpenIDsRetireStragglers pins the openID half of the staleness key:
// a straggler tail from a PREVIOUS reader session must never land on a
// reopened reader — the case pointer identity used to cover and gen alone
// cannot (a reopened reader walks the same gen sequence).
func TestIVOpenIDsRetireStragglers(t *testing.T) {
	a := &App{}
	first := &ivState{accountID: "acc", gen: 4, openID: ivOpenSeq.Add(1), loading: true}
	a.mu.Lock()
	a.iv = first
	a.mu.Unlock()
	// The reader is closed and reopened: a fresh session, same account,
	// same gen sequence position.
	second := &ivState{accountID: "acc", gen: 4, openID: ivOpenSeq.Add(1), loading: true}
	a.mu.Lock()
	a.iv = second
	a.mu.Unlock()
	// The first session's straggler (openID mismatch) must be dropped.
	if landed, _ := a.ivLandRelated(first.openID, 4, ivPageJSON("https://telegra.ph/straggler"), nil); landed {
		t.Fatal("a straggler from a previous reader session must be dropped (R46 openID guard)")
	}
	a.mu.Lock()
	h := a.iv
	a.mu.Unlock()
	if h != second || h.page != nil || h.loading != true {
		t.Fatal("the dropped straggler must leave the reopened reader untouched")
	}
	// The CURRENT session's fetch at the current generation lands.
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

// TestIVPushHistoryBuildsFreshSlice pins the R38 half of R46: pushHistory
// never appends into a backing array a previous head still holds — the
// pushed slice is a fresh allocation, and the replaced head's slice and
// backing are untouched.
func TestIVPushHistoryBuildsFreshSlice(t *testing.T) {
	first := &ivPage{URL: "https://telegra.ph/first"}
	second := &ivPage{URL: "https://telegra.ph/second"}
	root := &ivPage{URL: "https://telegra.ph/root"}
	next := &ivPage{URL: "https://telegra.ph/next"}
	// Backing with spare capacity: the pre-fix append wrote into THIS array.
	backing := []*ivPage{first, second}
	old := &ivState{accountID: "acc", page: root, hist: backing[:1], openID: 1}

	cp := *old // the installer's copy
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
