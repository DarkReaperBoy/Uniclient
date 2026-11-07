package tests

import (
	"fmt"
	"image/color"
	"math"
	"reflect"
	"testing"

	. "uniclient/ui/material"
)

func srgbLinear(v uint8) float64 {
	f := float64(v) / 255
	if f <= 0.04045 {
		return f / 12.92
	}
	return math.Pow((f+0.055)/1.055, 2.4)
}

func luma(c color.NRGBA) float64 {
	return 0.2126*srgbLinear(c.R) + 0.7152*srgbLinear(c.G) + 0.0722*srgbLinear(c.B)
}

func contrast(a, b color.NRGBA) float64 {
	la, lb := luma(a), luma(b)
	if la < lb {
		la, lb = lb, la
	}
	return (la + 0.05) / (lb + 0.05)
}

func kindName(k Kind) string {
	switch k {
	case Light:
		return "light"
	case Dark:
		return "dark"
	case Amoled:
		return "amoled"
	}
	return "unknown"
}

func mustHex(t *testing.T, name string, got, want color.NRGBA) {
	t.Helper()
	if got != want {
		t.Fatalf("%s drifted: %s (want %s)", name,
			fmt.Sprintf("#%02X%02X%02X", got.R, got.G, got.B),
			fmt.Sprintf("#%02X%02X%02X", want.R, want.G, want.B))
	}
}

func TestBaselineLightAnchors(t *testing.T) {
	s := SchemeFor(Light)
	mustHex(t, "Primary", s.Primary, color.NRGBA{0x67, 0x50, 0xA4, 0xFF})
	mustHex(t, "OnPrimary", s.OnPrimary, color.NRGBA{0xFF, 0xFF, 0xFF, 0xFF})
	mustHex(t, "PrimaryContainer", s.PrimaryContainer, color.NRGBA{0xEA, 0xDD, 0xFF, 0xFF})
	mustHex(t, "OnPrimaryContainer", s.OnPrimaryContainer, color.NRGBA{0x21, 0x00, 0x5D, 0xFF})
	mustHex(t, "Secondary", s.Secondary, color.NRGBA{0x62, 0x5B, 0x71, 0xFF})
	mustHex(t, "Tertiary", s.Tertiary, color.NRGBA{0x7D, 0x52, 0x60, 0xFF})
	mustHex(t, "Error", s.Error, color.NRGBA{0xB3, 0x26, 0x1E, 0xFF})
	mustHex(t, "Background", s.Background, color.NRGBA{0xFE, 0xF7, 0xFF, 0xFF})
	mustHex(t, "Surface", s.Surface, color.NRGBA{0xFE, 0xF7, 0xFF, 0xFF})
	mustHex(t, "OnSurface", s.OnSurface, color.NRGBA{0x1D, 0x1B, 0x20, 0xFF})
	mustHex(t, "SurfaceVariant", s.SurfaceVariant, color.NRGBA{0xE7, 0xE0, 0xEC, 0xFF})
	mustHex(t, "SurfaceContainerHighest", s.SurfaceContainerHighest, color.NRGBA{0xE6, 0xE0, 0xE9, 0xFF})
	mustHex(t, "Outline", s.Outline, color.NRGBA{0x79, 0x74, 0x7E, 0xFF})
	mustHex(t, "Scrim", s.Scrim, color.NRGBA{0x00, 0x00, 0x00, 0xFF})
}

func TestBaselineDarkAnchors(t *testing.T) {
	s := SchemeFor(Dark)
	mustHex(t, "Primary", s.Primary, color.NRGBA{0xD0, 0xBC, 0xFF, 0xFF})
	mustHex(t, "OnPrimary", s.OnPrimary, color.NRGBA{0x38, 0x1E, 0x72, 0xFF})
	mustHex(t, "PrimaryContainer", s.PrimaryContainer, color.NRGBA{0x4F, 0x37, 0x8B, 0xFF})
	mustHex(t, "OnPrimaryContainer", s.OnPrimaryContainer, color.NRGBA{0xEA, 0xDD, 0xFF, 0xFF})
	mustHex(t, "Background", s.Background, color.NRGBA{0x14, 0x12, 0x18, 0xFF})
	mustHex(t, "Surface", s.Surface, color.NRGBA{0x14, 0x12, 0x18, 0xFF})
	mustHex(t, "OnSurface", s.OnSurface, color.NRGBA{0xE6, 0xE0, 0xE9, 0xFF})
	mustHex(t, "SurfaceContainerLowest", s.SurfaceContainerLowest, color.NRGBA{0x0F, 0x0D, 0x13, 0xFF})
	mustHex(t, "SurfaceContainerHighest", s.SurfaceContainerHighest, color.NRGBA{0x36, 0x34, 0x3B, 0xFF})
	mustHex(t, "SurfaceBright", s.SurfaceBright, color.NRGBA{0x3B, 0x38, 0x3E, 0xFF})
	mustHex(t, "Error", s.Error, color.NRGBA{0xF2, 0xB8, 0xB5, 0xFF})
	mustHex(t, "Outline", s.Outline, color.NRGBA{0x93, 0x8F, 0x99, 0xFF})
}

