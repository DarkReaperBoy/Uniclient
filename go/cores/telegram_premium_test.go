package cores

import (
	"testing"

	"github.com/gotd/td/tg"
)

// TestPremiumPlansFromPromo: the help.getPremiumPromo wire payload maps
// onto display-ready plan rows — months, price atoms, payment URL, and
// the current/upgrade flags carried through.
func TestPremiumPlansFromPromo(t *testing.T) {
	promo := &tg.HelpPremiumPromo{
		StatusText: "You are not subscribed",
		PeriodOptions: []tg.PremiumSubscriptionOption{
			{
				Months:              12,
				Currency:            "USD",
				Amount:              3999,
				BotURL:              "https://t.me/premiumbot?start=12",
				Current:             false,
				CanPurchaseUpgrade:  false,
			},
			{
				Months:              1,
				Currency:            "EUR",
				Amount:              449,
				BotURL:              "https://t.me/premiumbot?start=1",
				Current:             true,
				CanPurchaseUpgrade:  true,
			},
		},
	}
	out := premiumPlansFromPromo(promo)
	if out.StatusText != "You are not subscribed" {
		t.Fatalf("StatusText = %q", out.StatusText)
	}
	if len(out.Options) != 2 {
		t.Fatalf("options = %d, want 2", len(out.Options))
	}
	o1 := out.Options[0]
	if o1.Months != 12 || o1.Currency != "USD" || o1.Amount != 3999 {
		t.Fatalf("option 0 = %+v", o1)
	}
	if o1.BotURL != "https://t.me/premiumbot?start=12" {
		t.Fatalf("BotURL = %q", o1.BotURL)
	}
	if o1.Current || o1.CanPurchaseUpgrade {
		t.Fatalf("option 0 flags = current=%v upgrade=%v, want false/false", o1.Current, o1.CanPurchaseUpgrade)
	}
	o2 := out.Options[1]
	if !o2.Current || !o2.CanPurchaseUpgrade {
		t.Fatalf("option 1 flags = current=%v upgrade=%v, want true/true", o2.Current, o2.CanPurchaseUpgrade)
	}
}

// TestPremiumPlansFromPromoEmpty: nil promo / no options → zero-value
// result, no panic.
func TestPremiumPlansFromPromoEmpty(t *testing.T) {
	if out := premiumPlansFromPromo(nil); out.StatusText != "" || len(out.Options) != 0 {
		t.Fatalf("nil promo = %+v", out)
	}
	if out := premiumPlansFromPromo(&tg.HelpPremiumPromo{}); len(out.Options) != 0 {
		t.Fatalf("empty promo options = %d", len(out.Options))
	}
}

// TestPremiumPlansOrderPreserved: the server's option order survives
// (it is already display order).
func TestPremiumPlansOrderPreserved(t *testing.T) {
	promo := &tg.HelpPremiumPromo{
		PeriodOptions: []tg.PremiumSubscriptionOption{
			{Months: 6, Currency: "USD", Amount: 1999},
			{Months: 3, Currency: "USD", Amount: 1099},
		},
	}
	out := premiumPlansFromPromo(promo)
	if out.Options[0].Months != 6 || out.Options[1].Months != 3 {
		t.Fatalf("order changed: %d then %d", out.Options[0].Months, out.Options[1].Months)
	}
}
