package dialogs

import (
	"fmt"
	"image"
	"image/color"
	"math"
)

const (
	TTLBlurRadius  = 24
	TTLContrastMin = 4.5
	TTLDarken      = 0.2
	TTLInnerMargin = 2
)

var TTLTimerInk = color.NRGBA{R: 0xff, G: 0xff, B: 0xff, A: 0xff}

func FormatTTLTiny(sec int) string {
	switch {
	case sec <= 3600*9:
		return fmt.Sprintf("%dh", sec/3600)
	case sec <= 86400*6:
		return fmt.Sprintf("%dd", sec/86400)
	case sec <= 86400*7*3:
		return fmt.Sprintf("%dw", sec/(86400*7))
	case sec <= 86400*31*11:
		return fmt.Sprintf("%dm", sec/(86400*31))
	case sec <= 86400*366:
		return fmt.Sprintf("%dy", int(math.Round(float64(sec)/float64(86400*365))))
	}
	return ""
}

func TimerClamp(s string) string {
	runes := []rune(s)
	if len(runes) <= 2 {
		return s
	}
	return string(runes[:2])
}

func TTLTimerRect(badge Rect) Rect {
	return Rect{
		X: badge.X + TTLInnerMargin,
		Y: badge.Y + TTLInnerMargin,
		W: badge.W - 2*TTLInnerMargin,
		H: badge.H - 2*TTLInnerMargin,
	}
}

func TTLBackdrop(userpic image.Image, badge image.Rectangle) image.Image {
	orig := userpic.Bounds()
	src := toNRGBA(userpic)
	badge = image.Rect(
		badge.Min.X-orig.Min.X, badge.Min.Y-orig.Min.Y,
		badge.Max.X-orig.Min.X, badge.Max.Y-orig.Min.Y,
	).Intersect(src.Bounds())
	out := image.NewNRGBA(badge)
	if badge.Empty() {
		return out
	}
	blurred := StackBlur(src, TTLBlurRadius)
	var sumR, sumG, sumB uint64
	for y := badge.Min.Y; y < badge.Max.Y; y++ {
		for x := badge.Min.X; x < badge.Max.X; x++ {
			r, g, b, _ := blurred.At(x, y).RGBA()
			sumR += uint64(uint8(r))
			sumG += uint64(uint8(g))
			sumB += uint64(uint8(b))
		}
	}
	n := uint64(badge.Dx() * badge.Dy())
	avg := color.NRGBA{
		R: uint8(sumR / n),
		G: uint8(sumG / n),
		B: uint8(sumB / n),
		A: 0xff,
	}
	darken := ContrastRatio(avg, TTLTimerInk) < TTLContrastMin
	for y := badge.Min.Y; y < badge.Max.Y; y++ {
		for x := badge.Min.X; x < badge.Max.X; x++ {
			r, g, b, _ := blurred.At(x, y).RGBA()
			c := color.NRGBA{R: uint8(r), G: uint8(g), B: uint8(b), A: 0xff}
			if darken {
				c.R = uint8(int(c.R) * 4 / 5)
				c.G = uint8(int(c.G) * 4 / 5)
				c.B = uint8(int(c.B) * 4 / 5)
			}
			out.SetNRGBA(x, y, c)
		}
	}
	return out
}

func ContrastRatio(a, b color.NRGBA) float64 {
	la := relativeLuminance(a)
	lb := relativeLuminance(b)
	brightest, darkest := la, lb
	if lb > la {
		brightest, darkest = lb, la
	}
	return (brightest + 0.05) / (darkest + 0.05)
}

func relativeLuminance(c color.NRGBA) float64 {
	mapf := func(v float64) float64 {
		if v <= 0.03928 {
			return v / 12.92
		}
		return math.Pow((v+0.055)/1.055, 2.4)
	}
	return mapf(float64(c.R)/255)*0.2126 +
		mapf(float64(c.G)/255)*0.7152 +
		mapf(float64(c.B)/255)*0.0722
}

func toNRGBA(src image.Image) *image.NRGBA {
	b := src.Bounds()
	if n, ok := src.(*image.NRGBA); ok && b.Min == (image.Point{}) {
		return n
	}
	out := image.NewNRGBA(image.Rect(0, 0, b.Dx(), b.Dy()))
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			out.Set(x-b.Min.X, y-b.Min.Y, src.At(x, y))
		}
	}
	return out
}
