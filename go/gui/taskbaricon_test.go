package gui

import (
	"image/color"
	"testing"
)

// TestRenderTaskbarOverlayRGBA: the tile composes at sane sizes with
// opaque pixels inside the rounded square and the digits drawn.
func TestRenderTaskbarOverlayRGBA(t *testing.T) {
	accent := color.NRGBA{R: 0x54, G: 0xA8, B: 0xF0, A: 0xFF}
	for _, px := range []int{16, 24, 32} {
		img := renderTaskbarOverlayRGBA(px, accent, 3)
		b := img.Bounds()
		if b.Dx() != px || b.Dy() != px {
			t.Fatalf("bounds = %v for %dpx", b, px)
		}
		// center pixel is opaque accent
		c := img.NRGBAAt(px/2, px/2)
		if c.A != 0xFF || c.R != accent.R || c.G != accent.G || c.B != accent.B {
			t.Fatalf("center = %v", c)
		}
		// corner pixel is transparent (rounded)
		if img.NRGBAAt(0, 0).A != 0 {
			t.Fatalf("corner should be transparent")
		}
	}
	// zero count: no digits but still the tile (used for clearing is
	// skippped before render, the renderer itself stays total)
	img := renderTaskbarOverlayRGBA(24, accent, 0)
	if img.NRGBAAt(12, 12).A != 0xFF {
		t.Fatalf("zero-count tile should still fill")
	}
	// 99+ clamps like the tray badge
	img = renderTaskbarOverlayRGBA(24, accent, 250)
	if img.Bounds().Dx() != 24 {
		t.Fatalf("99+ tile bounds = %v", img.Bounds())
	}
}
