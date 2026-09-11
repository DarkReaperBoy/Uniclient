package gui

// trayicon.go — slice 137: the system-tray icon renderer (pure Go).
//
// The tray icon is generated programmatically (no binary assets in the
// repo): a rounded-square brand tile in the active accent color, an
// original speech-bubble mark, and — when there are unread messages — a
// counter badge in the bottom-right corner. The badge digits come from a
// tiny built-in 3x5 pixel font scaled to the icon size, which keeps the
// render deterministic and dependency-free.

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"math"
)

// trayCountLabel formats the badge counter (99+ past two digits). Pure.
func trayCountLabel(n int) string {
	switch {
	case n <= 0:
		return ""
	case n < 10:
		return string(rune('0' + n))
	case n < 100:
		return string(rune('0'+n/10)) + string(rune('0'+n%10))
	default:
		return "99+"
	}
}

// trayGlyphs is a 3x5 pixel font for the badge text (row-major, high bit
// = leftmost column). Digits plus '+' — the label never carries other
// characters.
var trayGlyphs = map[byte][5]uint8{
	'0': {0b111, 0b101, 0b101, 0b101, 0b111},
	'1': {0b010, 0b110, 0b010, 0b010, 0b111},
	'2': {0b111, 0b001, 0b111, 0b100, 0b111},
	'3': {0b111, 0b001, 0b111, 0b001, 0b111},
	'4': {0b101, 0b101, 0b111, 0b001, 0b001},
	'5': {0b111, 0b100, 0b111, 0b001, 0b111},
	'6': {0b111, 0b100, 0b111, 0b101, 0b111},
	'7': {0b111, 0b001, 0b010, 0b010, 0b010},
	'8': {0b111, 0b101, 0b111, 0b101, 0b111},
	'9': {0b111, 0b101, 0b111, 0b001, 0b111},
	'+': {0b000, 0b010, 0b111, 0b010, 0b000},
}

// renderTrayIconPNG draws the tray icon: rounded accent tile, white
// speech-bubble mark, optional unread badge. Returns PNG bytes.
func renderTrayIconPNG(px int, accent color.NRGBA, count int) []byte {
	if px < 16 {
		px = 16
	}
	img := image.NewNRGBA(image.Rect(0, 0, px, px))
	f := float64(px)

	// Rounded-square tile: corner radius ≈ 22% of the size (Material
	// launcher-icon geometry).
	tile := roundedTileMask(px, int(math.Round(f*0.22)))

	// Slightly darkened accent for the tile bottom (subtle depth without
	// a gradient library): blend accent toward black by 18%.
	dark := shade(accent, 0.82)

	// The brand mark: a speech bubble — a rounded-rect body with a tail
	// triangle pointing down-left, drawn in white on the tile.
	bubble := bubbleMask(px)

	// Badge (count > 0): filled circle with white digits, anchored in the
	// bottom-right corner, slightly overlapping the tile edge.
	label := trayCountLabel(count)
	var badge *image.Alpha
	if label != "" {
		badge = badgeMask(px, len(label))
	}

	for y := 0; y < px; y++ {
		for x := 0; x < px; x++ {
			var c color.NRGBA
			switch {
			case badge != nil && badge.AlphaAt(x, y).A > 0:
				c = badgeColor(accent)
			case tile.AlphaAt(x, y).A > 0 && bubble.AlphaAt(x, y).A > 0:
				c = color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF}
			case tile.AlphaAt(x, y).A > 0:
				// Vertical two-tone: bottom 45% slightly darker.
				if float64(y)/f > 0.55 {
					c = dark
				} else {
					c = accent
				}
			default:
				continue // fully transparent outside the tile
			}
			i := img.PixOffset(x, y)
			img.Pix[i] = c.R
			img.Pix[i+1] = c.G
			img.Pix[i+2] = c.B
			img.Pix[i+3] = 0xFF
		}
	}

	if label != "" {
		drawTrayDigits(img, px, label)
	}
	var buf bytes.Buffer
	_ = png.Encode(&buf, img)
	return buf.Bytes()
}

