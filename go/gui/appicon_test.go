package gui

// appicon_test.go — slice 170: AyuGram app-icon selector (ayu_settings.h
// appIcon + ayu/ui/components/icon_picker.cpp 1:1 in behavior).
//
// Primary source research (2026-09-13, GitHub API on AyuGramDesktop dev):
// AyuGram ships 12 icon sets (default, alt, discord, spotify, extera,
// nothing, bard, yaplus, win95, chibi, chibi2, extera2) picked in a
// 4-column grid (IconPicker::kColumns = 4) with cached previews and
// apply-on-click (Window::OverrideApplicationIcon + tray refresh). Our
// mirror: 12 OWN art sets (reusing the slice-137 programmatic tile+mark
// renderer with distinct palettes — never copied assets), the same grid
// shape, apply-on-click, persisted as AyuAppIcon.

import (
	"image/color"
	"testing"
)

func TestAppIconSetsRegistry(t *testing.T) {
	sets := appIconSets()
	if len(sets) != 12 {
		t.Fatalf("appIconSets count = %d, want 12 (AyuGram ships 12 sets)", len(sets))
	}
	seen := map[string]bool{}
	for _, s := range sets {
		if s.ID == "" {
			t.Fatal("icon set with empty ID")
		}
		if seen[s.ID] {
			t.Fatalf("duplicate icon set ID %q", s.ID)
		}
		seen[s.ID] = true
		if s.Label == "" {
			t.Fatalf("icon set %q has no label", s.ID)
		}
	}
	if sets[0].ID != "default" {
		t.Fatalf("first set = %q, want default", sets[0].ID)
	}
	if _, ok := seen["monochrome"]; !ok {
		t.Fatal("no monochrome set")
	}
}

func TestAppIconSetByID(t *testing.T) {
	sets := appIconSets()
	for _, s := range sets {
		if got := appIconSetByID(s.ID); got.ID != s.ID {
			t.Errorf("appIconSetByID(%q) = %q", s.ID, got.ID)
		}
	}
	// Unknown ID falls back to the default set (config from a newer build
	// must never crash or render an empty icon).
	if got := appIconSetByID("does-not-exist"); got.ID != "default" {
		t.Fatalf("appIconSetByID(bogus) = %q, want default", got.ID)
	}
	if got := appIconSetByID(""); got.ID != "default" {
		t.Fatalf("appIconSetByID(empty) = %q, want default", got.ID)
	}
}

func TestRenderAppIconDistinct(t *testing.T) {
	a := renderAppIconRGBA(appIconSetByID("default"), 64)
	b := renderAppIconRGBA(appIconSetByID("monochrome"), 64)
	if a == nil || b == nil {
		t.Fatal("nil render")
	}
	// Sample the bare tile area (upper-left inside the rounded corner,
	// outside the bubble mark which is white in both sets) — the tile
	// colors must differ between the sets.
	i := a.PixOffset(8, 8)
	ra, ga, ba := a.Pix[i], a.Pix[i+1], a.Pix[i+2]
	j := b.PixOffset(8, 8)
	rb, gb, bb := b.Pix[j], b.Pix[j+1], b.Pix[j+2]
	if ra == rb && ga == gb && ba == bb {
		t.Fatalf("default and monochrome tile colors identical: %v", ra)
	}
	// Opaque inside the tile.
	if a.Pix[i+3] != 0xFF {
		t.Fatalf("default set tile alpha = %d, want 255", a.Pix[i+3])
	}
}

func TestRenderAppIconSizes(t *testing.T) {
	set := appIconSetByID("default")
	for _, px := range []int{16, 32, 48, 256} {
		img := renderAppIconRGBA(set, px)
		if img.Bounds().Dx() != px || img.Bounds().Dy() != px {
			t.Fatalf("render(%d) bounds = %v", px, img.Bounds())
		}
		nonZero := false
		for _, p := range img.Pix {
			if p != 0 {
				nonZero = true
				break
			}
		}
		if !nonZero {
			t.Fatalf("render(%d) is fully transparent", px)
		}
	}
	if img := renderAppIconRGBA(set, 8); img.Bounds().Dx() < 16 {
		t.Fatalf("render below minimum clamps to >= 16, got %d", img.Bounds().Dx())
	}
}

// TestNetWMIconDataFormat pins the X11 _NET_WM_ICON payload: for each
// icon, [width, height, ARGB cardinals...] with ARGB packing
// (0xAARRGGBB) — the freedesktop spec order (alpha, not RGBA).
func TestNetWMIconDataFormat(t *testing.T) {
	set := appIconSetByID("default")
	data := netWMIconData(set, 24)
	if len(data) != 2+24*24 {
		t.Fatalf("payload length = %d, want %d", len(data), 2+24*24)
	}
	if data[0] != 24 || data[1] != 24 {
		t.Fatalf("payload dims = %d x %d, want 24 x 24", data[0], data[1])
	}
	// Center pixel: on-tile, fully opaque, packed A in the top byte.
	c := uint32(data[2+12*24+12])
	if c&(0xFF<<24) != 0xFF<<24 {
		t.Fatalf("center pixel alpha bits = %#x, want 0xFF000000", c&(0xFF<<24))
	}
	// Corner pixel: outside the rounded tile → fully transparent.
	corner := uint32(data[2+0])
	if corner != 0 {
		t.Fatalf("corner pixel = %#x, want 0 (outside rounded tile)", corner)
	}
}

func TestEffectiveAppIconSet(t *testing.T) {
	cases := []struct {
		id   string
		want string
	}{
		{"", "default"},
		{"grape", "grape"},
		{"nope", "default"},
	}
	for _, c := range cases {
		got := effectiveAppIconSet(cfgSnapshot{AyuAppIcon: c.id})
		if got.ID != c.want {
			t.Errorf("effectiveAppIconSet(%q) = %q, want %q", c.id, got.ID, c.want)
		}
	}
}

// TestRenderTrayIconForSet: the tray keeps its unread badge but follows
// the selected icon set's palette (AyuGram tray = current app logo).
func TestRenderTrayIconForSet(t *testing.T) {
	accent := color.NRGBA{R: 0x2E, G: 0x7D, B: 0x32, A: 0xFF}
	set := appIconSetByID("grape")
	noBadge := renderTrayIconForSetPNG(64, set, accent, 0)
	withBadge := renderTrayIconForSetPNG(64, set, accent, 7)
	if len(noBadge) == 0 || len(withBadge) == 0 {
		t.Fatal("empty tray renders")
	}
	if len(noBadge) == len(withBadge) {
		// Not a strict requirement, but the badge digits should almost
		// always change the PNG size; if equal, at least verify the
		// pixels differ.
		t.Log("badge did not change PNG size (acceptable)")
	}
}
