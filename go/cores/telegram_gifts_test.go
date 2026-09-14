package cores

// telegram_gifts_test.go — slice 211 tests-first: star gifts — the
// payments.getStarGifts catalog normalization (unified starGift: prices,
// limited flags, sticker thumbs), the gift-invoice builder
// (inputInvoiceStarGift flag mapping), and the stars gift-amount options
// normalization.

import (
	"testing"

	"github.com/gotd/td/tg"
)

func giftStickerDoc() *tg.Document {
	return &tg.Document{
		ID:            88001,
		AccessHash:    77,
		FileReference: []byte{9},
		MimeType:      "image/webp",
		Size:          12_000,
		Thumbs: []tg.PhotoSizeClass{
			&tg.PhotoStrippedSize{Type: "j", Bytes: []byte{1, 2, 3}},
		},
		Attributes: []tg.DocumentAttributeClass{
			&tg.DocumentAttributeSticker{Alt: "🎁"},
			&tg.DocumentAttributeFilename{FileName: "gift.webp"},
		},
	}
}

func TestStarGiftsFromWire(t *testing.T) {
	res := &tg.PaymentsStarGifts{
		Gifts: []tg.StarGiftClass{
			&tg.StarGift{
				ID:      5001,
				Sticker: giftStickerDoc(),
				Stars:   50,
			},
			&tg.StarGift{
				ID:      5002,
				Sticker: giftStickerDoc(),
				Stars:   100,
			},
		},
	}
	// limited + sold-out + require-premium flags on the second gift.
	g := res.Gifts[1].(*tg.StarGift)
	g.SetLimited(true)
	g.SetSoldOut(true)
	g.SetRequirePremium(true)
	g.SetAvailabilityTotal(1000)
	g.SetAvailabilityRemains(3)
	g.ConvertStars = 25

	out := starGiftsFromWire(res)
	if len(out) != 2 {
		t.Fatalf("gifts = %d, want 2", len(out))
	}
	first := out[0]
	if first.GiftID != "5001" || first.Stars != 50 || first.NanoStars != 50*1_000_000_000 {
		t.Errorf("first gift wrong: %+v", first)
	}
	if first.ThumbB64 == "" {
		t.Error("sticker thumb not carried (gift rows render it)")
	}
	if first.StickerEmoji != "🎁" {
		t.Errorf("sticker emoji = %q", first.StickerEmoji)
	}
	if first.Limited || first.SoldOut || first.RequirePremium {
		t.Errorf("plain gift carries flags: %+v", first)
	}
	second := out[1]
	if !second.Limited || !second.SoldOut || !second.RequirePremium {
		t.Errorf("flags lost: %+v", second)
	}
	if second.AvailabilityTotal != 1000 || second.AvailabilityRemains != 3 {
		t.Errorf("availability lost: %+v", second)
	}
	if second.ConvertStars != 25 {
		t.Errorf("convert_stars lost: %+v", second)
	}
}

func TestStarGiftsFromWireEmptyAndUnique(t *testing.T) {
	if out := starGiftsFromWire(nil); len(out) != 0 {
		t.Errorf("nil res = %d", len(out))
	}
	// Collectible (unique) gifts are resale objects, not catalog purchases.
	res := &tg.PaymentsStarGifts{Gifts: []tg.StarGiftClass{
		&tg.StarGiftUnique{ID: 99},
	}}
	if out := starGiftsFromWire(res); len(out) != 0 {
		t.Errorf("unique gift leaked into the buy catalog: %d", len(out))
	}
}

func TestStarGiftInvoice(t *testing.T) {
	inv := starGiftInvoice(&tg.InputPeerUser{UserID: 42, AccessHash: 7}, 5001, "happy birthday", true)
	sg, ok := inv.(*tg.InputInvoiceStarGift)
	if !ok {
		t.Fatalf("invoice type %T", inv)
	}
	if sg.GiftID != 5001 {
		t.Errorf("gift id = %d", sg.GiftID)
	}
	if !sg.HideName {
		t.Error("hide_name flag lost")
	}
	peer := sg.Peer.(*tg.InputPeerUser)
	if peer.UserID != 42 || peer.AccessHash != 7 {
		t.Errorf("peer = %+v", peer)
	}
	if sg.Message == nil || len(sg.Message.Entities) != 0 {
		t.Errorf("message = %+v (want empty entities)", sg.Message)
	}

	inv2 := starGiftInvoice(&tg.InputPeerUser{UserID: 1, AccessHash: 1}, 2, "", false)
	sg2 := inv2.(*tg.InputInvoiceStarGift)
	if sg2.HideName || sg2.Message != nil {
		t.Errorf("minimal invoice carries optional fields: %+v", sg2)
	}
}

func TestGiftOptionsFromWire(t *testing.T) {
	opts := []tg.StarsGiftOption{
		{Stars: 100, Currency: "USD", Amount: 200},
		{Stars: 500},
	}
	o := opts[0]
	o.SetStoreProduct("stars_100")
	o.SetExtended(true)
	out := giftOptionsFromWire(opts)
	if len(out) != 2 {
		t.Fatalf("options = %d", len(out))
	}
	if out[0].Stars != 100 || out[0].NanoStars != 100*1_000_000_000 {
		t.Errorf("stars = %+v", out[0])
	}
	if out[0].Currency != "USD" || out[0].Amount != 200 || !out[0].Extended {
		t.Errorf("store fields lost: %+v", out[0])
	}
	if out[1].Currency != "" || out[1].Extended {
		t.Errorf("bare option carries fields: %+v", out[1])
	}
}
