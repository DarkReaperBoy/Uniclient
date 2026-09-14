package gui

// statsearn_test.go — slice 213 tests: pure helpers for the stats
// panel's Earn tab — the graph-map conversion onto StatsGraphData, the
// balance/USD labels, and the withdraw gate.

import (
	"testing"

	"uniclient/cores"
)

func TestEarnChartsFromMaps(t *testing.T) {
	charts := []map[string]interface{}{
		{"title": "Revenue", "type": "StackBar", "data": `{"cols":[...]}`},
		{"title": "Top Hours", "type": "Linear", "data": "{}", "zoom_token": "tok"},
		{"title": "Async", "type": "Linear", "async_token": "async123"},
	}
	out := earnChartsFromMaps(charts)
	if len(out) != 2 {
		t.Fatalf("charts = %d, want 2 (async graphs dropped, matching statsChartCard's honest skip)", len(out))
	}
	if out[0].Title != "Revenue" || out[0].JSON != `{"cols":[...]}` || out[0].Token != "" {
		t.Errorf("chart 0 = %+v", out[0])
	}
	if out[1].Token != "tok" {
		t.Errorf("zoom token lost: %+v", out[1])
	}
	if got := earnChartsFromMaps(nil); len(got) != 0 {
		t.Errorf("nil charts = %d", len(got))
	}
}

func TestEarnBalanceLabels(t *testing.T) {
	st := &cores.StarsRevenueResult{
		AvailableBalance: 2_500_000_000, // 2.5 stars
		OverallRevenue:   10_000_000_000,
		UsdRate:          0.013,
	}
	bal, overall := earnBalanceLabels(st)
	if bal != "2.5 Stars available" {
		t.Errorf("balance label = %q", bal)
	}
	if overall != "10 Stars overall" {
		t.Errorf("overall label = %q", overall)
	}
	if got := earnUsdLabel(st.AvailableBalance, st.UsdRate); got != "≈ $0.03" {
		t.Errorf("usd label = %q", got)
	}
	// Zero rate → no USD line (honest absence).
	if got := earnUsdLabel(100, 0); got != "" {
		t.Errorf("zero-rate usd label = %q", got)
	}
}

func TestEarnWithdrawReady(t *testing.T) {
	base := cores.StarsRevenueResult{
		WithdrawalEnabled: true,
		AvailableBalance:  5_000_000_000, // 5 stars
		WithdrawalMin:     1_000_000_000,
	}
	if !earnWithdrawReady(&base, false) {
		t.Error("funded + enabled withdrawal must be ready")
	}
	disabled := base
	disabled.WithdrawalEnabled = false
	if earnWithdrawReady(&disabled, false) {
		t.Error("disabled withdrawal must not be ready")
	}
	short := base
	short.AvailableBalance = 100
	if earnWithdrawReady(&short, false) {
		t.Error("below-minimum balance must not be ready")
	}
	if earnWithdrawReady(&base, true) {
		t.Error("in-flight withdrawal must not be ready")
	}
	if earnWithdrawReady(nil, false) {
		t.Error("nil stats must not be ready")
	}
}
