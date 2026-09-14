package cores

// telegram_giveaways_test.go — slice 212 tests-first: stars giveaways —
// the payments.getStarsGiveawayOptions normalization (winner splits,
// yearly boosts, extended/default flags), the
// inputInvoiceStars(inputStorePaymentStarsGiveaway) builder (flag
// mapping), the prepaid-launch purpose builder (stars vs premium), and
// the tdesktop UniqueIdFromCreditOption random-id port.

import (
	"testing"

	"github.com/cespare/xxhash/v2"
	"github.com/gotd/td/tg"
)

func TestGiveawayOptionsFromWire(t *testing.T) {
	opts := []tg.StarsGiveawayOption{
		{
			Stars:        500,
			YearlyBoosts: 4,
			Currency:     "USD",
			Amount:       500,
		},
		{Stars: 100},
	}
	opts[0].SetDefault(true)
	opts[0].Winners = []tg.StarsGiveawayWinnersOption{
		{Users: 1, PerUserStars: 500},
		{Users: 10, PerUserStars: 50},
	}
	opts[0].Winners[1].SetDefault(true)
	opts[1].SetExtended(true)

	out := giveawayOptionsFromWire(opts)
	if len(out) != 2 {
		t.Fatalf("options = %d, want 2", len(out))
	}
	if out[0].Stars != 500 || out[0].YearlyBoosts != 4 || out[0].Currency != "USD" || out[0].Amount != 500 {
		t.Errorf("option 0 fields lost: %+v", out[0])
	}
	if !out[0].Default || out[0].Extended {
		t.Errorf("option 0 flags wrong: %+v", out[0])
	}
	if len(out[0].Winners) != 2 {
		t.Fatalf("winner splits = %d, want 2", len(out[0].Winners))
	}
	if out[0].Winners[0].Users != 1 || out[0].Winners[0].PerUserStars != 500 || out[0].Winners[0].Default {
		t.Errorf("winner 0 wrong: %+v", out[0].Winners[0])
	}
	if out[0].Winners[1].Users != 10 || out[0].Winners[1].PerUserStars != 50 || !out[0].Winners[1].Default {
		t.Errorf("winner 1 wrong: %+v", out[0].Winners[1])
	}
	if !out[1].Extended || out[1].Default {
		t.Errorf("option 1 flags wrong: %+v", out[1])
	}
	if len(giveawayOptionsFromWire(nil)) != 0 {
		t.Error("nil options must stay empty")
	}
}

func TestStarsGiveawayInvoice(t *testing.T) {
	peer := &tg.InputPeerChannel{ChannelID: 42, AccessHash: 7}
	extra := []tg.InputPeerClass{&tg.InputPeerChannel{ChannelID: 9, AccessHash: 1}}
	p := GiveawayParams{
		WinnerCount: 10,
		UntilDate:   1780000000,
		OnlyNew:     true,
		ShowWinners: true,
		Prize:       "extra prize",
	}
	inv := starsGiveawayInvoice(peer, nil, p, 500, 12345)
	si, ok := inv.(*tg.InputInvoiceStars)
	if !ok {
		t.Fatalf("invoice type %T", inv)
	}
	purp, ok := si.Purpose.(*tg.InputStorePaymentStarsGiveaway)
	if !ok {
		t.Fatalf("purpose type %T", si.Purpose)
	}
	if purp.Stars != 500 {
		t.Errorf("total stars = %d, want 500", purp.Stars)
	}
	if purp.Users != 10 {
		t.Errorf("users = %d, want 10", purp.Users)
	}
	if purp.RandomID != 12345 {
		t.Errorf("random id = %d", purp.RandomID)
	}
	if purp.UntilDate != 1780000000 {
		t.Errorf("until date = %d", purp.UntilDate)
	}
	if !purp.OnlyNewSubscribers || !purp.WinnersAreVisible {
		t.Errorf("flags lost: %+v", purp)
	}
	if purp.PrizeDescription != "extra prize" {
		t.Errorf("prize = %q", purp.PrizeDescription)
	}
	if ch, ok := purp.BoostPeer.(*tg.InputPeerChannel); !ok || ch.ChannelID != 42 {
		t.Errorf("boost peer = %T", purp.BoostPeer)
	}

	// Minimal params: no optional flags set.
	inv2 := starsGiveawayInvoice(peer, nil, GiveawayParams{WinnerCount: 1, UntilDate: 100}, 100, 1)
	purp2 := inv2.(*tg.InputInvoiceStars).Purpose.(*tg.InputStorePaymentStarsGiveaway)
	if purp2.OnlyNewSubscribers || purp2.WinnersAreVisible || purp2.PrizeDescription != "" {
		t.Errorf("minimal invoice carries optional fields: %+v", purp2)
	}
	if purp2.Users != 1 {
		t.Errorf("users = %d", purp2.Users)
	}

	// Countries + additional peers ride the flags.
	inv3 := starsGiveawayInvoice(peer, extra, GiveawayParams{
		WinnerCount: 2,
		UntilDate:   100,
		Countries:   []string{"DE", "FR"},
	}, 200, 5)
	purp3 := inv3.(*tg.InputInvoiceStars).Purpose.(*tg.InputStorePaymentStarsGiveaway)
	if len(purp3.CountriesISO2) != 2 || purp3.CountriesISO2[0] != "DE" {
		t.Errorf("countries = %v", purp3.CountriesISO2)
	}
	if len(purp3.AdditionalPeers) != 1 {
		t.Errorf("additional peers = %v", purp3.AdditionalPeers)
	}
}

