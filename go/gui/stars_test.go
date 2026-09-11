package gui

// stars_test.go — slice 144 (tests-first): the pure halves of the Stars
// page — nanostar→display formatting, amount labels, row titles and
// filter tabs.

import (
	"testing"

	"uniclient/cores"
)

// TestFormatStars: nanostars render as trimmed decimals — whole stars
// without a separator, fractional with trailing zeros trimmed.
func TestFormatStars(t *testing.T) {
	cases := []struct {
		nano int64
		want string
	}{
		{123_000_000_000, "123"},
		{0, "0"},
		{1_000_000_000, "1"},
		{12_500_000_000, "12.5"},
		{100_000_000, "0.1"},
		{1_000_000, "0.001"},
		{-12_500_000_000, "-12.5"},
	}
	for _, c := range cases {
		if got := formatStars(c.nano); got != c.want {
			t.Errorf("formatStars(%d) = %q, want %q", c.nano, got, c.want)
		}
	}
}

// TestStarsTxnAmountLabel: incoming amounts get a +, spending keeps the
// minus, refunds say refunded.
func TestStarsTxnAmountLabel(t *testing.T) {
	cases := []struct {
		txn  cores.StarsTxn
		want string
	}{
		{cores.StarsTxn{NanoStars: 25_000_000_000}, "+25"},
		{cores.StarsTxn{NanoStars: -50_000_000_000}, "-50"},
		{cores.StarsTxn{NanoStars: 12_500_000_000}, "+12.5"},
		{cores.StarsTxn{NanoStars: -100_000_000}, "-0.1"},
	}
	for _, c := range cases {
		if got := starsTxnAmountLabel(c.txn); got != c.want {
			t.Errorf("starsTxnAmountLabel(%+v) = %q, want %q", c.txn.NanoStars, got, c.want)
		}
	}
}

// TestStarsTxnTitle: the row title's priority — product title first,
// then the counterparty's name, then the honest fallback.
func TestStarsTxnTitle(t *testing.T) {
	cases := []struct {
		txn  cores.StarsTxn
		want string
	}{
		{cores.StarsTxn{Title: "Boost a channel", PeerTitle: "Durov's Channel"}, "Boost a channel"},
		{cores.StarsTxn{PeerTitle: "Alice"}, "Alice"},
		{cores.StarsTxn{}, "Stars"},
	}
	for _, c := range cases {
		if got := starsTxnTitle(c.txn); got != c.want {
			t.Errorf("starsTxnTitle = %q, want %q", got, c.want)
		}
	}
}

// TestStarsTxnStatusChip: refund/pending/failed pick their chip label,
// plain transactions have none.
func TestStarsTxnStatusChip(t *testing.T) {
	if got := starsTxnStatusChip(cores.StarsTxn{Refund: true}); got != "Refunded" {
		t.Fatalf("refund chip = %q", got)
	}
	if got := starsTxnStatusChip(cores.StarsTxn{Pending: true, Failed: true}); got != "Failed" {
		t.Fatalf("failed beats pending: %q", got)
	}
	if got := starsTxnStatusChip(cores.StarsTxn{Pending: true}); got != "Pending" {
		t.Fatalf("pending chip = %q", got)
	}
	if got := starsTxnStatusChip(cores.StarsTxn{}); got != "" {
		t.Fatalf("no chip for plain txn, got %q", got)
	}
}

// TestStarsFilterTabs: the filter tabs and their wire flags.
func TestStarsFilterTabs(t *testing.T) {
	tabs := starsFilterTabs()
	if len(tabs) != 3 {
		t.Fatalf("tabs = %d, want 3", len(tabs))
	}
	if tabs[0].label != "All" || tabs[1].label != "Incoming" || tabs[2].label != "Outgoing" {
		t.Fatalf("tab labels = %+v", tabs)
	}
	if tabs[0].filter != "" || tabs[1].filter != "in" || tabs[2].filter != "out" {
		t.Fatalf("tab filters = %+v", tabs)
	}
}
