package gui

// giveaways_test.go — slice 212 tests: pure helpers for the giveaway
// creation box (labels, date presets + 5-minute rounding, send gate) and
// the prepaid-giveaway rows parsed out of the boost status map.

import (
	"testing"
	"time"

	"uniclient/cores"
)

func TestGiveawayOptionLabel(t *testing.T) {
	if got := giveawayOptionLabel(cores.StarsGiveawayOptionInfo{Stars: 500}); got != "500 Stars" {
		t.Errorf("label = %q", got)
	}
	if got := giveawayOptionLabel(cores.StarsGiveawayOptionInfo{Stars: 500, YearlyBoosts: 4}); got != "500 Stars · +4 boosts/yr" {
		t.Errorf("label with boosts = %q", got)
	}
	if got := giveawayOptionLabel(cores.StarsGiveawayOptionInfo{Stars: 500, Default: true}); got != "500 Stars · Default" {
		t.Errorf("label with default = %q", got)
	}
}

func TestGiveawayWinnerLabel(t *testing.T) {
	if got := giveawayWinnerLabel(cores.StarsGiveawayWinnerInfo{Users: 10, PerUserStars: 50}); got != "10 winners · 50 Stars each" {
		t.Errorf("winner label = %q", got)
	}
	if got := giveawayWinnerLabel(cores.StarsGiveawayWinnerInfo{Users: 1, PerUserStars: 500}); got != "1 winner · 500 Stars each" {
		t.Errorf("single winner label = %q", got)
	}
}

func TestGiveawayDatePresets(t *testing.T) {
	presets := giveawayDatePresets()
	if len(presets) != 4 {
		t.Fatalf("presets = %d, want 4", len(presets))
	}
	if presets[0].Days != 3 || presets[0].Label != "in 3 days" {
		t.Errorf("first preset = %+v (tdesktop default is 3 days)", presets[0])
	}
	if presets[3].Days != 30 || presets[3].Label != "in 30 days" {
		t.Errorf("last preset = %+v", presets[3])
	}
}

func TestGiveawayUntilDate(t *testing.T) {
	// tdesktop ThreeDaysAfterToday: +3 days, then round minutes up to a
	// 5-minute boundary.
	now := time.Date(2026, 9, 14, 12, 3, 30, 0, time.UTC)
	got := giveawayUntilDate(3, now)
	want := time.Date(2026, 9, 17, 12, 5, 0, 0, time.UTC).Unix()
	if got != want {
		t.Errorf("until = %d, want %d", got, want)
	}
	// Already on a boundary → unchanged minutes.
	now2 := time.Date(2026, 9, 14, 12, 0, 0, 0, time.UTC)
	got2 := giveawayUntilDate(7, now2)
	want2 := time.Date(2026, 9, 21, 12, 0, 0, 0, time.UTC).Unix()
	if got2 != want2 {
		t.Errorf("until = %d, want %d", got2, want2)
	}
	// 12:04:59 → 12:05.
	now3 := time.Date(2026, 9, 14, 12, 4, 59, 0, time.UTC)
	got3 := giveawayUntilDate(3, now3)
	want3 := time.Date(2026, 9, 17, 12, 5, 0, 0, time.UTC).Unix()
	if got3 != want3 {
		t.Errorf("until = %d, want %d", got3, want3)
	}
}

func TestPrepaidFromBoostStatus(t *testing.T) {
	st := map[string]interface{}{
		"prepaid_giveaways": []interface{}{
			map[string]interface{}{"id": int64(11), "credits": 500, "quantity": 10, "boosts": 20, "date": 1780000000},
			map[string]interface{}{"id": int64(22), "months": 3, "quantity": 10, "date": 1780000000},
			map[string]interface{}{"id": int64(33)},
		},
	}
	rows := prepaidFromBoostStatus(st)
	if len(rows) != 3 {
		t.Fatalf("rows = %d, want 3", len(rows))
	}
	if rows[0].ID != 11 || rows[0].Credits != 500 || rows[0].Quantity != 10 || rows[0].Boosts != 20 {
		t.Errorf("stars row = %+v", rows[0])
	}
	if rows[1].ID != 22 || rows[1].Credits != 0 || rows[1].Months != 3 || rows[1].Quantity != 10 {
		t.Errorf("premium row = %+v", rows[1])
	}
	if rows[2].ID != 33 {
		t.Errorf("bare row = %+v", rows[2])
	}

	// Absent / typed-wrong fields stay honest.
	if got := prepaidFromBoostStatus(map[string]interface{}{}); len(got) != 0 {
		t.Errorf("empty status = %d rows", len(got))
	}
	if got := prepaidFromBoostStatus(nil); len(got) != 0 {
		t.Errorf("nil status = %d rows", len(got))
	}
}

func TestPrepaidRowSub(t *testing.T) {
	stars := prepaidGiveawayRow{ID: 11, Credits: 500, Quantity: 10, Boosts: 20, Date: 1780000000}
	if got := prepaidRowTitle(stars); got != "Prepaid Stars giveaway · 500 Stars" {
		t.Errorf("stars title = %q", got)
	}
	prem := prepaidGiveawayRow{ID: 22, Months: 3, Quantity: 10}
	if got := prepaidRowTitle(prem); got != "Prepaid Premium giveaway · 3 months" {
		t.Errorf("premium title = %q", got)
	}
	if got := prepaidRowSub(stars); got != "10 winners · 20 boosts" {
		t.Errorf("stars sub = %q", got)
	}
	if got := prepaidRowSub(prem); got != "10 winners" {
		t.Errorf("premium sub = %q", got)
	}
}

func TestGiveawaySendGate(t *testing.T) {
	opts := []cores.StarsGiveawayOptionInfo{
		{Stars: 500, Winners: []cores.StarsGiveawayWinnerInfo{{Users: 10, PerUserStars: 50}}},
	}
	// Balance short → disabled (honest, like the gift picker).
	st := &giveawayDlgState{loaded: true, options: opts, selOpt: 0, selWin: 0, balance: 100, dateIdx: 0}
	if giveawaySendEnabled(st) {
		t.Error("balance-short giveaway must be disabled")
	}
	// Balance covers the total → enabled.
	st.balance = 500 * 1_000_000_000
	if !giveawaySendEnabled(st) {
		t.Error("funded giveaway must be enabled")
	}
	// Not loaded → disabled.
	st.loaded = false
	if giveawaySendEnabled(st) {
		t.Error("unloaded giveaway must be disabled")
	}
	// Sending in flight → disabled.
	st.loaded = true
	st.sending = true
	if giveawaySendEnabled(st) {
		t.Error("in-flight giveaway must be disabled")
	}
}