// roundedTileMask renders the anti-aliased rounded square as an alpha mask.
func roundedTileMask(px, r int) *image.Alpha {
	m := image.NewAlpha(image.Rect(0, 0, px, px))
	// 2x supersampling for smooth corners.
	const ss = 2
	for y := 0; y < px; y++ {
		for x := 0; x < px; x++ {
			hits := 0
			for sy := 0; sy < ss; sy++ {
				for sx := 0; sx < ss; sx++ {
					fx := float64(x) + (float64(sx)+0.5)/ss
					fy := float64(y) + (float64(sy)+0.5)/ss
					if inRoundedRect(fx, fy, float64(px), float64(r)) {
						hits++
					}
				}
			}
			m.Pix[y*px+x] = uint8(255 * hits / (ss * ss))
		}
	}
	return m
}

// inRoundedRect reports whether (x, y) lies inside the centered rounded
// square of the given size.
func inRoundedRect(x, y, size, r float64) bool {
	lo, hi := 0.0, size
	// Distance to the nearest corner-center point in the rounded region.
	var cx, cy float64
	switch {
	case x < lo+r && y < lo+r:
		cx, cy = lo+r, lo+r
	case x > hi-r && y < lo+r:
		cx, cy = hi-r, lo+r
	case x < lo+r && y > hi-r:
		cx, cy = lo+r, hi-r
	case x > hi-r && y > hi-r:
		cx, cy = hi-r, hi-r
	default:
		return x >= lo && x <= hi && y >= lo && y <= hi
	}
	dx, dy := x-cx, y-cy
	return dx*dx+dy*dy <= r*r
}

// bubbleMask renders the speech-bubble mark (alpha mask) inside the tile.
func bubbleMask(px int) *image.Alpha {
	m := image.NewAlpha(image.Rect(0, 0, px, px))
	f := float64(px)
	// Bubble body: rounded rect occupying the upper-middle ~52% of the tile.
	// Tail: triangle from the body's bottom-left going down-left.
	bodyX0, bodyY0 := f*0.24, f*0.20
	bodyX1, bodyY1 := f*0.76, f*0.56
	tailX0, tailY0 := f*0.30, f*0.54 // tail top edge (on the body bottom)
	tailX1, tailY1 := f*0.20, f*0.72 // tail tip (down-left)

	const ss = 2
	for y := 0; y < px; y++ {
		for x := 0; x < px; x++ {
			hits := 0
			for sy := 0; sy < ss; sy++ {
				for sx := 0; sx < ss; sx++ {
					fx := float64(x) + (float64(sx)+0.5)/ss
					fy := float64(y) + (float64(sy)+0.5)/ss
					if inBubble(fx, fy, bodyX0, bodyY0, bodyX1, bodyY1, tailX0, tailY0, tailX1, tailY1) {
						hits++
					}
				}
			}
			if hits > 0 {
				m.Pix[y*px+x] = uint8(255 * hits / (ss * ss))
			}
		}
	}
	return m
}

// inBubble tests one supersample point against the bubble geometry.
func inBubble(x, y, bx0, by0, bx1, by1, tx0, ty0, tx1, ty1 float64) bool {
	br := (bx1 - bx0) * 0.30 // body corner radius
	if inRoundedRectXY(x, y, bx0, by0, bx1, by1, br) {
		return true
	}
	// Tail triangle (tip at (tx1,ty1), base along the body's bottom).
	return pointInTriangle(x, y, tx0, ty0, tx0+(tx1-tx0)*0.9, ty0, tx1, ty1)
}

// inRoundedRectXY is inRoundedRect for an explicit rect.
func inRoundedRectXY(x, y, x0, y0, x1, y1, r float64) bool {
	var cx, cy float64
	switch {
	case x < x0+r && y < y0+r:
		cx, cy = x0+r, y0+r
	case x > x1-r && y < y0+r:
		cx, cy = x1-r, y0+r
	case x < x0+r && y > y1-r:
		cx, cy = x0+r, y1-r
	case x > x1-r && y > y1-r:
		cx, cy = x1-r, y1-r
	default:
		return x >= x0 && x <= x1 && y >= y0 && y <= y1
	}
	dx, dy := x-cx, y-cy
	return dx*dx+dy*dy <= r*r
}

// pointInTriangle via barycentric sign tests.
func pointInTriangle(px, py, ax, ay, bx, by, cx, cy float64) bool {
	d1 := cross(px, py, ax, ay, bx, by)
	d2 := cross(px, py, bx, by, cx, cy)
	d3 := cross(px, py, cx, cy, ax, ay)
	hasNeg := d1 < 0 || d2 < 0 || d3 < 0
	hasPos := d1 > 0 || d2 > 0 || d3 > 0
	return !(hasNeg && hasPos)
}

