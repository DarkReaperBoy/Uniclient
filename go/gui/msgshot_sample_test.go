package gui

import (
	"image/color"
	"os"
	"testing"

	"uniclient/engine"
)

// TestWriteShotSample renders a representative message shot to
// /tmp/shot-sample.png when UNICLIENT_SHOT_SAMPLE=1 — a manual visual
// verification hook (not part of the regular gate).
func TestWriteShotSample(t *testing.T) {
	if os.Getenv("UNICLIENT_SHOT_SAMPLE") == "" {
		t.Skip("set UNICLIENT_SHOT_SAMPLE=1 to render the sample")
	}
	msg := engine.CachedMessage{
		SenderName:    "Alice Cooper",
		SenderColorID: 3,
		ContentText:   "The **quick** brown fox jumps over the lazy dog. Here is a link and some `code` plus a spoiler!",
		Timestamp:     1737000000,
		EditedAt:      1737000600,
		ReplyPreview:  "Bob: did you see the render test?",
	}
	msg.ContentRich = []byte(`[
		{"type":"bold","offset":4,"length":6},
		{"type":"text_url","offset":45,"length":4,"url":"https://example.com"},
		{"type":"code","offset":60,"length":6},
		{"type":"spoiler","offset":79,"length":7}
	]`)
	p := shotPalette{
		bubble:    color.NRGBA{R: 0x18, G: 0x2C, B: 0x3A, A: 0xFF},
		bubbleOut: color.NRGBA{R: 0x2B, G: 0x52, B: 0x7A, A: 0xFF},
		text:      color.NRGBA{R: 0xF0, G: 0xF4, B: 0xF8, A: 0xFF},
		dim:       color.NRGBA{R: 0x8F, G: 0x9D, B: 0xAB, A: 0xFF},
		accent:    color.NRGBA{R: 0x54, G: 0xA8, B: 0xF0, A: 0xFF},
	}
	img, err := renderMessageShot(msg, p)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	raw, err := shotPNGBytes(img)
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	if err := os.WriteFile("/tmp/shot-sample.png", raw, 0o644); err != nil {
		t.Fatalf("write: %v", err)
	}
	t.Logf("sample written: %dx%d", img.Bounds().Dx(), img.Bounds().Dy())
}
