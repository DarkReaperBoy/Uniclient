package gui

import (
	"image"
	"testing"
)

// Rubber-band selection (slice 84, AyuGram §3): rect math + row hit tests.

func TestRubberSelectRect(t *testing.T) {
	start, cur := image.Pt(100, 50), image.Pt(200, 150)
	r := rubberSelectRect(start, cur)
	if r.Min != image.Pt(100, 50) || r.Max != image.Pt(200, 150) {
		t.Errorf("down-right = %v", r)
	}
	// Reversed drag (up-left): same normalized rect.
	r = rubberSelectRect(cur, start)
	if r.Min != image.Pt(100, 50) || r.Max != image.Pt(200, 150) {
		t.Errorf("up-left = %v", r)
	}
	// Mixed directions.
	r = rubberSelectRect(image.Pt(200, 50), image.Pt(100, 150))
	if r.Min != image.Pt(100, 50) || r.Max != image.Pt(200, 150) {
		t.Errorf("mixed = %v", r)
	}
	// Zero-area tap rect stays empty.
	r = rubberSelectRect(image.Pt(10, 10), image.Pt(10, 10))
	if r.Dx() != 0 || r.Dy() != 0 {
		t.Errorf("tap rect = %v, want zero area", r)
	}
}

func TestRubberHits(t *testing.T) {
	bounds := map[int]image.Rectangle{
		0: {Min: image.Pt(0, 0), Max: image.Pt(300, 60)},
		1: {Min: image.Pt(0, 60), Max: image.Pt(300, 120)},
		2: {Min: image.Pt(0, 120), Max: image.Pt(300, 180)},
	}
	// Rect covering rows 0-1.
	hits := rubberHits(bounds, image.Rectangle{Min: image.Pt(0, 10), Max: image.Pt(300, 100)})
	if len(hits) != 2 {
		t.Fatalf("hits = %v, want rows 0 and 1", hits)
	}
	seen := map[int]bool{}
	for _, h := range hits {
		seen[h] = true
	}
	if !seen[0] || !seen[1] || seen[2] {
		t.Errorf("hits = %v, want {0,1}", hits)
	}

	// Zero-area tap: nothing.
	if hits := rubberHits(bounds, image.Rectangle{Min: image.Pt(5, 5), Max: image.Pt(5, 5)}); len(hits) != 0 {
		t.Errorf("tap hits = %v, want none", hits)
	}
	// Rect outside: nothing.
	if hits := rubberHits(bounds, image.Rectangle{Min: image.Pt(0, 500), Max: image.Pt(300, 600)}); len(hits) != 0 {
		t.Errorf("offscreen hits = %v, want none", hits)
	}
	// Empty bounds map: nothing.
	if hits := rubberHits(nil, image.Rectangle{Min: image.Pt(0, 0), Max: image.Pt(10, 10)}); len(hits) != 0 {
		t.Errorf("empty bounds hits = %v, want none", hits)
	}
}
