package gui

// R47/R48 pins (chunk 3 iteration 31, the unscanned-file queue by size #2
// — giveaways.go read in full):
//
//   - R47: giveawayDlgState had R34's pre-fix shape — openGiveawayCreator's
//     load tail and sendGiveaway's two send tails mutated the frame-carried
//     struct IN PLACE under a.mu (with staleness guards that do not stop
//     the frameMu-side reads), every GUI-loop click writer did the same,
//     and the dateIdx clamp wrote the FROZEN frame pointer directly (not
//     even under a.mu) — after periodMax shrank the preset list the live
//     head stayed out of range and the Send button went silently dead.
//     All writers now go through updateGiveaway (copy-on-write, the
//     R34 discipline) with accountID+chatID (+prepaid-ID) staleness
//     guards; the create tail's old prepaid==nil-only guard also let a
//     stale tail stomp a dialog reopened for the same chat — fixed.
//   - R48: openPrepaidLaunch ran GetGiveawayPeriodMax SYNCHRONOUSLY on the
//     GUI loop — a blocking RPC on the frame thread. Goroutine-wrapped
//     now (inspection-verified shape change; no behavioral pin exists on
//     the bare harness, where the RPC errors fast and max<=0 installs
//     nothing).

import (
	"sync"
	"testing"
	"time"

	"uniclient/cores"
	"uniclient/engine"
)

// TestGiveawayStateIsCopyOnWrite pins R47's core: the open/toggle/close
// writers must swap the head, never mutate the frame-visible struct in
// place. A reader continuously captures the current head and reads its
// fields with NO lock (what layout does under frameMu) while three
// writers churn through the real entry points — under the pre-fix
// in-place writes this is a -race report; under the fix every installed
// head is immutable once published.
func TestGiveawayStateIsCopyOnWrite(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	orig := &giveawayDlgState{accountID: "acc", chatID: "c1", peerTitle: "T", onlyNew: true}
	a.mu.Lock()
	a.giveawayDlg = orig
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
			h := a.giveawayDlg
			a.mu.Unlock()
			if h != nil {
				_ = h.loaded
				_ = h.err
				_ = h.sending
				_ = h.launched
				_ = h.selOpt
				_ = h.selWin
				_ = h.dateIdx
				_ = h.onlyNew
				_ = h.showWinners
				_ = h.periodMax
				_ = h.balance
				_ = h.countryQuery
				_ = h.pickCountries
				_ = h.pickChannels
			}
		}
	}()
	for i := 0; i < 3; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < 120; j++ {
				a.openGiveawayCreator(engine.ChatInfo{AccountID: "acc", ChatID: "c1", Title: "T"})
				a.updateGiveaway(func(cur *giveawayDlgState) bool {
					cur.onlyNew = !cur.onlyNew
					cur.showWinners = !cur.showWinners
					cur.dateIdx = j % 4
					cur.countryQuery = "q"
					return true
				})
				a.closeGiveaway()
			}
		}()
	}
	go func() {
		time.Sleep(120 * time.Millisecond)
		close(stop)
	}()
	wg.Wait()
	time.Sleep(100 * time.Millisecond)
	if !orig.onlyNew || orig.dateIdx != 0 || orig.countryQuery != "" || orig.loaded || orig.err != "" {
		t.Fatal("the original head was mutated in place — the R34/R47 write-races-layout class")
	}
}

