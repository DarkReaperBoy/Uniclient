package gui

import (
	"image"
	"image/color"

	"rsc.io/qr"
)

// renderQR encodes text into an RGBA image (4px module margin), pure Go.
func renderQR(text string) *image.RGBA {
	code, err := qr.Encode(text, qr.M)
	if err != nil {
		return nil
	}
	const scale = 4
	const quiet = 4 // modules of quiet zone
	n := code.Size
	size := (n + quiet*2) * scale
	img := image.NewRGBA(image.Rect(0, 0, size, size))
	// white background
	white := color.RGBA{R: 255, G: 255, B: 255, A: 255}
	black := color.RGBA{A: 255}
	for y := 0; y < size; y++ {
		for x := 0; x < size; x++ {
			img.SetRGBA(x, y, white)
		}
	}
	for r := 0; r < n; r++ {
		for c := 0; c < n; c++ {
			if code.Black(r, c) {
				for dy := 0; dy < scale; dy++ {
					for dx := 0; dx < scale; dx++ {
						x := (c+quiet)*scale + dx
						y := (r+quiet)*scale + dy
						img.SetRGBA(x, y, black)
					}
				}
			}
		}
	}
	return img
}
