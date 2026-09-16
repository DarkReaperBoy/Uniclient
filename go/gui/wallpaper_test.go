package gui

// wallpaper_test.go — slice 218 pure pins: the mirrored-JSON parse, the
// spec blur chain (downscale-to-450 + separable box blur), and the box
// scaler's averaging behavior.

import (
	"encoding/json"
	"image"
	"testing"

	"uniclient/cores"
)

func TestParseWallpaperJSON(t *testing.T) {
	if _, ok := parseWallpaperJSON(""); ok {
		t.Fatal("empty JSON parsed as a wallpaper")
	}
	if _, ok := parseWallpaperJSON("not json"); ok {
		t.Fatal("garbage parsed as a wallpaper")
	}
	info, ok := parseWallpaperJSON(`{"id":5,"access_hash":6,"doc_id":7,"doc_hash":8,"blurred":true,"motion":true}`)
	if !ok {
		t.Fatal("valid JSON rejected")
	}
	if info.ID != 5 || info.AccessHash != 6 || info.DocID != 7 || info.DocHash != 8 {
		t.Fatalf("fields = %+v", info)
	}
	if !info.Blurred || !info.Motion {
		t.Fatalf("settings lost: %+v", info)
	}
}

func TestWallpaperJSONRoundTripCore(t *testing.T) {
	// The GUI parse must accept exactly what the core marshals.
	info := cores.WallpaperInfo{ID: 1, AccessHash: 2, DocID: 3, DocHash: 4, Blurred: true, Intensity: -20, Colors: []int{0x445566}}
	raw, err := json.Marshal(info)
	if err != nil {
		t.Fatal(err)
	}
	back, ok := parseWallpaperJSON(string(raw))
	if !ok || back.ID != 1 || back.DocID != 3 || !back.Blurred || back.Intensity != -20 {
		t.Fatalf("round-trip drift: %+v ok=%v", back, ok)
	}
}

func TestBoxScaleRGBAverages(t *testing.T) {
	// A 4×4 image with a 2×2 white block on black, scaled to 2×2: each
	// destination pixel averages a 2×2 source footprint → exact quarters.
	src := image.NewRGBA(image.Rect(0, 0, 4, 4))
	for y := 0; y < 2; y++ {
		for x := 0; x < 2; x++ {
			i := src.PixOffset(x, y)
			src.Pix[i], src.Pix[i+1], src.Pix[i+2], src.Pix[i+3] = 255, 255, 255, 255
		}
	}
	dst := boxScaleRGBA(src, 2, 2)
	if r, g, b, _ := dst.At(0, 0).RGBA(); byte(r>>8) != 255 || byte(g>>8) != 255 || byte(b>>8) != 255 {
		t.Fatalf("top-left = (%d,%d,%d), want white", r>>8, g>>8, b>>8)
	}
	if r, g, b, _ := dst.At(1, 1).RGBA(); r != 0 || g != 0 || b != 0 {
		t.Fatalf("bottom-right = (%d,%d,%d), want black", r, g, b)
	}
	// Uniform image stays uniform at any scale.
	uniform := image.NewRGBA(image.Rect(0, 0, 9, 9))
	for i := range uniform.Pix {
		uniform.Pix[i] = []byte{90, 100, 110, 255}[i%4]
	}
	scaled := boxScaleRGBA(uniform, 3, 3)
	for y := 0; y < 3; y++ {
		for x := 0; x < 3; x++ {
			r, g, b, _ := scaled.At(x, y).RGBA()
			if byte(r>>8) != 90 || byte(g>>8) != 100 || byte(b>>8) != 110 {
				t.Fatalf("uniform drifted at (%d,%d): %d %d %d", x, y, r>>8, g>>8, b>>8)
			}
		}
	}
}

func TestBoxBlurUniformInvariant(t *testing.T) {
	// Blurring a uniform image must not change it.
	src := image.NewRGBA(image.Rect(0, 0, 40, 40))
	for i := 0; i < len(src.Pix); i += 4 {
		src.Pix[i], src.Pix[i+1], src.Pix[i+2], src.Pix[i+3] = 120, 130, 140, 255
	}
	dst := boxBlurRGBA(src, 12)
	for y := 0; y < 40; y++ {
		for x := 0; x < 40; x++ {
			r, g, b, _ := dst.At(x, y).RGBA()
			if byte(r>>8) != 120 || byte(g>>8) != 130 || byte(b>>8) != 140 {
				t.Fatalf("uniform drifted at (%d,%d)", x, y)
			}
		}
	}
}

func TestBoxBlurSmearsEdges(t *testing.T) {
	// A left-white/right-black image blurs into intermediate values near
	// the seam while the far edges stay pure.
	src := image.NewRGBA(image.Rect(0, 0, 64, 8))
	for y := 0; y < 8; y++ {
		for x := 0; x < 64; x++ {
			i := src.PixOffset(x, y)
			v := byte(0)
			if x < 32 {
				v = 255
			}
			src.Pix[i], src.Pix[i+1], src.Pix[i+2], src.Pix[i+3] = v, v, v, 255
		}
	}
	dst := boxBlurRGBA(src, 4)
	l, _, _, _ := dst.At(2, 4).RGBA()
	mid, _, _, _ := dst.At(31, 4).RGBA()
	r, _, _, _ := dst.At(61, 4).RGBA()
	if byte(l>>8) != 255 {
		t.Fatalf("left edge = %d, want 255", l>>8)
	}
	if byte(r>>8) != 0 {
		t.Fatalf("right edge = %d, want 0", r>>8)
	}
	if mid>>8 == 255 || mid>>8 == 0 {
		t.Fatalf("seam pixel = %d, want intermediate", mid>>8)
	}
}

func TestWallpaperBlurDownscales(t *testing.T) {
	// A 2000×1000 image must come back ≤450 wide after the spec blur.
	src := image.NewRGBA(image.Rect(0, 0, 2000, 1000))
	for i := 0; i < len(src.Pix); i += 4 {
		src.Pix[i], src.Pix[i+1], src.Pix[i+2], src.Pix[i+3] = 200, 210, 220, 255
	}
	dst := wallpaperBlur(src)
	if w := dst.Bounds().Dx(); w > 450 {
		t.Fatalf("blurred width = %d, want ≤450 (spec: fit 450×450)", w)
	}
	// Uniform content survives the blur chain.
	r, g, b, _ := dst.At(dst.Bounds().Dx()/2, dst.Bounds().Dy()/2).RGBA()
	if r>>8 < 190 || r>>8 > 210 {
		t.Fatalf("uniform drifted: %d", r>>8)
	}
	_ = g
	_ = b
}

func TestWallpaperBlurSmallPassthrough(t *testing.T) {
	// Under-450 images skip the downscale but still blur.
	src := image.NewRGBA(image.Rect(0, 0, 100, 100))
	dst := wallpaperBlur(src)
	if dst.Bounds().Dx() != 100 {
		t.Fatalf("small image rescaled: %d", dst.Bounds().Dx())
	}
}
