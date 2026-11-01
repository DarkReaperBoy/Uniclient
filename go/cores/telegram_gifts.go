package cores

import (
	"fmt"

	"github.com/gotd/td/tg"
)

func StarGiftsFromWire(res *tg.PaymentsStarGifts) *StarGiftsResult {
	out := &StarGiftsResult{}
	if res == nil {
		return out
	}
	for _, g := range res.Gifts {
		gift, ok := g.(*tg.StarGift)
		if !ok {
			continue
		}
		item := StarGiftItem{
			ID:             gift.ID,
			Stars:          gift.Stars,
			Limited:        gift.Limited,
			SoldOut:        gift.SoldOut,
			Birthday:       gift.Birthday,
			RequirePremium: gift.RequirePremium,
		}
		if v, ok := gift.GetAvailabilityRemains(); ok {
			item.Remaining = v
		}
		if v, ok := gift.GetAvailabilityTotal(); ok {
			item.Total = v
		}
		if gift.ConvertStars != 0 {
			item.ConvertStars = gift.ConvertStars
		}
		if doc, ok := gift.Sticker.(*tg.Document); ok && doc != nil {
			item.ThumbB64 = extractStrippedThumbB64(doc.Thumbs)
			for _, at := range doc.Attributes {
				if st, ok := at.(*tg.DocumentAttributeSticker); ok {
					item.StickerEmoji = st.Alt
				}
			}
		}
		out.Gifts = append(out.Gifts, item)
	}
	return out
}

func GiftOptionsFromWire(opts []tg.StarsGiftOption) []StarsGiftAmount {
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

func StarGiftInvoice(peer tg.InputPeerClass, giftID int64, message string, hideName bool) tg.InputInvoiceClass {
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

func (t *TelegramCore) GetStarGifts() (*StarGiftsResult, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	res, err := api.PaymentsGetStarGifts(ctx, 0)
	if err != nil {
		return nil, fmt.Errorf("get star gifts: %w", err)
	}
	switch r := res.(type) {
	case *tg.PaymentsStarGifts:
		return StarGiftsFromWire(r), nil
	case *tg.PaymentsStarGiftsNotModified:
		return &StarGiftsResult{}, nil
	default:
		return nil, fmt.Errorf("unexpected payments.getStarGifts result %T", res)
	}
}

func (t *TelegramCore) GetStarsGiftOptions(userID string) ([]StarsGiftAmount, error) {
	api, ctx, err := t.WithAPI()
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
	return GiftOptionsFromWire(opts), nil
}

func (t *TelegramCore) SendStarGift(chatID string, giftID int64, message string, hideName bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	inputPeer, unlock, perr := t.withPeer(chatID)
	if perr != nil {
		return fmt.Errorf("resolve peer: %w", perr)
	}
	defer unlock()
	invoice := StarGiftInvoice(inputPeer, giftID, message, hideName)

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
		_ = r
		return fmt.Errorf("payment needs verification — top up in Settings → Telegram Stars")
	default:
		return fmt.Errorf("unexpected sendStarsForm result %T", result)
	}
}
