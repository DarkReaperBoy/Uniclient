package gui

// gifts_test.go — slice 211 tests: gift picker pure helpers — price
// label, buyability gating (sold out / premium-only / balance), badge
// subtitle, grid row math, and the menu gating.

import (
	"testing"

	"uniclient/cores"
	"uniclient/engine"
)

func TestGiftPriceLabel(t *testing.T) {
	if got := giftPriceLabel(50); got != "50 Stars" {
		t.Errorf("price(50) = %q", got)
	}
	if got := giftPriceLabel(0); got != "0 Stars" {
		t.Errorf("price(0) = %q", got)
	}
}

func TestGiftBuyable(t *testing.T) {
	g := cores.StarGiftItem{ID: 1, Stars: 50}
	if !giftBuyable(g, 50_000_000_000, false) {
		t.Error("exact balance must be buyable")
	}
	if giftBuyable(g, 49_999_999_999, false) {
		t.Error("short balance must not be buyable")
	}
	sold := g
	sold.SoldOut = true
	if giftBuyable(sold, 1_000_000_000_000, false) {
		t.Error("sold-out gift must never be buyable")
	}
	prem := g
	prem.RequirePremium = true
	if giftBuyable(prem, 1_000_000_000_000, false) {
		t.Error("premium-only gift blocked for free accounts")
	}
	if !giftBuyable(prem, 1_000_000_000_000, true) {
		t.Error("premium-only gift buyable with premium")
	}
}

func TestGiftCellSubtitle(t *testing.T) {
	cases := []struct {
		g    cores.StarGiftItem
		want string
	}{
		{cores.StarGiftItem{SoldOut: true}, "Sold out"},
		{cores.StarGiftItem{Limited: true}, "Limited"},
		{cores.StarGiftItem{Limited: true, Remaining: 3, Total: 1000}, "Limited · 3/1000"},
		{cores.StarGiftItem{Birthday: true}, "Birthday"},
		{cores.StarGiftItem{}, ""},
	}
	for _, c := range cases {
		if got := giftCellSubtitle(c.g); got != c.want {
			t.Errorf("subtitle(%+v) = %q, want %q", c.g, got, c.want)
		}
	}
}

func TestGiftGridRows(t *testing.T) {
	if giftGridRows(0) != 0 {
		t.Error("0 gifts = 0 rows")
	}
	if giftGridRows(1) != 1 || giftGridRows(3) != 1 {
		t.Error("1-3 gifts = 1 row")
	}
	if giftGridRows(4) != 2 || giftGridRows(7) != 3 {
		t.Error("rows must ceil-divide by 3")
	}
}

func TestGiftMenuGating(t *testing.T) {
	dm := engine.ChatInfo{Type: engine.ChatTypeDMVal}
	group := engine.ChatInfo{Type: engine.ChatTypeGroupVal}

	// giftsOK → DM menus carry the row.
	if !containsAction(headerMenuItems(dm, false, false, false, true), "gift") {
		t.Error("gift-capable DM menu lacks Send a gift")
	}
	// Non-gift platform → no row (no dead entry, §1.10).
	if containsAction(headerMenuItems(dm, false, false, false, false), "gift") {
		t.Error("non-gift DM menu shows Send a gift")
	}
	// Groups never get it.
	if containsAction(headerMenuItems(group, false, false, false, true), "gift") {
		t.Error("group menu shows Send a gift")
	}
}

func TestGiftAccountOK(t *testing.T) {
	f := frame{accounts: []engine.AccountInfo{
		{ID: "a1", Platform: "telegram"},
		{ID: "a2", Platform: "irc"},
	}}
	if !giftAccountOK(f, "a1") {
		t.Error("telegram account must pass")
	}
	if giftAccountOK(f, "a2") {
		t.Error("irc account must not pass")
	}
	if giftAccountOK(f, "missing") {
		t.Error("missing account must not pass")
	}
}
