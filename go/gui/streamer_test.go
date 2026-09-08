package gui

import (
	"image/color"
	"testing"
)

// maskColor keeps the row background's hue while making the overlay card
// nearly opaque (AyuGram's blur approximation).
func TestMaskColor(t *testing.T) {
	bg := color.NRGBA{R: 0x1C, G: 0x27, B: 0x33, A: 0xFF}
	got := maskColor(bg)
	if got.R != bg.R || got.G != bg.G || got.B != bg.B {
		t.Errorf("maskColor changed the hue: %+v -> %+v", bg, got)
	}
	if got.A != maskAlpha {
		t.Errorf("maskColor alpha = %d, want %d", got.A, maskAlpha)
	}
	if maskAlpha < 200 {
		t.Errorf("maskAlpha %d too transparent to hide text", maskAlpha)
	}
}