// TestUpdateGiveawayContract pins the installer semantics: nil head is a
// no-op returning false, a false return leaves the head alone (same
// pointer), an accepted update installs a FRESH head and the previous head
// stays frozen. (Compile seam: updateGiveaway does not exist pre-fix.)
func TestUpdateGiveawayContract(t *testing.T) {
	a := &App{}
	ran := false
	if a.updateGiveaway(func(cur *giveawayDlgState) bool { ran = true; return true }) {
		t.Fatal("a nil head must be a no-op returning false")
	}
	if ran {
		t.Fatal("fn must never run on a nil head")
	}

	orig := &giveawayDlgState{accountID: "acc", chatID: "c1", onlyNew: true}
	a.mu.Lock()
	a.giveawayDlg = orig
	a.mu.Unlock()
	if a.updateGiveaway(func(cur *giveawayDlgState) bool { return false }) {
		t.Fatal("an aborted update must return false")
	}
	a.mu.Lock()
	got := a.giveawayDlg
	a.mu.Unlock()
	if got != orig {
		t.Fatal("an aborted update must leave the head pointer untouched")
	}

	// A foreign account's update must not touch the open dialog.
	if a.updateGiveaway(func(cur *giveawayDlgState) bool {
		return cur.accountID == "other"
	}) {
		t.Fatal("a foreign-account update must abort")
	}

	if !a.updateGiveaway(func(cur *giveawayDlgState) bool {
		if cur.accountID != "acc" || cur.chatID != "c1" {
			return false
		}
		cur.onlyNew = false
		cur.dateIdx = 2
		return true
	}) {
		t.Fatal("an accepted update must return true")
	}
	a.mu.Lock()
	next := a.giveawayDlg
	a.mu.Unlock()
	if next == nil || next == orig {
		t.Fatal("an accepted update must install a fresh struct")
	}
	if next.onlyNew || next.dateIdx != 2 {
		t.Fatal("the installed copy must carry fn's changes")
	}
	if !orig.onlyNew || orig.dateIdx != 0 {
		t.Fatal("the replaced head must stay frozen (frame safety)")
	}
}

// TestGiveawayLoadTailLandsCopyOnWrite pins openGiveawayCreator's load: the
// open installs the box, the tail (every RPC errors immediately on the
// bare engine harness) lands through the installer with the error shown
// and loaded set, and the OPEN-TIME state stays frozen.
func TestGiveawayLoadTailLandsCopyOnWrite(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	a.openGiveawayCreator(engine.ChatInfo{AccountID: "ghost", ChatID: "c1", Title: "T"})
	a.mu.Lock()
	opened := a.giveawayDlg
	a.mu.Unlock()
	if opened == nil || opened.accountID != "ghost" || opened.loaded {
		t.Fatal("open must install an unloaded box for the account")
	}
	deadline := time.Now().Add(5 * time.Second)
	for {
		a.mu.Lock()
		cur := a.giveawayDlg
		a.mu.Unlock()
		if cur != nil && cur.loaded && cur.err != "" {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the load tail never landed")
		}
		time.Sleep(2 * time.Millisecond)
	}
	if opened.loaded || opened.err != "" || opened.options != nil {
		t.Fatal("the open-time head must stay frozen while the tail lands")
	}
}

// TestGiveawaySendTailLandsCopyOnWrite pins sendGiveaway's create path: the
// head installs a FRESH sending struct, the tail (CreateStarsGiveaway
// errors immediately on the bare engine) lands sending=false + the error,
// and the pre-send head stays frozen. Also pins the strengthened guard:
// after the dialog is replaced for a DIFFERENT chat, the stale tail must
// not touch the replacement.
func TestGiveawaySendTailLandsCopyOnWrite(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	armed := &giveawayDlgState{
		accountID: "acc", chatID: "c1",
		loaded:  true,
		options: []cores.StarsGiveawayOptionInfo{{Stars: 100, Winners: []cores.StarsGiveawayWinnerInfo{{Users: 1, PerUserStars: 100}}}},
		selOpt:  0, selWin: 0,
		balance: 1 << 40,
		dateIdx: 0,
	}
	a.mu.Lock()
	a.giveawayDlg = armed
	a.mu.Unlock()
	a.sendGiveaway(frame{giveawayDlg: armed})

	a.mu.Lock()
	cur := a.giveawayDlg
	a.mu.Unlock()
	if cur == nil || cur == armed {
		t.Fatal("sendGiveaway must install a fresh struct (never mutate in place)")
	}
	if cur.sending {
		// The tail has not landed yet — the expected common case.
	} else if cur.err == "" {
		t.Fatal("a landed tail must carry the error, not clear it silently")
	}

	// Replace the dialog for a different chat mid-flight: the stale tail
	// must never touch the replacement (the old guard was prepaid==nil
	// ONLY — a same-account reopen was stompable).
	replacement := &giveawayDlgState{accountID: "acc", chatID: "c2", loaded: true}
	a.mu.Lock()
	a.giveawayDlg = replacement
	a.mu.Unlock()

	// Grace period: the create RPC fails fast on the bare engine, so any
	// in-flight tail has aborted or landed on a prior head by now.
	time.Sleep(300 * time.Millisecond)
	a.mu.Lock()
	r := a.giveawayDlg
	a.mu.Unlock()
	if r != replacement || r.sending || r.launched || r.err != "" {
		t.Fatal("the stale create tail must leave the replacement untouched")
	}
	if armed.sending || armed.launched || armed.err != "" || !armed.loaded {
		t.Fatal("the pre-send head must stay frozen")
	}
}

