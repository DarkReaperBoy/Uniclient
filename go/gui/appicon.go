package gui

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"math"
)

type appIconSet struct {
	ID    string
	Label string
	Tile  color.NRGBA
	Mark  color.NRGBA
}

var liveAccentTile = color.NRGBA{}

func appIconSets() []appIconSet {
	white := color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF}
	return []appIconSet{
		{ID: "default", Label: "Default", Tile: liveAccentTile, Mark: white},
		{ID: "monochrome", Label: "Monochrome", Tile: color.NRGBA{R: 0x21, G: 0x25, B: 0x29, A: 0xFF}, Mark: white},
		{ID: "inverted", Label: "Inverted", Tile: white, Mark: color.NRGBA{R: 0x1A, G: 0x1C, B: 0x1E, A: 0xFF}},
		{ID: "ocean", Label: "Ocean", Tile: color.NRGBA{R: 0x02, G: 0x78, B: 0xD4, A: 0xFF}, Mark: white},
		{ID: "forest", Label: "Forest", Tile: color.NRGBA{R: 0x1B, G: 0x5E, B: 0x20, A: 0xFF}, Mark: white},
		{ID: "sunset", Label: "Sunset", Tile: color.NRGBA{R: 0xE4, G: 0x51, B: 0x2B, A: 0xFF}, Mark: white},
		{ID: "grape", Label: "Grape", Tile: color.NRGBA{R: 0x6A, G: 0x1B, B: 0x9A, A: 0xFF}, Mark: white},
		{ID: "slate", Label: "Slate", Tile: color.NRGBA{R: 0x37, G: 0x47, B: 0x4F, A: 0xFF}, Mark: white},
		{ID: "berry", Label: "Berry", Tile: color.NRGBA{R: 0xAD, G: 0x14, B: 0x57, A: 0xFF}, Mark: white},
		{ID: "gold", Label: "Gold", Tile: color.NRGBA{R: 0xB8, G: 0x86, B: 0x0B, A: 0xFF}, Mark: color.NRGBA{R: 0x1A, G: 0x1C, B: 0x1E, A: 0xFF}},
		{ID: "teal", Label: "Teal", Tile: color.NRGBA{R: 0x00, G: 0x77, B: 0x74, A: 0xFF}, Mark: white},
		{ID: "carbon", Label: "Carbon", Tile: color.NRGBA{R: 0x0D, G: 0x0F, B: 0x11, A: 0xFF}, Mark: color.NRGBA{R: 0x9E, G: 0xA6, B: 0xAD, A: 0xFF}},
	}
}

func appIconSetByID(id string) appIconSet {
	for _, s := range appIconSets() {
		if s.ID == id {
			return s
		}
	}
	return appIconSets()[0]
}

func colorEq(a, b color.NRGBA) bool {
	return a.R == b.R && a.G == b.G && a.B == b.B && a.A == b.A
}

func effectiveAppIconSet(cfg cfgSnapshot) appIconSet {
	return appIconSetByID(cfg.AyuAppIcon)
}

const appIconPickerSupported = appIconRuntimeApply

var appIconAccentStandIn = color.NRGBA{R: 0x54, G: 0xA8, B: 0xF0, A: 0xFF}

func renderAppIconRGBA(set appIconSet, px int) *image.NRGBA {
	if px < 16 {
		px = 16
	}
	tile := set.Tile
	if tile == liveAccentTile {
		tile = appIconAccentStandIn
	}
	return renderIconTile(px, tile, set.Mark, nil, 0)
}

func renderTrayIconForSetPNG(px int, set appIconSet, accent color.NRGBA, count int) []byte {
	if px < 16 {
		px = 16
	}
	tile := set.Tile
	if set.Tile == liveAccentTile {
		tile = accent
	}
	img := renderIconTile(px, tile, set.Mark, nil, count)
	var buf bytes.Buffer
	_ = png.Encode(&buf, img)
	return buf.Bytes()
}

func renderIconTile(px int, tile, mark color.NRGBA, _ *image.Alpha, count int) *image.NRGBA {
	img := image.NewNRGBA(image.Rect(0, 0, px, px))
	f := float64(px)

	tMask := roundedTileMask(px, int(math.Round(f*0.22)))
	bubble := bubbleMask(px)
	dark := shade(tile, 0.82)

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
				c = badgeColor(tile)
			case tMask.AlphaAt(x, y).A > 0 && bubble.AlphaAt(x, y).A > 0:
				c = mark
			case tMask.AlphaAt(x, y).A > 0:
				if float64(y)/f > 0.55 {
					c = dark
				} else {
					c = tile
				}
			default:
				continue
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
	return img
}

func netWMIconData(set appIconSet, px int) []uint32 {
	if px < 16 {
		px = 16
	}
	img := renderAppIconRGBA(set, px)
	data := make([]uint32, 2, 2+px*px)
	data[0] = uint32(px)
	data[1] = uint32(px)
	b := img.Bounds()
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			i := img.PixOffset(x, y)
			argb := uint32(img.Pix[i+3])<<24 | uint32(img.Pix[i])<<16 |
				uint32(img.Pix[i+1])<<8 | uint32(img.Pix[i+2])
			data = append(data, argb)
		}
	}
	return data
}

const appIconGridColumns = 4

func appIconGridRows(n int) int {
	if n <= 0 {
		return 0
	}
	return (n + appIconGridColumns - 1) / appIconGridColumns
}

func appIconCellWidth(w int) int {
	if w <= 0 {
		return 0
	}
	return w / appIconGridColumns
}

func appIconIsSelected(set appIconSet, cfg cfgSnapshot) bool {
	return appIconSetByID(cfg.AyuAppIcon).ID == set.ID
}