func TestAmoledBlackChrome(t *testing.T) {
	black := color.NRGBA{0x00, 0x00, 0x00, 0xFF}
	s := SchemeFor(Amoled)
	d := SchemeFor(Dark)
	mustHex(t, "Background", s.Background, black)
	mustHex(t, "Surface", s.Surface, black)
	mustHex(t, "SurfaceDim", s.SurfaceDim, black)
	mustHex(t, "SurfaceContainerLowest", s.SurfaceContainerLowest, black)
	mustHex(t, "SurfaceContainerLow", s.SurfaceContainerLow, d.SurfaceContainerLow)
	mustHex(t, "SurfaceContainer", s.SurfaceContainer, d.SurfaceContainer)
	mustHex(t, "SurfaceContainerHigh", s.SurfaceContainerHigh, d.SurfaceContainerHigh)
	mustHex(t, "SurfaceContainerHighest", s.SurfaceContainerHighest, d.SurfaceContainerHighest)
	mustHex(t, "SurfaceBright", s.SurfaceBright, d.SurfaceBright)
	mustHex(t, "Primary", s.Primary, d.Primary)
	mustHex(t, "OnSurface", s.OnSurface, d.OnSurface)
	mustHex(t, "OnError", s.OnError, d.OnError)
	mustHex(t, "OutlineVariant", s.OutlineVariant, d.OutlineVariant)
}

func TestSchemeContrastPairs(t *testing.T) {
	pairs := []struct {
		name string
		fg   func(Scheme) color.NRGBA
		bg   func(Scheme) color.NRGBA
	}{
		{"OnPrimary/Primary", func(s Scheme) color.NRGBA { return s.OnPrimary }, func(s Scheme) color.NRGBA { return s.Primary }},
		{"OnSecondary/Secondary", func(s Scheme) color.NRGBA { return s.OnSecondary }, func(s Scheme) color.NRGBA { return s.Secondary }},
		{"OnTertiary/Tertiary", func(s Scheme) color.NRGBA { return s.OnTertiary }, func(s Scheme) color.NRGBA { return s.Tertiary }},
		{"OnError/Error", func(s Scheme) color.NRGBA { return s.OnError }, func(s Scheme) color.NRGBA { return s.Error }},
		{"OnPrimaryContainer/PrimaryContainer", func(s Scheme) color.NRGBA { return s.OnPrimaryContainer }, func(s Scheme) color.NRGBA { return s.PrimaryContainer }},
		{"OnSecondaryContainer/SecondaryContainer", func(s Scheme) color.NRGBA { return s.OnSecondaryContainer }, func(s Scheme) color.NRGBA { return s.SecondaryContainer }},
		{"OnTertiaryContainer/TertiaryContainer", func(s Scheme) color.NRGBA { return s.OnTertiaryContainer }, func(s Scheme) color.NRGBA { return s.TertiaryContainer }},
		{"OnErrorContainer/ErrorContainer", func(s Scheme) color.NRGBA { return s.OnErrorContainer }, func(s Scheme) color.NRGBA { return s.ErrorContainer }},
		{"OnSurface/Surface", func(s Scheme) color.NRGBA { return s.OnSurface }, func(s Scheme) color.NRGBA { return s.Surface }},
		{"OnBackground/Background", func(s Scheme) color.NRGBA { return s.OnBackground }, func(s Scheme) color.NRGBA { return s.Background }},
		{"OnSurfaceVariant/SurfaceVariant", func(s Scheme) color.NRGBA { return s.OnSurfaceVariant }, func(s Scheme) color.NRGBA { return s.SurfaceVariant }},
		{"InverseOnSurface/InverseSurface", func(s Scheme) color.NRGBA { return s.InverseOnSurface }, func(s Scheme) color.NRGBA { return s.InverseSurface }},
	}
	for _, kind := range []Kind{Light, Dark, Amoled} {
		s := SchemeFor(kind)
		for _, p := range pairs {
			if got := contrast(p.fg(s), p.bg(s)); got < 4.5 {
				t.Fatalf("%s %s contrast %.2f < 4.5", kindName(kind), p.name, got)
			}
		}
	}
}

func TestSurfaceTintFollowsPrimary(t *testing.T) {
	for _, kind := range []Kind{Light, Dark, Amoled} {
		s := SchemeFor(kind)
		if s.SurfaceTint != s.Primary {
			t.Fatalf("%s surface tint %v != primary %v", kindName(kind), s.SurfaceTint, s.Primary)
		}
	}
}

func TestSchemeColorsOpaque(t *testing.T) {
	typ := reflect.TypeOf(Scheme{})
	for _, kind := range []Kind{Light, Dark, Amoled} {
		s := reflect.ValueOf(SchemeFor(kind))
		for i := 0; i < s.NumField(); i++ {
			if got := s.Field(i).Field(3).Uint(); got != 0xFF {
				t.Fatalf("%s.%s alpha %d, want 255", kindName(kind), typ.Field(i).Name, got)
			}
		}
	}
}

func TestSchemesDistinct(t *testing.T) {
	l, d, a := SchemeFor(Light), SchemeFor(Dark), SchemeFor(Amoled)
	if l == d {
		t.Fatal("light scheme equals dark scheme")
	}
	if d == a {
		t.Fatal("dark scheme equals amoled scheme")
	}
	if l == a {
		t.Fatal("light scheme equals amoled scheme")
	}
}

func TestDarkSurfaceHierarchy(t *testing.T) {
	for _, kind := range []Kind{Dark, Amoled} {
		s := SchemeFor(kind)
		levels := []color.NRGBA{
			s.SurfaceContainerLowest, s.Surface, s.SurfaceContainerLow,
			s.SurfaceContainer, s.SurfaceContainerHigh, s.SurfaceContainerHighest,
			s.SurfaceBright,
		}
		for i := 1; i < len(levels); i++ {
			if luma(levels[i]) < luma(levels[i-1]) {
				t.Fatalf("%s surface luma order broken at level %d", kindName(kind), i)
			}
		}
	}
}