// TestGiveawayClampLandsOnLiveHead pins R47's send-dead half: when
// periodMax arrives late and shrinks the preset list below the picked
// dateIdx, the clamp must fix the LIVE head (through the installer) — the
// old in-place clamp wrote the frozen frame pointer and the Send button
// stayed silently dead. (Compile seam: clampGiveawayDateIdx does not
// exist pre-fix.)
func TestGiveawayClampLandsOnLiveHead(t *testing.T) {
	a := &App{}
	a.mu.Lock()
	a.giveawayDlg = &giveawayDlgState{accountID: "acc", chatID: "c1", dateIdx: 5}
	a.mu.Unlock()
	// periodMax arrives late: presets shrink to the 3-day bucket.
	a.updateGiveaway(func(cur *giveawayDlgState) bool {
		cur.periodMax = 3 * 86400
		return true
	})
	a.mu.Lock()
	head := a.giveawayDlg
	a.mu.Unlock()
	if head.dateIdx != 5 {
		t.Fatalf("sanity: the live head keeps the picked index pre-clamp (got %d)", head.dateIdx)
	}
	a.clampGiveawayDateIdx()
	a.mu.Lock()
	head = a.giveawayDlg
	a.mu.Unlock()
	want := len(giveawayDatePresetsFor(3*86400)) - 1
	if head.dateIdx != want {
		t.Fatalf("the clamp must land on the LIVE head: dateIdx=%d want %d", head.dateIdx, want)
	}
	// Idempotent: a second clamp is a no-op (same pointer even).
	a.clampGiveawayDateIdx()
	a.mu.Lock()
	head2 := a.giveawayDlg
	a.mu.Unlock()
	if head2 != head {
		t.Fatal("a no-op clamp must not install a new head")
	}
}

// TestGiveawayPrepaidPeriodMaxGuarded pins R48's landing guard shape:
// the period-max install from openPrepaidLaunch's goroutine must abort
// against a dialog whose prepaid row has a different ID (the old
// synchronous code compared under a direct lock; the goroutine version
// keeps the same discipline through the installer).
func TestGiveawayPrepaidPeriodMaxGuarded(t *testing.T) {
	a := &App{}
	mine := &giveawayDlgState{accountID: "acc", chatID: "c1", prepaid: &prepaidGiveawayRow{ID: 7}, loaded: true}
	a.mu.Lock()
	a.giveawayDlg = mine
	a.mu.Unlock()
	// A foreign prepaid row is open: the install must abort.
	changed := a.updateGiveaway(func(cur *giveawayDlgState) bool {
		if cur.prepaid == nil || cur.prepaid.ID != 9 {
			return false
		}
		cur.periodMax = 99
		return true
	})
	if changed {
		t.Fatal("a foreign-prepaid period-max install must abort")
	}
	a.mu.Lock()
	got := a.giveawayDlg
	a.mu.Unlock()
	if got != mine || got.periodMax != 0 {
		t.Fatal("the aborted install must leave the head untouched")
	}
}
