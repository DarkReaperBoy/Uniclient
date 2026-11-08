package tests

import (
	"math"
	"testing"

	. "uniclient/ui/icons"
)

func absF(v float32) float32 {
	return float32(math.Abs(float64(v)))
}

func TestComposeIconCells(t *testing.T) {
	cases := []struct {
		icon         Icon
		maskW, maskH int
		cellW, cellH int
		offX, offY   int
		contours     int
	}{
		{ComposeAttach, 18, 21, 40, 40, 11, 9, 1},
		{ComposeSend, 20, 19, 24, 24, 2, 2, 1},
		{ComposeSmile, 10, 9, 40, 40, 15, 17, 3},
	}
	for _, c := range cases {
		g, cell := c.icon.Glyph, c.icon.Cell
		if g.W != c.maskW || g.H != c.maskH {
			t.Fatalf("mask size = %dx%d, want %dx%d", g.W, g.H, c.maskW, c.maskH)
		}
		if cell != (Cell{W: c.cellW, H: c.cellH, X: c.offX, Y: c.offY}) {
			t.Fatalf("cell = %+v, want %dx%d at (%d,%d)", cell, c.cellW, c.cellH, c.offX, c.offY)
		}
		if cell.X+g.W > cell.W || cell.Y+g.H > cell.H {
			t.Fatalf("padded-canvas containment broken: mask %dx%d at (%d,%d) escapes canvas %dx%d",
				g.W, g.H, cell.X, cell.Y, cell.W, cell.H)
		}
		if len(g.Paths) != c.contours {
			t.Fatalf("contour count = %d, want %d", len(g.Paths), c.contours)
		}
		for i, p := range g.Paths {
			if len(p) < 3 {
				t.Fatalf("contour %d has %d vertices, want >= 3", i, len(p))
			}
		}
		minX, minY, maxX, maxY := g.Bounds()
		if minX < -0.01 || minY < -0.01 || maxX > float32(g.W)+0.01 || maxY > float32(g.H)+0.01 {
			t.Fatalf("bounds (%v,%v)-(%v,%v) escape mask %dx%d", minX, minY, maxX, maxY, g.W, g.H)
		}
	}
}

func TestComposeGlyphBounds(t *testing.T) {
	cases := []struct {
		g                      Glyph
		minX, minY, maxX, maxY float32
		tol                    float32
	}{
		{ComposeAttach.Glyph, 0, 0, 18, 20.667, 0.51},
		{ComposeSend.Glyph, 0, 0, 19.333, 19, 0.51},
		{ComposeSmile.Glyph, 0, 0, 9.667, 8.333, 0.51},
	}
	for _, c := range cases {
		minX, minY, maxX, maxY := c.g.Bounds()
		if absF(minX-c.minX) > c.tol || absF(minY-c.minY) > c.tol ||
			absF(maxX-c.maxX) > c.tol || absF(maxY-c.maxY) > c.tol {
			t.Fatalf("bounds = (%v,%v)-(%v,%v), want (%v,%v)-(%v,%v) tol %v",
				minX, minY, maxX, maxY, c.minX, c.minY, c.maxX, c.maxY, c.tol)
		}
	}
}

func TestComposeGlyphWinding(t *testing.T) {
	for _, icon := range []Icon{ComposeAttach, ComposeSend, ComposeSmile} {
		for i, p := range icon.Glyph.Paths {
			a := signedArea(p)
			if a >= 0 {
				t.Fatalf("compose contour %d area %v, want negative (cv2 clockwise solid convention)", i, a)
			}
		}
	}
	if a := signedArea(ComposeAttach.Glyph.Paths[0]); a > -90 || a < -97 {
		t.Fatalf("attach contour area = %v, want ~-93.89 (IoU 0.876 vs @2x)", a)
	}
	if a := signedArea(ComposeSend.Glyph.Paths[0]); a < -172 || a > -162 {
		t.Fatalf("send contour area = %v, want ~-166.61 (IoU 0.854 vs @2x)", a)
	}
	if a := signedArea(ComposeSmile.Glyph.Paths[0]); a < -14 || a > -11 {
		t.Fatalf("smile mouth area = %v, want ~-12.67 (IoU 0.839 vs @2x)", a)
	}
}
