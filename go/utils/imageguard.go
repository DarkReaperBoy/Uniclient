package utils

import (
	"fmt"
	"image"
	"io"
)

// ImageWithinBudget reports whether a header-declared image fits the
// pixel budget: decoders allocate w×h×4 BEFORE reading a single pixel
// (F-74), so a hostile 800-byte PNG/JPEG declaring 65535×65535 asks
// for ~17 GB and OOMs the client. Byte caps don't help — the bomb is
// in the DIMENSIONS.
func ImageWithinBudget(w, h int, maxPixels int64) bool {
	if w <= 0 || h <= 0 {
		return false
	}
	return int64(w)*int64(h) <= maxPixels
}

// DecodeImageGuarded decodes with a DecodeConfig-first dimension
// check (header only — no pixel allocation) so dimension bombs are
// rejected BEFORE the decoder allocates. Formats without a
// DecodeConfig fall back to a plain Decode (documented gap: only the
// config-less decoders bypass the budget; png/jpeg/gif/webp all ship
// DecodeConfig).
func DecodeImageGuarded(r io.Reader, maxPixels int64) (image.Image, string, error) {
	data, err := io.ReadAll(r)
	if err != nil {
		return nil, "", err
	}
	// Sniff the format + read header dimensions cheaply.
	cfg, format, err := image.DecodeConfig(newBytesReader(data))
	if err == nil {
		if !ImageWithinBudget(cfg.Width, cfg.Height, maxPixels) {
			return nil, format, fmt.Errorf("image dimensions exceed budget: %dx%d (%d px > %d)",
				cfg.Width, cfg.Height, cfg.Width*cfg.Height, maxPixels)
		}
	} else if !isUnsupportedConfigErr(err) {
		return nil, format, err
	}
	// Header passed (or no config available) → decode from the buffer.
	return image.Decode(newBytesReader(data))
}

// isUnsupportedConfigErr reports the "this format ships no DecodeConfig"
// case — not a hostile signal, just a missing header reader.
func isUnsupportedConfigErr(err error) bool {
	return err != nil && err.Error() == "image: unknown format"
}

// newBytesReader avoids importing bytes here twice — io.Reader over a
// slice that can be re-read.
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
