package gui

import (
	"image"
	"testing"
)

// Real image avatars (AyuGram parity §2): crop math is pure — locked here.

func TestSquareCrop(t *testing.T) {
	// Landscape: crop to centered square of height.
	img := image.NewRGBA(image.Rect(0, 0, 100, 60))
	c := squareCrop(img)
	if c.Bounds().Dx() != 60 || c.Bounds().Dy() != 60 {
		t.Errorf("landscape crop = %v, want 60x60", c.Bounds())
	}

	// Portrait: crop to centered square of width.
	img = image.NewRGBA(image.Rect(0, 0, 40, 90))
	c = squareCrop(img)
	if c.Bounds().Dx() != 40 || c.Bounds().Dy() != 40 {
		t.Errorf("portrait crop = %v, want 40x40", c.Bounds())
	}

	// Square: unchanged bounds size.
	img = image.NewRGBA(image.Rect(0, 0, 50, 50))
	c = squareCrop(img)
	if c.Bounds().Dx() != 50 || c.Bounds().Dy() != 50 {
		t.Errorf("square crop = %v, want 50x50", c.Bounds())
	}

	// Degenerate: empty image returns something drawable-sized without panic.
	img = image.NewRGBA(image.Rect(0, 0, 0, 0))
	c = squareCrop(img)
	if c.Bounds().Dx() < 0 {
		t.Error("degenerate crop panicked bounds")
	}
}
