package gui

// taskbaricon.go — slice 153: the Windows taskbar overlay tile,
// composed with the tray glyph font. Shared (platform-independent) so
// the composition is unit-testable everywhere; only the HICON
// conversion + COM call live behind the windows build tag.

import (
	"image"
	"image/color"
)

// renderTaskbarOverlayRGBA composes the small overlay tile: rounded
// accent square + the white count digits (the tray glyph font).
func renderTaskbarOverlayRGBA(px int, accent color.NRGBA, count int) *image.NRGBA {
	img := image.NewNRGBA(image.Rect(0, 0, px, px))
	tile := roundedTileMask(px, px/4)
	for y := 0; y < px; y++ {
		for x := 0; x < px; x++ {
			if tile.AlphaAt(x, y).A == 0 {
				continue
			}
			i := img.PixOffset(x, y)
			img.Pix[i] = accent.R
			img.Pix[i+1] = accent.G
			img.Pix[i+2] = accent.B
			img.Pix[i+3] = 0xFF
		}
	}
	if label := trayCountLabel(count); label != "" {
		drawTrayDigits(img, px, label)
	}
	return img
}
