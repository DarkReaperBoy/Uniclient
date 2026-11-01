package gui

import (
	"sync"
	"testing"
	"time"

	"uniclient/cores"
	"uniclient/engine"
)

func TestGiveawayStateIsCopyOnWrite(t *testing.T) {
	a := &App{eng: &engine.Engine{}}
	orig := &giveawayDlgState{accountID: "acc", chatID: "c1", peerTitle: "T", onlyNew: true}
	a.mu.Lock()
	a.giveawayDlg = orig
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
	} else if cur.err == "" {
		t.Fatal("a landed tail must carry the error, not clear it silently")
	}

	replacement := &giveawayDlgState{accountID: "acc", chatID: "c2", loaded: true}
	a.mu.Lock()
	a.giveawayDlg = replacement
	a.mu.Unlock()

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

func TestGiveawayClampLandsOnLiveHead(t *testing.T) {
	a := &App{}
	a.mu.Lock()
	a.giveawayDlg = &giveawayDlgState{accountID: "acc", chatID: "c1", dateIdx: 5}
	a.mu.Unlock()
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
	a.clampGiveawayDateIdx()
	a.mu.Lock()
	head2 := a.giveawayDlg
	a.mu.Unlock()
	if head2 != head {
		t.Fatal("a no-op clamp must not install a new head")
	}
}

func TestGiveawayPrepaidPeriodMaxGuarded(t *testing.T) {
	a := &App{}
	mine := &giveawayDlgState{accountID: "acc", chatID: "c1", prepaid: &prepaidGiveawayRow{ID: 7}, loaded: true}
	a.mu.Lock()
	a.giveawayDlg = mine
	a.mu.Unlock()
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
