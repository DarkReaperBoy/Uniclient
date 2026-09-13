package cores

import (
	"testing"

	"github.com/gotd/td/tg"
)

// Gift service messages (slice 180, parity row "Gift / star-gift
// messages"): messageActionStarGift / messageActionGiftStars /
// messageActionGiftTon must convert into structured Extra (gift_* fields
// for the GUI's gift card bubble) + real action sentences (the old
// fallback said "performed an action").

func giftStickerDoc() *tg.Document {
	return &tg.Document{
		ID:            555001,
		AccessHash:    9001,
		FileReference: []byte("ref"),
		MimeType:      "image/webp",
		Size:          12345,
		Thumbs: []tg.PhotoSizeClass{
			&tg.PhotoStrippedSize{Type: "j", Bytes: append([]byte{1}, make([]byte, 32)...)},
		},
		Attributes: []tg.DocumentAttributeClass{
			&tg.DocumentAttributeSticker{Alt: "🎁"},
		},
	}
}

func TestConvertServiceStarGift(t *testing.T) {
	tc := NewTelegramCore(TelegramConfig{})
	svc := &tg.MessageService{
		ID:   900,
		Date: 1726000000,
		Action: &tg.MessageActionStarGift{
			Saved: true,
			Gift: &tg.StarGift{
				Stars:   100,
				Limited: true,
				Sticker: giftStickerDoc(),
			},
			Message: tg.TextWithEntities{Text: "Happy birthday!"},
		},
	}
	m := tc.convertServiceMessage(svc)
	if m == nil {
		t.Fatal("convertServiceMessage returned nil")
	}
	if m.Extra["gift_kind"] != "stargift" {
		t.Errorf("gift_kind = %v", m.Extra["gift_kind"])
	}
	if v, _ := m.Extra["gift_stars"].(int64); v != 100 {
		t.Errorf("gift_stars = %v (%T)", m.Extra["gift_stars"], m.Extra["gift_stars"])
	}
	if m.Extra["gift_text"] != "Happy birthday!" {
		t.Errorf("gift_text = %v", m.Extra["gift_text"])
	}
	if m.Extra["gift_thumb_b64"] == "" {
		t.Error("gift_thumb_b64 missing (sticker's stripped thumb)")
	}
	if v, _ := m.Extra["gift_limited"].(bool); !v {
		t.Errorf("gift_limited = %v", m.Extra["gift_limited"])
	}
	if v, _ := m.Extra["gift_saved"].(bool); !v {
		t.Errorf("gift_saved = %v", m.Extra["gift_saved"])
	}
	// The action sentence mentions the gift.
	if m.Text == "" || m.Text == " performed an action" {
		t.Errorf("text = %q", m.Text)
	}
	// The sticker document's download coordinates got cached for the
	// engine's later fetch.
	if tc.getCachedFileHash(555001) != 9001 {
		t.Error("sticker file info not cached")
	}
}

func TestConvertServiceGiftStars(t *testing.T) {
	tc := NewTelegramCore(TelegramConfig{})
	svc := &tg.MessageService{
		ID:   901,
		Date: 1726000000,
		Action: &tg.MessageActionGiftStars{
			Currency: "USD",
			Amount:   199,
			Stars:    75,
		},
	}
	m := tc.convertServiceMessage(svc)
	if m == nil {
		t.Fatal("convertServiceMessage returned nil")
	}
	if m.Extra["gift_kind"] != "stars" {
		t.Errorf("gift_kind = %v", m.Extra["gift_kind"])
	}
	if v, _ := m.Extra["gift_stars"].(int64); v != 75 {
		t.Errorf("gift_stars = %v (%T)", m.Extra["gift_stars"], m.Extra["gift_stars"])
	}
	if m.Text == "" || m.Text == " performed an action" {
		t.Errorf("text = %q", m.Text)
	}
}

func TestConvertServiceGiftTon(t *testing.T) {
	tc := NewTelegramCore(TelegramConfig{})
	svc := &tg.MessageService{
		ID:   902,
		Date: 1726000000,
		Action: &tg.MessageActionGiftTon{
			Currency:       "USD",
			Amount:         299,
			CryptoCurrency: "TON",
			CryptoAmount:   150000000,
		},
	}
	m := tc.convertServiceMessage(svc)
	if m == nil {
		t.Fatal("convertServiceMessage returned nil")
	}
	if m.Extra["gift_kind"] != "ton" {
		t.Errorf("gift_kind = %v", m.Extra["gift_kind"])
	}
	if m.Text == "" || m.Text == " performed an action" {
		t.Errorf("text = %q", m.Text)
	}
}

func TestServiceActionTextGifts(t *testing.T) {
	tc := NewTelegramCore(TelegramConfig{})
	cases := []struct {
		action tg.MessageActionClass
		want   string
	}{
		{&tg.MessageActionStarGift{Gift: &tg.StarGift{Stars: 50, Sticker: giftStickerDoc()}}, "Al sent a gift"},
		{&tg.MessageActionGiftStars{Stars: 75}, "Al sent you 75 Stars"},
		{&tg.MessageActionGiftTon{CryptoCurrency: "TON", CryptoAmount: 5}, "Al sent you a TON gift"},
	}
	for _, c := range cases {
		got := tc.serviceActionText("Al", c.action)
		if got != c.want {
			t.Errorf("text = %q, want %q", got, c.want)
		}
	}
}
