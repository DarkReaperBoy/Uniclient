package qrscan

import (
	"bytes"
	"errors"
	"fmt"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"os"

	gozxing "github.com/makiuchi-d/gozxing"
	zxqr "github.com/makiuchi-d/gozxing/qrcode"
	_ "golang.org/x/image/bmp"
	_ "golang.org/x/image/webp"
	"uniclient/utils"
)

var (
	ErrNotImage = errors.New("qrscan: not a decodable image")
	ErrNoQR     = errors.New("qrscan: no QR code found")
)

const qrMaxImagePixels = 40_000_000

func DecodeBytes(data []byte) (string, error) {
	img, _, err := utils.DecodeImageGuarded(bytes.NewReader(data), qrMaxImagePixels)
	if err != nil {
		return "", fmt.Errorf("%w: %v", ErrNotImage, err)
	}
	return DecodeImage(img)
}

func DecodeImage(img image.Image) (string, error) {
	if img == nil {
		return "", fmt.Errorf("%w: nil image", ErrNotImage)
	}
	bm, err := gozxing.NewBinaryBitmapFromImage(img)
	if err != nil {
		return "", fmt.Errorf("%w: %v", ErrNoQR, err)
	}
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

func DecodeFile(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return DecodeBytes(b)
}
