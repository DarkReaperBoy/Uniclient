package gui

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"math"
)

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

func renderTrayIconPNG(px int, accent color.NRGBA, count int) []byte {
	if px < 16 {
		px = 16
	}
	white := color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF}
	img := renderIconTile(px, accent, white, nil, count)
	var buf bytes.Buffer
	_ = png.Encode(&buf, img)
	return buf.Bytes()
}

func roundedTileMask(px, r int) *image.Alpha {
	m := image.NewAlpha(image.Rect(0, 0, px, px))
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

func inRoundedRect(x, y, size, r float64) bool {
	lo, hi := 0.0, size
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

func bubbleMask(px int) *image.Alpha {
	m := image.NewAlpha(image.Rect(0, 0, px, px))
	f := float64(px)
	bodyX0, bodyY0 := f*0.24, f*0.20
	bodyX1, bodyY1 := f*0.76, f*0.56
	tailX0, tailY0 := f*0.30, f*0.54
	tailX1, tailY1 := f*0.20, f*0.72

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

func inBubble(x, y, bx0, by0, bx1, by1, tx0, ty0, tx1, ty1 float64) bool {
	br := (bx1 - bx0) * 0.30
	if inRoundedRectXY(x, y, bx0, by0, bx1, by1, br) {
		return true
	}
	return pointInTriangle(x, y, tx0, ty0, tx0+(tx1-tx0)*0.9, ty0, tx1, ty1)
}

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

func badgeMask(px int, digits int) *image.Alpha {
	m := image.NewAlpha(image.Rect(0, 0, px, px))
	f := float64(px)
	r := f * 0.30
	if digits > 2 {
		r = f * 0.34
	}
	cx, cy := f-r-f*0.04, f-r-f*0.04

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

func badgeColor(accent color.NRGBA) color.NRGBA {
	_ = accent
	return color.NRGBA{R: 0xE5, G: 0x3E, B: 0x3E, A: 0xFF}
}

func shade(c color.NRGBA, f float64) color.NRGBA {
	return color.NRGBA{
		R: uint8(float64(c.R) * f),
		G: uint8(float64(c.G) * f),
		B: uint8(float64(c.B) * f),
		A: c.A,
	}
}

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
	gw, gh := 3, 5
	sp := 1
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
