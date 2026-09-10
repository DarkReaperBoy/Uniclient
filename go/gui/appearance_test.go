package gui

import (
	"image/color"
	"testing"
)

// Accent & font scale (slice 59): hex parsing, blending, clamping, and
// preset integrity.
func TestParseAccentHex(t *testing.T) {
	c, ok := parseAccentHex("#4f6ef7")
	if !ok || c.R != 0x4f || c.G != 0x6e || c.B != 0xf7 || c.A != 0xFF {
		t.Fatalf("parse = %+v %v", c, ok)
	}
	for _, bad := range []string{"", "#12345", "4f6ef7", "#zzzzzz", "#1234567", " #4f6ef7"} {
		// note: " #4f6ef7" trims to valid — only test truly malformed here
		if bad == " #4f6ef7" {
			continue
		}
		if _, ok := parseAccentHex(bad); ok {
			t.Errorf("accepted malformed %q", bad)
		}
	}
	if c, ok := parseAccentHex("  #4F6EF7  "); !ok || c.R != 0x4f {
		t.Errorf("trim+case = %+v %v", c, ok)
	}
}

func TestMixNRGBA(t *testing.T) {
	black := color.NRGBA{A: 0xFF, R: 0, G: 0, B: 0}
	white := color.NRGBA{A: 0xFF, R: 255, G: 255, B: 255}
	got := mixNRGBA(black, white, 0.5)
	if got.R != 128 || got.G != 128 || got.B != 128 {
		t.Fatalf("mid = %+v", got)
	}
	if got := mixNRGBA(black, white, 0); got != black {
		t.Fatalf("t=0 = %+v", got)
	}
	if got := mixNRGBA(black, white, 1); got != white {
		t.Fatalf("t=1 = %+v", got)
	}
}

func TestClampFontScale(t *testing.T) {
	if clampFontScale(0.5) != 0.8 {
		t.Error("floor")
	}
	if clampFontScale(2.0) != 1.4 {
		t.Error("ceil")
	}
	if clampFontScale(1.1) != 1.1 {
		t.Error("mid passthrough")
	}
}

func TestAccentPresetsValid(t *testing.T) {
	if len(accents) < 5 {
		t.Fatalf("presets = %d", len(accents))
	}
	seen := map[string]bool{}
	for _, p := range accents {
		if _, ok := parseAccentHex(p.hex); !ok {
			t.Errorf("bad preset hex %q", p.hex)
		}
		if p.name == "" {
			t.Errorf("preset %q has no name", p.hex)
		}
		if seen[p.hex] {
			t.Errorf("duplicate preset %q", p.hex)
		}
		seen[p.hex] = true
	}
}

func TestFontScaleChoices(t *testing.T) {
	if len(fontScaleChoices) != 3 {
		t.Fatalf("choices = %d", len(fontScaleChoices))
	}
	for i, ch := range fontScaleChoices {
		if got := clampFontScale(ch.v); got != ch.v {
			t.Errorf("choice %d (%s) not in range: %v", i, ch.label, ch.v)
		}
	}
	if fontScaleChoices[1].v != 1.0 {
		t.Error("default must be 1.0")
	}
}
