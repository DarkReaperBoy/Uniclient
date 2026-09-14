package cores

// telegram_giveaways.go — slice 212: stars giveaways (tdesktop
// create_giveaway_box + payments_form, read as primary sources).
//
// Surface:
//   - GetStarsGiveawayOptions: payments.getStarsGiveawayOptions → typed
//     winner splits (total stars, per-user stars, yearly boosts).
//   - CreateStarsGiveaway: balance-funded checkout —
//     payments.getPaymentForm(inputInvoiceStars(inputStorePaymentStarsGiveaway))
//     → payments.sendStarsForm, the same flow tdesktop uses on desktop for
//     credits giveaways (store products are the mobile-billing path; the
//     balance path is what a desktop client can actually complete).
//   - LaunchPrepaidGiveaway: payments.launchPrepaidGiveaway with the right
//     purpose (stars when the prepaid entry carries credits, premium
//     otherwise) — replaces the pre-slice-212 map-typed method that only
//     ever built the premium purpose and was wired to nothing.
//
// Pure builders are unit-tested against the wire shapes (tests first).

import (
	"fmt"
	"strconv"

	"github.com/cespare/xxhash/v2"
	"github.com/gotd/td/tg"
)

// giveawayOptionsFromWire normalizes payments.getStarsGiveawayOptions.
// Pure — unit-tested.
func giveawayOptionsFromWire(opts []tg.StarsGiveawayOption) []StarsGiveawayOptionInfo {
	out := make([]StarsGiveawayOptionInfo, 0, len(opts))
	for _, o := range opts {
		item := StarsGiveawayOptionInfo{
			Stars:        o.Stars,
			YearlyBoosts: o.YearlyBoosts,
			Currency:     o.Currency,
			Amount:       o.Amount,
			Extended:     o.Extended,
			Default:      o.Default,
		}
		if p, ok := o.GetStoreProduct(); ok {
			item.StoreProduct = p
		}
		for _, w := range o.Winners {
			item.Winners = append(item.Winners, StarsGiveawayWinnerInfo{
				Users:        w.Users,
				PerUserStars: w.PerUserStars,
				Default:      w.Default,
			})
		}
		out = append(out, item)
	}
	return out
}

// starsGiveawayPurpose maps GiveawayParams onto
// inputStorePaymentStarsGiveaway. Pure — unit-tested.
func starsGiveawayPurpose(boostPeer tg.InputPeerClass, extraPeers []tg.InputPeerClass, p GiveawayParams, totalStars, randomID int64) *tg.InputStorePaymentStarsGiveaway {
	purp := &tg.InputStorePaymentStarsGiveaway{
		Stars:     totalStars,
		BoostPeer: boostPeer,
		Users:     p.WinnerCount,
		RandomID:  randomID,
		UntilDate: p.UntilDate,
	}
	if p.OnlyNew {
		purp.SetOnlyNewSubscribers(true)
	}
	if p.ShowWinners {
		purp.SetWinnersAreVisible(true)
	}
	if p.Prize != "" {
		purp.SetPrizeDescription(p.Prize)
	}
	if len(p.Countries) > 0 {
		purp.SetCountriesISO2(p.Countries)
	}
	if len(extraPeers) > 0 {
		purp.SetAdditionalPeers(extraPeers)
	}
	return purp
}

// starsGiveawayInvoice wraps the purpose in inputInvoiceStars. Pure —
// unit-tested.
func starsGiveawayInvoice(boostPeer tg.InputPeerClass, extraPeers []tg.InputPeerClass, p GiveawayParams, totalStars, randomID int64) tg.InputInvoiceClass {
	return &tg.InputInvoiceStars{
		Purpose: starsGiveawayPurpose(boostPeer, extraPeers, p, totalStars, randomID),
	}
}

// prepaidGiveawayPurpose builds the payments.launchPrepaidGiveaway
// purpose: stars when the prepaid entry carries credits, premium (months)
// otherwise. RandomID = the prepaid giveaway id (tdesktop applyPrepaid
// routes prepaid->id through invoice.randomId). Pure — unit-tested.
func prepaidGiveawayPurpose(boostPeer tg.InputPeerClass, extraPeers []tg.InputPeerClass, p GiveawayParams, credits int64, months int, randomID int64) tg.InputStorePaymentPurposeClass {
	if credits > 0 {
		return starsGiveawayPurpose(boostPeer, extraPeers, p, credits, randomID)
	}
	purp := &tg.InputStorePaymentPremiumGiveaway{
		BoostPeer: boostPeer,
		RandomID:  randomID,
		UntilDate: p.UntilDate,
		Currency:  "USD",
		Amount:    0,
	}
	if p.OnlyNew {
		purp.SetOnlyNewSubscribers(true)
	}
	if p.ShowWinners {
		purp.SetWinnersAreVisible(true)
	}
	if p.Prize != "" {
		purp.SetPrizeDescription(p.Prize)
	}
	if len(p.Countries) > 0 {
		purp.SetCountriesISO2(p.Countries)
	}
	if len(extraPeers) > 0 {
		purp.SetAdditionalPeers(extraPeers)
	}
	return purp
}

