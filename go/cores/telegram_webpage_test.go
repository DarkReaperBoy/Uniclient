package cores

// telegram_webpage_test.go — slice 130 tests-first: MessageMediaWebPage
// conversion must export the page photo's download coordinates so the
// engine can pull the full-resolution thumb through the standard media
// pipeline (tdesktop renders the webpage's own Telegram-hosted photo, not
// the site's original image). Before this slice the conversion kept only
// the stripped inline thumb (wp_thumb_b64) — full photos were unreachable.

import (
	"strconv"
	"testing"

	"github.com/gotd/td/tg"
)

// webPagePhotoMessage builds a convertMessage input carrying a webpage
// with a real photo (stripped thumb + full PhotoSize).
func webPagePhotoMessage(photoID int64) *tg.Message {
	photo := &tg.Photo{
		ID:            photoID,
		AccessHash:    photoID * 31,
		FileReference: []byte{9, 9},
		Sizes: []tg.PhotoSizeClass{
			&tg.PhotoStrippedSize{Type: "j", Bytes: []byte{0x01, 0x02, 0x03}},
			&tg.PhotoSize{Type: "x", W: 640, H: 480, Size: 123456},
		},
	}
	// Optional fields ride flag bits — the generated setters keep
	// them consistent (plain struct literals leave Has* unset and the
	// Get* accessors return !ok).
	wp := &tg.WebPage{
		ID:  555,
		URL: "https://example.com/article",
	}
	wp.SetSiteName("Example")
	wp.SetTitle("An article")
	wp.SetDescription("Something happened.")
	wp.SetPhoto(photo)
	return &tg.Message{
		ID:    77,
		Media: &tg.MessageMediaWebPage{Webpage: wp},
	}
}

func TestConvertMessageWebPagePhoto(t *testing.T) {
	tc := NewTelegramCore(TelegramConfig{})
	msg := tc.convertMessage(webPagePhotoMessage(9001))
	if msg == nil {
		t.Fatal("convertMessage returned nil")
	}
	if msg.Extra == nil {
		t.Fatal("no Extra map built")
	}

	// Pre-existing fields stay intact.
	if msg.Extra["wp_url"] != "https://example.com/article" {
		t.Errorf("wp_url = %v", msg.Extra["wp_url"])
	}
	if msg.Extra["wp_thumb_b64"] == "" {
		t.Error("wp_thumb_b64 missing (stripped thumb must stay)")
	}
	if v, _ := msg.Extra["wp_photo_w"].(int); v != 640 {
		t.Errorf("wp_photo_w = %v (%T), want 640", msg.Extra["wp_photo_w"], msg.Extra["wp_photo_w"])
	}
	if v, _ := msg.Extra["wp_photo_h"].(int); v != 480 {
		t.Errorf("wp_photo_h = %v, want 480", msg.Extra["wp_photo_h"])
	}

	// New export: the photo's download coordinates.
	id, ok := msg.Extra["wp_photo_id"].(string)
	if !ok || id != strconv.FormatInt(9001, 10) {
		t.Errorf("wp_photo_id = %v (%T), want \"9001\"", msg.Extra["wp_photo_id"], msg.Extra["wp_photo_id"])
	}
	extra, ok := msg.Extra["wp_photo_extra"].(string)
	if !ok || extra == "" {
		t.Fatalf("wp_photo_extra = %v (%T), want non-empty file extra", msg.Extra["wp_photo_extra"], msg.Extra["wp_photo_extra"])
	}
	// The exported extra must decode back to the photo's access hash +
	// file reference (the standard encodeFileExtra pair).
	hash, ref := decodeFileExtra(extra)
	if hash != 9001*31 {
		t.Errorf("decoded access hash = %d, want %d", hash, 9001*31)
	}
	if len(ref) != 2 || ref[0] != 9 || ref[1] != 9 {
		t.Errorf("decoded file reference = %v, want [9 9]", ref)
	}

	// The conversion must not attach the webpage photo as a message
	// attachment (the card owns the render; the engine's ensure path
	// builds the media row on demand).
	if len(msg.Attachments) != 0 {
		t.Errorf("webpage message gained %d attachments, want 0", len(msg.Attachments))
	}
}

func TestConvertMessageWebPageNoPhoto(t *testing.T) {
	tc := NewTelegramCore(TelegramConfig{})
	msg := tc.convertMessage(&tg.Message{
		ID: 78,
		Media: &tg.MessageMediaWebPage{
			Webpage: &tg.WebPage{
				ID:  556,
				URL: "https://example.com/no-photo",
			},
		},
	})
	if msg == nil {
		t.Fatal("convertMessage returned nil")
	}
	if _, ok := msg.Extra["wp_photo_id"]; ok {
		t.Error("wp_photo_id exported for a photo-less webpage")
	}
	if _, ok := msg.Extra["wp_photo_extra"]; ok {
		t.Error("wp_photo_extra exported for a photo-less webpage")
	}
}
