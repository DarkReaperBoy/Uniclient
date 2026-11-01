package gui

import (
	"image/color"
	"testing"
)

func TestRenderTaskbarOverlayRGBA(t *testing.T) {
	accent := color.NRGBA{R: 0x54, G: 0xA8, B: 0xF0, A: 0xFF}
	for _, px := range []int{16, 24, 32} {
		img := renderTaskbarOverlayRGBA(px, accent, 3)
		b := img.Bounds()
		if b.Dx() != px || b.Dy() != px {
			t.Fatalf("bounds = %v for %dpx", b, px)
		}
		c := img.NRGBAAt(px/2, px/2)
		if c.A != 0xFF || c.R != accent.R || c.G != accent.G || c.B != accent.B {
			t.Fatalf("center = %v", c)
		}
		if img.NRGBAAt(0, 0).A != 0 {
			t.Fatalf("corner should be transparent")
		}
	}
	img := renderTaskbarOverlayRGBA(24, accent, 0)
	if img.NRGBAAt(12, 12).A != 0xFF {
		t.Fatalf("zero-count tile should still fill")
	}
	img = renderTaskbarOverlayRGBA(24, accent, 250)
	if img.Bounds().Dx() != 24 {
		t.Fatalf("99+ tile bounds = %v", img.Bounds())
	}
}
