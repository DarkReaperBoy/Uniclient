package gui

// premium_test.go — slice 143 (tests-first): the pure halves of the
// Premium settings page — currency exponent + price formatting, plan
// labels, and the limits comparison rows.

import (
        "testing"

        "uniclient/cores"
)

// TestCurrencyExponent: smallest-unit exponents per the Telegram
// currencies table (2 for the vast majority, 0 for the zero-decimal
// currencies, 3 for the triple-decimal ones).
func TestCurrencyExponent(t *testing.T) {
        cases := []struct {
                cur  string
                want int
        }{
                {"USD", 2}, {"EUR", 2}, {"GBP", 2}, {"INR", 2}, {"BRL", 2},
                {"JPY", 0}, {"KRW", 0}, {"VND", 0}, {"CLP", 0},
                {"BHD", 3}, {"IQD", 3}, {"JOD", 3}, {"KWD", 3}, {"LYD", 3}, {"OMR", 3}, {"TND", 3},
                {"", 2},    // unknown → the majority rule
                {"XXX", 2}, // unknown code → 2
        }
        for _, c := range cases {
                if got := currencyExponent(c.cur); got != c.want {
                        t.Errorf("currencyExponent(%q) = %d, want %d", c.cur, got, c.want)
                }
        }
}

// TestFormatPremiumPrice: wire amounts (smallest units) render as human
// prices — trailing zeros trimmed sensibly, zero-decimal currencies
// without a separator, triple-decimal currencies keep three.
func TestFormatPremiumPrice(t *testing.T) {
        cases := []struct {
                cur    string
                amount int64
                want   string
        }{
                {"USD", 3999, "39.99 USD"},
                {"USD", 400, "4 USD"},
                {"USD", 405, "4.05 USD"},
                {"EUR", 449, "4.49 EUR"},
                {"JPY", 500, "500 JPY"},
                {"KRW", 9900, "9900 KRW"},
                {"BHD", 3500, "3.500 BHD"},
                {"INR", 39900, "399 INR"},
        }
        for _, c := range cases {
                if got := formatPremiumPrice(c.cur, c.amount); got != c.want {
                        t.Errorf("formatPremiumPrice(%q,%d) = %q, want %q", c.cur, c.amount, got, c.want)
                }
        }
}

// TestPremiumPlanLabel: duration labels.
func TestPremiumPlanLabel(t *testing.T) {
        cases := []struct {
                months int
                want   string
        }{
                {1, "1 month"},
                {3, "3 months"},
                {6, "6 months"},
                {12, "12 months"},
                {0, "0 months"},
        }
        for _, c := range cases {
                if got := premiumPlanLabel(c.months); got != c.want {
                        t.Errorf("premiumPlanLabel(%d) = %q, want %q", c.months, got, c.want)
                }
        }
}

// TestPremiumLimitRows: the limits map renders as comparison rows —
// known keys become labeled rows in a fixed order; unknown keys are
// skipped; the free/premium values come straight through.
func TestPremiumLimitRows(t *testing.T) {
        limits := map[string]int{
                "free_limit":               10,
                "premium_limit":            20,
                "chats_per_folder_free":    100,
                "chats_per_folder_premium": 200,
                "shared_folders_free":      2,
                "shared_folders_premium":   20,
                "links_per_folder_free":    3,
                "links_per_folder_premium": 20,
                "unknown_thing":            7,
        }
        rows := premiumLimitRows(limits)
        if len(rows) != 4 {
                t.Fatalf("rows = %d, want 4 (unknown keys skipped)", len(rows))
        }
        if rows[0].label != "Chat folders" || rows[0].free != 10 || rows[0].premium != 20 {
                t.Fatalf("row 0 = %+v", rows[0])
        }
        if rows[1].label != "Chats per folder" || rows[1].free != 100 || rows[1].premium != 200 {
                t.Fatalf("row 1 = %+v", rows[1])
        }
        if rows[2].label != "Shared folders" || rows[2].free != 2 || rows[2].premium != 20 {
                t.Fatalf("row 2 = %+v", rows[2])
        }
        if rows[3].label != "Links per folder" || rows[3].free != 3 || rows[3].premium != 20 {
                t.Fatalf("row 3 = %+v", rows[3])
        }

        // Missing keys degrade to zeros, never phantom rows.
        rows = premiumLimitRows(map[string]int{"free_limit": 5})
        if len(rows) != 4 {
                t.Fatalf("degraded rows = %d, want 4", len(rows))
        }
        if rows[0].free != 5 || rows[0].premium != 0 {
                t.Fatalf("degraded row 0 = %+v", rows[0])
        }
}

// TestPremiumPlanSubtitle: the plan row's price subtitle.
func TestPremiumPlanSubtitle(t *testing.T) {
        p := cores.PremiumPlanOption{Months: 12, Currency: "USD", Amount: 3999}
        if got := premiumPlanSubtitle(p); got != "39.99 USD" {
                t.Fatalf("subtitle = %q, want 39.99 USD", got)
        }
}
