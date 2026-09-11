package gui

import (
	"bytes"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"os"
	"testing"
)

// decodeTrayPNG decodes rendered icon bytes for assertions.
func decodeTrayPNG(t *testing.T, b []byte) image.Image {
	t.Helper()
	img, err := png.Decode(bytes.NewReader(b))
	if err != nil {
		t.Fatalf("png decode: %v", err)
	}
	return img
}

// TestRenderTrayIconPNGDecodes: the renderer emits a valid PNG of the
// requested square size.
func TestRenderTrayIconPNGDecodes(t *testing.T) {
	for _, sz := range []int{64, 128, 256} {
		b := renderTrayIconPNG(sz, color.NRGBA{R: 0x35, G: 0x7C, B: 0xF0, A: 0xFF}, 0)
		img := decodeTrayPNG(t, b)
		if img.Bounds().Dx() != sz || img.Bounds().Dy() != sz {
			t.Fatalf("size %d: bounds = %v", sz, img.Bounds())
		}
	}
}

// TestRenderTrayIconBadgePresence: count > 0 draws the badge circle (some
// pixel far from the center differs from the no-badge render); count = 0
// never does.
func TestRenderTrayIconBadgePresence(t *testing.T) {
	accent := color.NRGBA{R: 0x35, G: 0x7C, B: 0xF0, A: 0xFF}
	plain := decodeTrayPNG(t, renderTrayIconPNG(128, accent, 0))
	badged := decodeTrayPNG(t, renderTrayIconPNG(128, accent, 3))

	// The badge sits in the bottom-right quadrant; scan it for a change.
	changed := 0
	for y := 96; y < 128; y++ {
		for x := 96; x < 128; x++ {
			p1 := plain.At(x, y)
			p2 := badged.At(x, y)
			if p1 != p2 {
				changed++
			}
		}
	}
	if changed < 50 {
		t.Fatalf("badge region changed only %d pixels, want >= 50", changed)
	}

	// Same region between two plain renders must be identical (determinism).
	plain2 := decodeTrayPNG(t, renderTrayIconPNG(128, accent, 0))
	for y := 96; y < 128; y++ {
		for x := 96; x < 128; x++ {
			if plain.At(x, y) != plain2.At(x, y) {
				t.Fatal("plain render is not deterministic")
			}
		}
	}
}

// TestRenderTrayIconDigitsDiffer: two different counts render differently
// inside the badge; "9+" is used past the digit budget.
func TestRenderTrayIconDigitsDiffer(t *testing.T) {
	accent := color.NRGBA{R: 0x35, G: 0x7C, B: 0xF0, A: 0xFF}
	i3 := decodeTrayPNG(t, renderTrayIconPNG(128, accent, 3))
	i7 := decodeTrayPNG(t, renderTrayIconPNG(128, accent, 7))
	i12 := decodeTrayPNG(t, renderTrayIconPNG(128, accent, 12))
	i999 := decodeTrayPNG(t, renderTrayIconPNG(128, accent, 999))

	diff := func(a, b image.Image) int {
		n := 0
		for y := 96; y < 128; y++ {
			for x := 96; x < 128; x++ {
				if a.At(x, y) != b.At(x, y) {
					n++
				}
			}
		}
		return n
	}
	if diff(i3, i7) < 10 {
		t.Fatal("3 and 7 badges look identical")
	}
	if diff(i3, i12) < 10 {
		t.Fatal("3 and 12 badges look identical")
	}
	if diff(i12, i999) < 10 {
		t.Fatal("12 and 999 badges look identical")
	}
}

// TestTrayCountLabel: badge text formatting (pure).
func TestTrayCountLabel(t *testing.T) {
	cases := []struct {
		n    int
		want string
	}{
		{0, ""}, {1, "1"}, {9, "9"}, {10, "10"}, {99, "99"}, {100, "99+"}, {9999, "99+"},
	}
	for _, c := range cases {
		if got := trayCountLabel(c.n); got != c.want {
			t.Errorf("trayCountLabel(%d) = %q, want %q", c.n, got, c.want)
		}
	}
}

// TestRenderTrayIconDumpSamples: visual smoke — writes sample icons to
// UNICLIENT_TRAY_ICON_DIR when set (screenshots for review; no-op in CI).
func TestRenderTrayIconDumpSamples(t *testing.T) {
	dir := os.Getenv("UNICLIENT_TRAY_ICON_DIR")
	if dir == "" {
		t.Skip("UNICLIENT_TRAY_ICON_DIR not set")
	}
	accent := color.NRGBA{R: 0x35, G: 0x7C, B: 0xF0, A: 0xFF}
	for _, n := range []int{0, 3, 12, 157} {
		p := fmt.Sprintf("%s/tray_%d.png", dir, n)
		if err := os.WriteFile(p, renderTrayIconPNG(128, accent, n), 0o644); err != nil {
			t.Fatalf("write %s: %v", p, err)
		}
	}
}