func TestPrepaidGiveawayPurpose(t *testing.T) {
	peer := &tg.InputPeerChannel{ChannelID: 42, AccessHash: 7}
	p := GiveawayParams{
		WinnerCount: 10,
		UntilDate:   1780000000,
		OnlyNew:     true,
		ShowWinners: true,
	}

	// Credits > 0 → stars purpose.
	purp := prepaidGiveawayPurpose(peer, nil, p, 500, 0, 77)
	sp, ok := purp.(*tg.InputStorePaymentStarsGiveaway)
	if !ok {
		t.Fatalf("prepaid stars purpose type %T", purp)
	}
	if sp.Stars != 500 || sp.RandomID != 77 || sp.Users != 10 {
		t.Errorf("stars purpose fields: %+v", sp)
	}
	if !sp.OnlyNewSubscribers || !sp.WinnersAreVisible {
		t.Errorf("flags lost: %+v", sp)
	}

	// Credits = 0 → premium purpose (months carried by the giveaway id).
	purp2 := prepaidGiveawayPurpose(peer, nil, p, 0, 3, 88)
	pp, ok := purp2.(*tg.InputStorePaymentPremiumGiveaway)
	if !ok {
		t.Fatalf("prepaid premium purpose type %T", purp2)
	}
	if pp.RandomID != 88 || pp.UntilDate != 1780000000 {
		t.Errorf("premium purpose fields: %+v", pp)
	}
	if !pp.OnlyNewSubscribers || !pp.WinnersAreVisible {
		t.Errorf("flags lost: %+v", pp)
	}
	if ch, ok := pp.BoostPeer.(*tg.InputPeerChannel); !ok || ch.ChannelID != 42 {
		t.Errorf("boost peer = %T", pp.BoostPeer)
	}
}

func TestGiveawayRandomID(t *testing.T) {
	opt := StarsGiveawayOptionInfo{Stars: 500, Currency: "USD", Amount: 500}
	a := giveawayRandomID(opt, 42, 1000)
	b := giveawayRandomID(opt, 42, 1000)
	if a != b {
		t.Errorf("random id must be deterministic: %d != %d", a, b)
	}
	c := giveawayRandomID(opt, 43, 1000)
	if a == c {
		t.Error("random id must vary by peer")
	}
	d := giveawayRandomID(StarsGiveawayOptionInfo{Stars: 600}, 42, 1000)
	if a == d {
		t.Error("random id must vary by option")
	}
	if a == 0 {
		t.Error("random id must not be zero")
	}
	// Pins the hash choice: zeroed fields format to "0","","","0","0","0"
	// and the digest must be exactly XXH64 of that concatenation
	// (tdesktop UniqueIdFromCreditOption uses XXH64).
	if uint64(giveawayRandomID(StarsGiveawayOptionInfo{}, 0, 0)) != xxhash.Sum64String("0000") {
		t.Errorf("zeroed random id is not XXH64(\"0000\")")
	}
}
