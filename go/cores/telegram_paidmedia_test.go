package cores

import (
	"testing"

	"github.com/gotd/td/tg"
)

// Paid media (slice 181, parity row "Paid messages / paid posts"):
// locked messageMediaPaidMedia converts into the paid_* Extra set (star
// price, preview thumb + dims, first-video flag) with the invoice
// attachment; unlocked extended media splices the real photo conversion
// in (paid_unlocked + the price stay).

func paidPreview() *tg.MessageExtendedMediaPreview {
	pv := &tg.MessageExtendedMediaPreview{
		W: 640,
		H: 480,
	}
	pv.SetThumb(&tg.PhotoStrippedSize{Type: "j", Bytes: append([]byte{1}, make([]byte, 32)...)})
	pv.SetVideoDuration(15)
	return pv
}

func paidMediaMessage(paid *tg.MessageMediaPaidMedia) *tg.Message {
	return &tg.Message{
		ID:      950,
		Date:    1726000000,
		Media:   paid,
		Message: "caption text",
	}
}

func TestConvertPaidMediaLocked(t *testing.T) {
	tc := NewTelegramCore(TelegramConfig{})
	m := tc.convertMessage(paidMediaMessage(&tg.MessageMediaPaidMedia{
		StarsAmount:   25,
		ExtendedMedia: []tg.MessageExtendedMediaClass{paidPreview()},
	}))
	if m == nil {
		t.Fatal("convertMessage returned nil")
	}
	if m.Extra["invoice_is_paid_media"] != true {
		t.Errorf("invoice_is_paid_media = %v", m.Extra["invoice_is_paid_media"])
	}
	if v, _ := m.Extra["paid_stars"].(int64); v != 25 {
		t.Errorf("paid_stars = %v (%T)", m.Extra["paid_stars"], m.Extra["paid_stars"])
	}
	if m.Extra["paid_thumb_b64"] == "" {
		t.Error("paid_thumb_b64 missing (preview thumb)")
	}
	if v, _ := m.Extra["paid_w"].(int); v != 640 {
		t.Errorf("paid_w = %v (%T)", m.Extra["paid_w"], m.Extra["paid_w"])
	}
	if v, _ := m.Extra["paid_h"].(int); v != 480 {
		t.Errorf("paid_h = %v (%T)", m.Extra["paid_h"], m.Extra["paid_h"])
	}
	if v, _ := m.Extra["paid_video_duration"].(int); v != 15 {
		t.Errorf("paid_video_duration = %v", m.Extra["paid_video_duration"])
	}
	if v, _ := m.Extra["invoice_first_video"].(bool); !v {
		t.Errorf("invoice_first_video = %v", m.Extra["invoice_first_video"])
	}
	if v, _ := m.Extra["paid_unlocked"].(bool); v {
		t.Error("locked media must not be paid_unlocked")
	}
	// The caption stays the message text.
	if m.Text != "caption text" {
		t.Errorf("text = %q", m.Text)
	}
}

func TestConvertPaidMediaUnlockedPhoto(t *testing.T) {
	tc := NewTelegramCore(TelegramConfig{})
	photo := &tg.MessageMediaPhoto{
		Photo: &tg.Photo{
			ID:            77001,
			AccessHash:    4242,
			FileReference: []byte("ref"),
			Sizes: []tg.PhotoSizeClass{
				&tg.PhotoSize{Type: "x", W: 1280, H: 960, Size: 200000},
			},
		},
	}
	m := tc.convertMessage(paidMediaMessage(&tg.MessageMediaPaidMedia{
		StarsAmount: 25,
		ExtendedMedia: []tg.MessageExtendedMediaClass{
			&tg.MessageExtendedMedia{Media: photo},
		},
	}))
	if m == nil {
		t.Fatal("convertMessage returned nil")
	}
	if v, _ := m.Extra["paid_unlocked"].(bool); !v {
		t.Errorf("paid_unlocked = %v", m.Extra["paid_unlocked"])
	}
	if v, _ := m.Extra["paid_stars"].(int64); v != 25 {
		t.Errorf("paid_stars (kept after unlock) = %v", m.Extra["paid_stars"])
	}
	// The real photo became the attachment (image ref, not the invoice).
	if len(m.Attachments) != 1 {
		t.Fatalf("attachments = %d", len(m.Attachments))
	}
	if m.Attachments[0].ID != "77001" {
		t.Errorf("attachment id = %q (want the photo)", m.Attachments[0].ID)
	}
	if m.Attachments[0].MimeType != "image/jpeg" {
		t.Errorf("attachment mime = %q", m.Attachments[0].MimeType)
	}
	// The photo's download coordinates are cached.
	if tc.getCachedFileHash(77001) != 4242 {
		t.Error("photo file info not cached")
	}
}
