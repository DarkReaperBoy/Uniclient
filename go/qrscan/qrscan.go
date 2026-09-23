// Package qrscan decodes QR codes from image bytes — the desktop-shaped
// half of Telegram's invite-QR flow (matrix row 306): a user picks a QR
// image file (screenshot, download) and the app reads the link it holds.
//
// The decoder is github.com/makiuchi-d/gozxing (MIT, pure Go). It was
// chosen by measurement, not reputation: a cross-encoder bench of six
// pure-Go decoders scored gozxing 96/96 exact payload matches across
// four independent encoders and four image variants (rotation, JPEG
// artifacts), while two of the others returned wrong payloads outright.
// research/qr_decoder.md holds the method and the full table.
//
// Every fixture the tests decode was rendered by a FOREIGN encoder, so
// the decoder never grades symbols it produced itself.
package qrscan

import (
	"bytes"
	"errors"
	"fmt"
	"image"
	_ "image/gif" // registered for DecodeBytes: users pick any image
	_ "image/jpeg"
	_ "image/png"
	"os"

	gozxing "github.com/makiuchi-d/gozxing"
	zxqr "github.com/makiuchi-d/gozxing/qrcode"
	_ "golang.org/x/image/bmp" // same reason: Telegram screenshots come as bmp/webp too
	_ "golang.org/x/image/webp"
)

// Sentinel errors the GUI maps to distinct, honest copy (§1.10).
var (
	// ErrNotImage: the bytes are not a decodable PNG/JPEG/GIF image.
	ErrNotImage = errors.New("qrscan: not a decodable image")
	// ErrNoQR: a valid image that contains no readable QR symbol.
	ErrNoQR = errors.New("qrscan: no QR code found")
)

// DecodeBytes decodes the first QR symbol found in an image file's bytes.
// Wraps ErrNotImage (image.Decode failed) or ErrNoQR (no symbol read).
func DecodeBytes(data []byte) (string, error) {
	img, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return "", fmt.Errorf("%w: %v", ErrNotImage, err)
	}
	return DecodeImage(img)
}

// DecodeImage decodes the first QR symbol in an already-loaded image.
func DecodeImage(img image.Image) (string, error) {
	if img == nil {
		return "", fmt.Errorf("%w: nil image", ErrNotImage)
	}
	bm, err := gozxing.NewBinaryBitmapFromImage(img)
	if err != nil {
		return "", fmt.Errorf("%w: %v", ErrNoQR, err)
	}
	// nil hints = the exact configuration the selection bench scored
	// 96/96 under; do not tune it without re-running that bench.
	res, err := zxqr.NewQRCodeReader().Decode(bm, nil)
	if err != nil {
		return "", fmt.Errorf("%w: %v", ErrNoQR, err)
	}
	text := res.GetText()
	if text == "" {
		return "", ErrNoQR
	}
	return text, nil
}

// DecodeFile reads path and decodes the first QR symbol in it.
func DecodeFile(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return DecodeBytes(b)
}
