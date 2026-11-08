package tests

import (
	"math"
	"testing"

	. "uniclient/ui/icons"
)

func TestIconCells(t *testing.T) {
	cases := []struct {
		icon         Icon
		maskW, maskH int
		cellW, cellH int
		offX, offY   int
		contours     int
	}{
		{DialogsBot, 16, 11, 17, 14, 1, 3, 4},
		{DialogsChannel, 12, 11, 15, 15, 3, 4, 3},
		{DialogsForum, 19, 10, 20, 14, 1, 4, 6},
		{DialogsSending, 11, 11, 19, 15, 8, 4, 3},
		{DialogsSent, 12, 10, 22, 14, 10, 4, 1},
		{DialogsReceived, 17, 10, 22, 14, 5, 4, 2},
		{DialogsPinned, 20, 20, 20, 20, 0, 0, 1},
		{DialogsMention, 18, 18, 18, 18, 0, 0, 2},
		{DialogsReaction, 18, 18, 18, 18, 0, 0, 1},
		{DialogsPoll, 18, 18, 18, 18, 0, 0, 3},
		{HistorySending, 11, 11, 16, 16, 5, 5, 3},
		{HistorySent, 13, 11, 15, 15, 2, 4, 1},
		{HistoryReceived, 18, 11, 20, 15, 2, 4, 2},
		{HistoryMention, 20, 20, 36, 46, 16, 26, 2},
	}
	for _, c := range cases {
		g, cell := c.icon.Glyph, c.icon.Cell
		if g.W != c.maskW || g.H != c.maskH {
			t.Fatalf("mask size = %dx%d, want %dx%d", g.W, g.H, c.maskW, c.maskH)
		}
		if cell != (Cell{W: c.cellW, H: c.cellH, X: c.offX, Y: c.offY}) {
			t.Fatalf("cell = %+v, want %dx%d at (%d,%d)", cell, c.cellW, c.cellH, c.offX, c.offY)
		}
		if g.W+c.offX != c.cellW || g.H+c.offY != c.cellH {
			t.Fatalf("cell law broken: mask %dx%d + point (%d,%d) must equal canvas %dx%d",
				g.W, g.H, c.offX, c.offY, c.cellW, c.cellH)
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

func TestGlyphBounds(t *testing.T) {
	cases := []struct {
		g                      Glyph
		minX, minY, maxX, maxY float32
		tol                    float32
	}{
		{DialogsSent.Glyph, 0.333, 1.333, 11.667, 10, 0.51},
		{DialogsReceived.Glyph, 0.333, 1.333, 16.667, 10, 0.51},
		{HistorySent.Glyph, 0.333, 1.333, 12.667, 10.667, 0.51},
		{HistoryReceived.Glyph, 0.333, 1.333, 17.667, 10.667, 0.51},
		{DialogsSending.Glyph, 0, 0, 11, 11, 0.51},
		{DialogsPinned.Glyph, 4.667, 4, 16, 15.333, 0.51},
		{DialogsBot.Glyph, 0.333, 0, 15.667, 11, 0.51},
		{DialogsChannel.Glyph, 0.667, 0.333, 11, 11, 0.51},
		{DialogsForum.Glyph, 0, 0, 19, 10, 0.51},
		{DialogsMention.Glyph, 1.986, 1.986, 16.014, 16.014, 0.02},
		{HistoryMention.Glyph, 0, 0, 19, 19.333, 0.02},
	}
	for _, c := range cases {
		minX, minY, maxX, maxY := c.g.Bounds()
		if math.Abs(float64(minX-c.minX)) > float64(c.tol) ||
			math.Abs(float64(minY-c.minY)) > float64(c.tol) ||
			math.Abs(float64(maxX-c.maxX)) > float64(c.tol) ||
			math.Abs(float64(maxY-c.maxY)) > float64(c.tol) {
			t.Fatalf("bounds = (%v,%v)-(%v,%v), want (%v,%v)-(%v,%v) tol %v",
				minX, minY, maxX, maxY, c.minX, c.minY, c.maxX, c.maxY, c.tol)
		}
	}
}

func TestPollBarGeometry(t *testing.T) {
	g := DialogsPoll.Glyph
	if len(g.Paths) != 3 {
		t.Fatalf("poll must trace 3 bars, got %d contours", len(g.Paths))
	}
	bars := []struct{ minX, minY, maxX, maxY float32 }{
		{2.5, 6.917, 5.5, 15.25},
		{7.5, 2.75, 10.5, 15.25},
		{12.5, 9.0, 15.5, 15.25},
	}
	for i, want := range bars {
		minX, minY, maxX, maxY := contourBounds(g.Paths[i])
		if math.Abs(float64(minX-want.minX)) > 0.02 ||
			math.Abs(float64(minY-want.minY)) > 0.02 ||
			math.Abs(float64(maxX-want.maxX)) > 0.02 ||
			math.Abs(float64(maxY-want.maxY)) > 0.02 {
			t.Fatalf("bar %d bounds = (%v,%v)-(%v,%v), want (%v,%v)-(%v,%v)",
				i, minX, minY, maxX, maxY, want.minX, want.minY, want.maxX, want.maxY)
		}
	}
}

func contourBounds(p []Vertex) (minX, minY, maxX, maxY float32) {
	minX, minY = p[0].X, p[0].Y
	maxX, maxY = minX, minY
	for _, v := range p[1:] {
		if v.X < minX {
			minX = v.X
		}
		if v.Y < minY {
			minY = v.Y
		}
		if v.X > maxX {
			maxX = v.X
		}
		if v.Y > maxY {
			maxY = v.Y
		}
	}
	return minX, minY, maxX, maxY
}

func TestTimerSpec(t *testing.T) {
	if TimerPen != 1.5 {
		t.Fatalf("timer pen = %v, want 1.5", TimerPen)
	}
	if TimerFontSize != 9 {
		t.Fatalf("timer font = %d, want 9", TimerFontSize)
	}
	if TimerMaxChars != 2 {
		t.Fatalf("timer max chars = %d, want 2", TimerMaxChars)
	}
	arc := TimerSolidArc(2, 2, 16, 16)
	if len(arc) < 40 {
		t.Fatalf("solid arc too coarse: %d vertices", len(arc))
	}
	minX, minY, maxX, maxY := contourBounds(arc)
	wantMin, wantMax := float32(1.25), float32(10.75)
	if math.Abs(float64(minX-wantMin)) > 0.05 || math.Abs(float64(maxX-wantMax)) > 0.05 {
		t.Fatalf("solid arc x bounds = %v..%v, want %v..%v (left half annulus, cap bulge right)",
			minX, maxX, wantMin, wantMax)
	}
	if math.Abs(float64(minY-1.25)) > 0.05 || math.Abs(float64(maxY-18.75)) > 0.05 {
		t.Fatalf("solid arc y bounds = %v..%v, want 1.25..18.75", minY, maxY)
	}

	dots := TimerDots(2, 2, 16, 16)
	if len(dots) != 9 {
		t.Fatalf("timer dots = %d, want 9", len(dots))
	}
	var rightY float32
	var sawRight bool
	for _, d := range dots {
		if d.R != 0.75 {
			t.Fatalf("dot radius = %v, want 0.75", d.R)
		}
		if d.X < 10-0.001 || d.X > 18.001 {
			t.Fatalf("dot (%v,%v) escapes the right half", d.X, d.Y)
		}
		if d.X > 17.999 {
			rightY, sawRight = d.Y, true
		}
	}
	if !sawRight || math.Abs(float64(rightY-10)) > 0.001 {
		t.Fatalf("a dot must sit at the 3 o'clock point (18,10), got y=%v ok=%v", rightY, sawRight)
	}
	minDotX := dots[0].X
	for _, d := range dots {
		if d.X < minDotX {
			minDotX = d.X
		}
	}
	if math.Abs(float64(minDotX-10.566)) > 0.01 {
		t.Fatalf("innermost dot x = %v, want ~10.566 (pitch 3 on radius 8)", minDotX)
	}
}

func TestGlyphContoursOrientedForHoles(t *testing.T) {
	if len(DialogsSending.Glyph.Paths) < 2 || len(DialogsMention.Glyph.Paths) < 2 || len(DialogsPinned.Glyph.Paths) < 1 || len(HistoryMention.Glyph.Paths) < 2 {
		t.Fatalf("sending needs 2+, mention 2+, pinned 1+ contours for the orientation law")
	}
	solid := signedArea(DialogsSending.Glyph.Paths[0])
	hole := signedArea(DialogsSending.Glyph.Paths[1])
	if solid*hole > 0 {
		t.Fatalf("sending ring and its hole must be wound oppositely (areas %v, %v)", solid, hole)
	}
	pin := signedArea(DialogsPinned.Glyph.Paths[0])
	if pin == 0 {
		t.Fatalf("pinned contour degenerate")
	}
	mentionOuter := signedArea(DialogsMention.Glyph.Paths[0])
	mentionInner := signedArea(DialogsMention.Glyph.Paths[1])
	if mentionOuter*mentionInner > 0 {
		t.Fatalf("mention outer and inner dot must be wound oppositely (areas %v, %v)", mentionOuter, mentionInner)
	}
	historyMentionOuter := signedArea(HistoryMention.Glyph.Paths[0])
	historyMentionInner := signedArea(HistoryMention.Glyph.Paths[1])
	if historyMentionOuter*historyMentionInner > 0 {
		t.Fatalf("history mention ring and its counter must be wound oppositely (areas %v, %v)",
			historyMentionOuter, historyMentionInner)
	}
}

func signedArea(p []Vertex) float32 {
	var a float64
	for i := 0; i < len(p); i++ {
		j := (i + 1) % len(p)
		a += float64(p[i].X)*float64(p[j].Y) - float64(p[j].X)*float64(p[i].Y)
	}
	return float32(a / 2)
}
