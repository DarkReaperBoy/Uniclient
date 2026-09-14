package cores

// telegram_gifts.go — slice 211: star gifts. tdesktop star_gift_box.cpp:
// the gift catalog (payments.getStarGifts), the per-user gift-amount
// options (payments.getStarsGiftOptions), and the balance-funded checkout
// payments.getPaymentForm(inputInvoiceStarGift) → payments.sendStarsForm —
// everything in-app, no external checkout (insufficient balance surfaces
// an honest error pointing at the Stars settings page).

import (
	"fmt"
	"strconv"

	"github.com/gotd/td/tg"
)

// starGiftsFromWire normalizes the payments.getStarGifts catalog into the
// engine-facing shape. Collectible (unique) gifts are resale objects, not
// catalog purchases — excluded. Pure — unit-tested.
func starGiftsFromWire(res *tg.PaymentsStarGifts) []StarGiftInfo {
	if res == nil {
		return nil
	}
	out := make([]StarGiftInfo, 0, len(res.Gifts))
	for _, g := range res.Gifts {
		gift, ok := g.(*tg.StarGift)
		if !ok {
			continue
		}
		info := StarGiftInfo{
			GiftID:         strconv.FormatInt(gift.ID, 10),
			Stars:          gift.Stars,
			NanoStars:      gift.Stars * 1_000_000_000,
			Limited:        gift.Limited,
			SoldOut:        gift.SoldOut,
			Birthday:       gift.Birthday,
			RequirePremium: gift.RequirePremium,
		}
		if v, ok := gift.GetAvailabilityRemains(); ok {
			info.AvailabilityRemains = v
		}
		if v, ok := gift.GetAvailabilityTotal(); ok {
			info.AvailabilityTotal = v
		}
		if gift.ConvertStars != 0 {
			info.ConvertStars = gift.ConvertStars
		}
		if doc, ok := gift.Sticker.(*tg.Document); ok && doc != nil {
			info.ThumbB64 = extractStrippedThumbB64(doc.Thumbs)
			for _, at := range doc.Attributes {
				if st, ok := at.(*tg.DocumentAttributeSticker); ok {
					info.StickerEmoji = st.Alt
				}
			}
		}
		out = append(out, info)
	}
	return out
}

// giftOptionsFromWire normalizes payments.getStarsGiftOptions. Pure —
// unit-tested.
func giftOptionsFromWire(opts []tg.StarsGiftOption) []StarsGiftAmount {
	out := make([]StarsGiftAmount, 0, len(opts))
	for _, o := range opts {
		amt := StarsGiftAmount{
			Stars:     o.Stars,
			NanoStars: o.Stars * 1_000_000_000,
			Currency:  o.Currency,
			Amount:    o.Amount,
			Extended:  o.Extended,
		}
		if p, ok := o.GetStoreProduct(); ok {
			amt.StoreProduct = p
		}
		out = append(out, amt)
	}
	return out
}

// starGiftInvoice builds the inputInvoiceStarGift purchase invoice. Pure —
// unit-tested.
func starGiftInvoice(peer tg.InputPeerClass, giftID int64, message string, hideName bool) tg.InputInvoiceClass {
	inv := &tg.InputInvoiceStarGift{
		Peer:   peer,
		GiftID: giftID,
	}
	if hideName {
		inv.SetHideName(true)
	}
	if message != "" {
		inv.SetMessage(tg.TextWithEntities{Text: message})
	}
	return inv
}

// GetStarGifts returns the purchasable gift catalog (payments.getStarGifts).
// GetStarGifts returns the purchasable gift catalog (payments.getStarGifts).
// Replaces the pre-slice-211 stub that returned empty items and a 6-cap.
func (t *TelegramCore) GetStarGifts() (*StarGiftsResult, error) {
	api, ctx, err := t.withAPI()
	if err != nil {
		return nil, err
	}
	res, err := api.PaymentsGetStarGifts(ctx, 0)
	if err != nil {
		return nil, fmt.Errorf("get star gifts: %w", err)
	}
	switch r := res.(type) {
	case *tg.PaymentsStarGifts:
		return starGiftsFromWire(r), nil
	case *tg.PaymentsStarGiftsNotModified:
		return &StarGiftsResult{}, nil
	default:
		return nil, fmt.Errorf("unexpected payments.getStarGifts result %T", res)
	}
}

// GetStarsGiftOptions lists the star amounts giftable to one user
// (payments.getStarsGiftOptions).
func (t *TelegramCore) GetStarsGiftOptions(userID string) ([]StarsGiftAmount, error) {
	api, ctx, err := t.withAPI()
	if err != nil {
		return nil, err
	}
	inputPeer, unlock, perr := t.withPeer(userID)
	if perr != nil {
		return nil, fmt.Errorf("resolve peer: %w", perr)
	}
	user, ok := inputPeer.(*tg.InputPeerUser)
	unlock()
	if !ok {
		return nil, fmt.Errorf("%w: star gift options need a user peer", ErrNotSupported)
	}
	opts, err := api.PaymentsGetStarsGiftOptions(ctx, &tg.PaymentsGetStarsGiftOptionsRequest{
		UserID: &tg.InputUser{UserID: user.UserID, AccessHash: user.AccessHash},
	})
	if err != nil {
		return nil, err
	}
	return giftOptionsFromWire(opts), nil
}

// SendStarGift purchases one catalog gift for the peer from the account's
// star balance: payments.getPaymentForm(inputInvoiceStarGift) →
// payments.sendStarsForm. Replaces the pre-slice-211 sendPaymentForm
// variant (wrong form type + empty credentials). PaymentVerificationNeeded
// (insufficient balance) is an honest error — the topup lives in the
// Stars settings page.
func (t *TelegramCore) SendStarGift(chatID string, giftID int64, message string, hideName bool) error {
	api, ctx, err := t.withAPI()
	if err != nil {
		return err
	}
	inputPeer, unlock, perr := t.withPeer(chatID)
	if perr != nil {
		return fmt.Errorf("resolve peer: %w", perr)
	}
	defer unlock()
	invoice := starGiftInvoice(inputPeer, giftID, message, hideName)

	form, err := api.PaymentsGetPaymentForm(ctx, &tg.PaymentsGetPaymentFormRequest{
		Invoice: invoice,
	})
	if err != nil {
		return err
	}
	var formID int64
	switch f := form.(type) {
	case *tg.PaymentsPaymentFormStarGift:
		formID = f.FormID
	default:
		return fmt.Errorf("unexpected payment form %T for a star gift", form)
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
		if r.URL != "" {
			return fmt.Errorf("payment needs verification — top up in Settings → Telegram Stars")
		}
		return fmt.Errorf("payment needs verification — top up in Settings → Telegram Stars")
	default:
		return fmt.Errorf("unexpected sendStarsForm result %T", result)
	}
}