func cross(px, py, ax, ay, bx, by float64) float64 {
	return (px-bx)*(ay-by) - (ax-bx)*(py-by)
}

// badgeMask renders the unread badge: a filled circle at the bottom-right
// corner plus the digit glyphs punched as "lit" area (the badge itself is
// drawn in badgeColor; digits are drawn white by the caller via the mask
// covering the whole badge region — digits differentiated in badgeGlyphs).
func badgeMask(px int, digits int) *image.Alpha {
	m := image.NewAlpha(image.Rect(0, 0, px, px))
	f := float64(px)
	r := f * 0.30 // badge radius
	if digits > 2 {
		r = f * 0.34
	}
	cx, cy := f-r-f*0.04, f-r-f*0.04 // anchored bottom-right, slight inset

	const ss = 2
	for y := 0; y < px; y++ {
		for x := 0; x < px; x++ {
			hits := 0
			for sy := 0; sy < ss; sy++ {
				for sx := 0; sx < ss; sx++ {
					fx := float64(x) + (float64(sx)+0.5)/ss
					fy := float64(y) + (float64(sy)+0.5)/ss
					dx, dy := fx-cx, fy-cy
					if dx*dx+dy*dy <= r*r {
						hits++
					}
				}
			}
			if hits > 0 {
				m.Pix[y*px+x] = uint8(255 * hits / (ss * ss))
			}
		}
	}
	return m
}

// badgeColor derives the badge fill from the accent: a strong red tint
// (unread urgency, tdesktop's badge red) regardless of accent hue.
func badgeColor(accent color.NRGBA) color.NRGBA {
	_ = accent // badge stays brand-constant (red), not accent-tinted
	return color.NRGBA{R: 0xE5, G: 0x3E, B: 0x3E, A: 0xFF}
}

// shade scales an RGB color toward black (factor < 1) keeping alpha.
func shade(c color.NRGBA, f float64) color.NRGBA {
	return color.NRGBA{
		R: uint8(float64(c.R) * f),
		G: uint8(float64(c.G) * f),
		B: uint8(float64(c.B) * f),
		A: c.A,
	}
}

// drawTrayDigits stamps white digit glyphs into an NRGBA over the badge
// circle. Used by renderTrayIconPNG via a second pass (kept separate for
// testability).
func drawTrayDigits(img *image.NRGBA, px int, label string) {
	if label == "" {
		return
	}
	f := float64(px)
	r := f * 0.30
	if len(label) > 2 {
		r = f * 0.34
	}
	cx, cy := f-r-f*0.04, f-r-f*0.04
	// Glyph geometry: each 3x5 digit scaled so the text block fits within
	// ~62% of the badge diameter.
	gw, gh := 3, 5
	sp := 1 // one-pixel spacing column between digits (in font units)
	units := len(label)*gw + (len(label)-1)*sp
	scale := int(math.Round(2 * r * 0.62 / float64(gh)))
	if scale < 1 {
		scale = 1
	}
	w := units * scale
	h := gh * scale
	x0 := int(math.Round(cx)) - w/2
	y0 := int(math.Round(cy)) - h/2

	for di := 0; di < len(label); di++ {
		gl, ok := trayGlyphs[label[di]]
		if !ok {
			continue
		}
		base := x0 + di*(gw+sp)*scale
		for gy := 0; gy < gh; gy++ {
			row := gl[gy]
			for gx := 0; gx < gw; gx++ {
				if row&(1<<(gw-1-gx)) == 0 {
					continue
				}
				for sy := 0; sy < scale; sy++ {
					for sx := 0; sx < scale; sx++ {
						x := base + gx*scale + sx
						y := y0 + gy*scale + sy
						if x < 0 || y < 0 || x >= px || y >= px {
							continue
						}
						i := img.PixOffset(x, y)
						img.Pix[i] = 0xFF
						img.Pix[i+1] = 0xFF
						img.Pix[i+2] = 0xFF
						img.Pix[i+3] = 0xFF
					}
				}
			}
		}
	}
}

// RenderTrayIconSample is the exported seam for tooling/tests that need a
// tray icon render (e.g. visual smoke scripts).
func RenderTrayIconSample(accent color.NRGBA, count int) []byte {
	return renderTrayIconPNG(128, accent, count)
}
