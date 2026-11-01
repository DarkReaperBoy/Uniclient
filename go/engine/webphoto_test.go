package engine

import (
	"testing"
)

func TestParseWebPagePhoto(t *testing.T) {
	raw := []byte(`{"extra":{
		"wp_url":"https://example.com/a",
		"wp_thumb_b64":"QUJD",
		"wp_photo_id":"9001",
		"wp_photo_extra":"279031:OQ==",
		"wp_photo_w":640,
		"wp_photo_h":480
	}}`)
	ph, ok := parseWebPagePhoto(raw)
	if !ok {
		t.Fatal("webpage photo not parsed")
	}
	if ph.PhotoID != "9001" || ph.Extra != "279031:OQ==" {
		t.Errorf("photo id/extra = %q / %q", ph.PhotoID, ph.Extra)
	}
	if ph.ThumbB64 != "QUJD" {
		t.Errorf("thumb b64 = %q", ph.ThumbB64)
	}
	if ph.Width != 640 || ph.Height != 480 {
		t.Errorf("w/h = %d/%d, want 640/480", ph.Width, ph.Height)
	}

	if _, ok := parseWebPagePhoto([]byte(`{"extra":{"wp_url":"https://x.com"}}`)); ok {
		t.Error("photo-less webpage parsed as having a photo")
	}
	if _, ok := parseWebPagePhoto([]byte(`{"extra":{"dice_emoji":"🎲"}}`)); ok {
		t.Error("non-webpage parsed as webpage photo")
	}
	if _, ok := parseWebPagePhoto(nil); ok {
		t.Error("nil raw parsed")
	}
	if _, ok := parseWebPagePhoto([]byte(`not json`)); ok {
		t.Error("garbage parsed")
	}
	if _, ok := parseWebPagePhoto([]byte(`{"extra":{"wp_url":"u","wp_photo_id":"5"}}`)); ok {
		t.Error("photo without extra parsed as usable")
	}
}

func TestWebPagePhotoFileName(t *testing.T) {
	if got := webPagePhotoFileName("1234567"); got != "webpage_1234567.jpg" {
		t.Errorf("webPagePhotoFileName = %q", got)
	}
}
