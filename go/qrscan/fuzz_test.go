package qrscan

// Hostile-input fuzzing for the QR scanner entry points (slice 255):
// scanned images are attacker-supplied — DecodeBytes/DecodeImage must
// never panic (§1.10: fail the scan, never kill the camera session).

import (
	"image"
	"image/color"
	"testing"
)

func FuzzDecodeBytes(f *testing.F) {
	f.Add([]byte{})
	f.Add([]byte{0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A})
	f.Add([]byte("GIF89a"))
	f.Add([]byte{0xFF, 0xD8, 0xFF, 0xE0})
	f.Add([]byte("no image at all"))
	f.Fuzz(func(t *testing.T, data []byte) {
		_, _ = DecodeBytes(data) // error is fine; a panic is not
	})
}

func FuzzDecodeImage(f *testing.F) {
	f.Add(8, 8)
	f.Add(1, 1)
	f.Add(64, 64)
	f.Fuzz(func(t *testing.T, w, h int) {
		if w <= 0 || h <= 0 || w > 256 || h > 256 {
			t.Skip()
		}
		img := image.NewGray(image.Rect(0, 0, w, h))
		for y := 0; y < h; y++ {
			for x := 0; x < w; x++ {
				img.SetGray(x, y, color.Gray{Y: uint8((x*31 + y*17) & 0xFF)})
			}
		}
		_, _ = DecodeImage(img)
	})
}
