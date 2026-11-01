package utils

import (
	"fmt"
	"image"
	"io"
)

func ImageWithinBudget(w, h int, maxPixels int64) bool {
	if w <= 0 || h <= 0 {
		return false
	}
	return int64(w)*int64(h) <= maxPixels
}

func DecodeImageGuarded(r io.Reader, maxPixels int64) (image.Image, string, error) {
	data, err := io.ReadAll(r)
	if err != nil {
		return nil, "", err
	}
	cfg, format, err := image.DecodeConfig(newBytesReader(data))
	if err == nil {
		if !ImageWithinBudget(cfg.Width, cfg.Height, maxPixels) {
			return nil, format, fmt.Errorf("image dimensions exceed budget: %dx%d (%d px > %d)",
				cfg.Width, cfg.Height, cfg.Width*cfg.Height, maxPixels)
		}
	} else if !isUnsupportedConfigErr(err) {
		return nil, format, err
	}
	return image.Decode(newBytesReader(data))
}

func isUnsupportedConfigErr(err error) bool {
	return err != nil && err.Error() == "image: unknown format"
}

func newBytesReader(b []byte) io.Reader { return &sliceReader{b: b} }

type sliceReader struct {
	b []byte
	i int
}

func (s *sliceReader) Read(p []byte) (int, error) {
	if s.i >= len(s.b) {
		return 0, io.EOF
	}
	n := copy(p, s.b[s.i:])
	s.i += n
	return n, nil
}