// giveawayRandomID ports tdesktop's UniqueIdFromCreditOption: XXH64 over
// (stars + storeProduct + currency + amount + peerID + sessionID). The
// session component is the account's own user id — any stable
// per-login value serves the idempotency role. Pure — unit-tested.
func giveawayRandomID(opt StarsGiveawayOptionInfo, peerID, sessionID int64) int64 {
	h := xxhash.New()
	for _, part := range []string{
		strconv.FormatInt(opt.Stars, 10),
		opt.StoreProduct,
		opt.Currency,
		strconv.FormatInt(opt.Amount, 10),
		strconv.FormatInt(peerID, 10),
		strconv.FormatInt(sessionID, 10),
	} {
		_, _ = h.WriteString(part)
	}
	return int64(h.Sum64())
}

// GetStarsGiveawayOptions lists the giveaway prize options
// (payments.getStarsGiveawayOptions).
func (t *TelegramCore) GetStarsGiveawayOptions() ([]StarsGiveawayOptionInfo, error) {
	api, ctx, err := t.withAPI()
	if err != nil {
		return nil, err
	}
	opts, err := api.PaymentsGetStarsGiveawayOptions(ctx)
	if err != nil {
		return nil, fmt.Errorf("get stars giveaway options: %w", err)
	}
	return giveawayOptionsFromWire(opts), nil
}

// CreateStarsGiveaway funds a stars giveaway from the account's star
// balance: payments.getPaymentForm(inputInvoiceStars) →
// payments.sendStarsForm (tdesktop's desktop credits path). A
// PaymentVerificationNeeded result means the balance is short — an
// honest error pointing at the Stars settings page, never a fake
// checkout.
func (t *TelegramCore) CreateStarsGiveaway(chatID string, opt StarsGiveawayOptionInfo, p GiveawayParams) error {
	api, ctx, err := t.withAPI()
	if err != nil {
		return err
	}
	inputPeer, unlock, perr := t.withPeer(chatID)
	if perr != nil {
		return fmt.Errorf("resolve peer: %w", perr)
	}
	defer unlock()

	// The boost peer must be the channel itself; the access-hash variant
	// of the resolved peer carries the id the hash needs.
	peerID := int64(0)
	if ch, ok := inputPeer.(*tg.InputPeerChannel); ok {
		peerID = ch.ChannelID
	} else if su, ok := inputPeer.(*tg.InputPeerUser); ok {
		peerID = su.UserID
	}
	randomID := giveawayRandomID(opt, peerID, t.selfID)

	var extraPeers []tg.InputPeerClass
	for _, cid := range p.ExtraChats {
		ep, eunlock, eerr := t.withPeer(cid)
		if eerr == nil {
			extraPeers = append(extraPeers, ep)
			eunlock()
		}
	}

	invoice := starsGiveawayInvoice(inputPeer, extraPeers, p, opt.Stars, randomID)
	form, err := api.PaymentsGetPaymentForm(ctx, &tg.PaymentsGetPaymentFormRequest{
		Invoice: invoice,
	})
	if err != nil {
		return err
	}
	var formID int64
	switch f := form.(type) {
	case *tg.PaymentsPaymentFormStars:
		formID = f.FormID
	default:
		return fmt.Errorf("unexpected payment form %T for a stars giveaway", form)
	}
	result, err := api.PaymentsSendStarsForm(ctx, &tg.PaymentsSendStarsFormRequest{
		FormID:  formID,
		Invoice: invoice,
	})
	if err != nil {
		return err
	}
	switch r := result.(type) {
	case *tg.PaymentsPaymentResult:
		return nil
	case *tg.PaymentsPaymentVerificationNeeded:
		_ = r
		return fmt.Errorf("payment needs verification — top up in Settings → Telegram Stars")
	default:
		return fmt.Errorf("unexpected send result %T", result)
	}
}

// LaunchPrepaidGiveaway launches an already-paid giveaway
// (payments.launchPrepaidGiveaway). Credits > 0 selects the stars
// purpose; months > 0 the premium one (PrepaidStarsGiveaway vs
// PrepaidGiveaway entries from the boosts status).
func (t *TelegramCore) LaunchPrepaidGiveaway(chatID string, giveawayID int64, credits int64, months int, p GiveawayParams) error {
	api, ctx, err := t.withAPI()
	if err != nil {
		return err
	}
	inputPeer, unlock, perr := t.withPeer(chatID)
	if perr != nil {
		return fmt.Errorf("resolve peer: %w", perr)
	}
	defer unlock()

	var extraPeers []tg.InputPeerClass
	for _, cid := range p.ExtraChats {
		ep, eunlock, eerr := t.withPeer(cid)
		if eerr == nil {
			extraPeers = append(extraPeers, ep)
			eunlock()
		}
	}

	_, err = api.PaymentsLaunchPrepaidGiveaway(ctx, &tg.PaymentsLaunchPrepaidGiveawayRequest{
		Peer:       inputPeer,
		GiveawayID: giveawayID,
		Purpose:    prepaidGiveawayPurpose(inputPeer, extraPeers, p, credits, months, giveawayID),
	})
	return err
}
