package cores

import (
	"fmt"
	"strconv"

	"github.com/cespare/xxhash/v2"
	"github.com/gotd/td/tg"
)

func GiveawayOptionsFromWire(opts []tg.StarsGiveawayOption) []StarsGiveawayOptionInfo {
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

func StarsGiveawayInvoice(boostPeer tg.InputPeerClass, extraPeers []tg.InputPeerClass, p GiveawayParams, totalStars, randomID int64) tg.InputInvoiceClass {
	return &tg.InputInvoiceStars{
		Purpose: starsGiveawayPurpose(boostPeer, extraPeers, p, totalStars, randomID),
	}
}

func PrepaidGiveawayPurpose(boostPeer tg.InputPeerClass, extraPeers []tg.InputPeerClass, p GiveawayParams, credits int64, months int, randomID int64) tg.InputStorePaymentPurposeClass {
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

func GiveawayRandomID(opt StarsGiveawayOptionInfo, peerID, sessionID int64) int64 {
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

func (t *TelegramCore) GetStarsGiveawayOptions() ([]StarsGiveawayOptionInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	opts, err := api.PaymentsGetStarsGiveawayOptions(ctx)
	if err != nil {
		return nil, fmt.Errorf("get stars giveaway options: %w", err)
	}
	return GiveawayOptionsFromWire(opts), nil
}

func (t *TelegramCore) CreateStarsGiveaway(chatID string, opt StarsGiveawayOptionInfo, p GiveawayParams) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	inputPeer, unlock, perr := t.withPeer(chatID)
	if perr != nil {
		return fmt.Errorf("resolve peer: %w", perr)
	}
	defer unlock()

	peerID := int64(0)
	if ch, ok := inputPeer.(*tg.InputPeerChannel); ok {
		peerID = ch.ChannelID
	} else if su, ok := inputPeer.(*tg.InputPeerUser); ok {
		peerID = su.UserID
	}
	randomID := GiveawayRandomID(opt, peerID, t.selfID)

	var extraPeers []tg.InputPeerClass
	for _, cid := range p.ExtraChats {
		ep, eunlock, eerr := t.withPeer(cid)
		if eerr == nil {
			extraPeers = append(extraPeers, ep)
			eunlock()
		}
	}

	invoice := StarsGiveawayInvoice(inputPeer, extraPeers, p, opt.Stars, randomID)
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

func (t *TelegramCore) LaunchPrepaidGiveaway(chatID string, giveawayID int64, credits int64, months int, p GiveawayParams) error {
	api, ctx, err := t.WithAPI()
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
		Purpose:    PrepaidGiveawayPurpose(inputPeer, extraPeers, p, credits, months, giveawayID),
	})
	return err
}
