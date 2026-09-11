package gui

// fontpick_test.go — slice 146 (tests-first): the pure halves of the
// custom-font support — collection face swapping, path validation and
// display names.

import (
	"path/filepath"
	"testing"

	"gioui.org/font"
	"gioui.org/font/gofont"
	"gioui.org/font/opentype"
	"golang.org/x/image/font/gofont/goregular"
)

// goregularTTF exposes the embedded Go regular font bytes (a stand-in
// for a picked .ttf in tests).
func goregularTTF() []byte { return goregular.TTF }

// fakeUserFace builds a real parsed face from the embedded Go fonts —
// the same pipeline a picked .ttf goes through.
func fakeUserFace(t *testing.T) font.Face {
	t.Helper()
	faces, err := opentype.ParseCollection(goregularTTF())
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(faces) == 0 {
		t.Fatal("no faces in collection")
	}
	return faces[0].Face
}

// TestSwapCollectionFaces: swapping the default family's face objects
// keeps every descriptor (typeface/weight/style) and the entry count —
// matching behaves exactly as before, only the glyphs change. The mono
// family only swaps when a mono face is given.
func TestSwapCollectionFaces(t *testing.T) {
	base := gofont.Collection()
	userFace := fakeUserFace(t)
	monoFace := fakeUserFace(t)

	out := swapCollectionFaces(base, userFace, nil)
	if len(out) != len(base) {
		t.Fatalf("count changed: %d vs %d", len(out), len(base))
	}
	defFamily := base[0].Font.Typeface
	swapped, monoSwapped := 0, 0
	for i := range out {
		if out[i].Font != base[i].Font {
			t.Fatalf("descriptor %d changed: %+v vs %+v", i, out[i].Font, base[i].Font)
		}
		switch out[i].Font.Typeface {
		case defFamily:
			if out[i].Face == userFace {
				swapped++
			} else if out[i].Face != base[i].Face {
				t.Fatalf("default-family face %d neither user nor original", i)
			}
		case "Go Mono":
			if out[i].Face != base[i].Face {
				t.Fatalf("mono face swapped without a mono font (leak of the user font)")
			}
		}
	}
	if swapped == 0 {
		t.Fatalf("no default-family entries swapped (family = %q)", defFamily)
	}
	_ = monoSwapped

	// With a mono face, the mono family swaps too.
	out2 := swapCollectionFaces(base, userFace, monoFace)
	monoSwapped = 0
	for i := range out2 {
		if out2[i].Font.Typeface == "Go Mono" && out2[i].Face == monoFace {
			monoSwapped++
		}
	}
	if monoSwapped == 0 {
		t.Fatal("mono family never swapped with a mono face")
	}
	if defFamily == "Go Mono" {
		t.Skip("default family IS mono in this gio version")
	}
}

// TestSwapCollectionFacesNil: nil faces → the base collection unchanged
// (same slice content).
func TestSwapCollectionFacesNil(t *testing.T) {
	base := gofont.Collection()
	out := swapCollectionFaces(base, nil, nil)
	if len(out) != len(base) {
		t.Fatalf("count changed: %d vs %d", len(out), len(base))
	}
	for i := range out {
		if out[i].Face != base[i].Face || out[i].Font != base[i].Font {
			t.Fatalf("entry %d changed with nil faces", i)
		}
	}
}

// TestIsFontPath: font extensions (case-insensitive).
func TestIsFontPath(t *testing.T) {
	cases := []struct {
		path string
		want bool
	}{
		{"/home/z/fonts/Inter.ttf", true},
		{"/home/z/Inter.TTF", true},
		{"/home/z/Inter.otf", true},
		{"/home/z/Inter.OTF", true},
		{"/home/z/Inter.woff2", false},
		{"/home/z/Inter", false},
		{"", false},
		{"/home/z/font.ttf.bak", false},
	}
	for _, c := range cases {
		if got := isFontPath(c.path); got != c.want {
			t.Errorf("isFontPath(%q) = %v, want %v", c.path, got, c.want)
		}
	}
}

// TestFontFileName: display name = base name of the path.
func TestFontFileName(t *testing.T) {
	cases := []struct {
		path string
		want string
	}{
		{"/home/z/fonts/Inter-Regular.ttf", "Inter-Regular.ttf"},
		{filepath.Join("x", "Mono.otf"), "Mono.otf"},
		{"", "Default"},
	}
	for _, c := range cases {
		if got := fontFileName(c.path); got != c.want {
			t.Errorf("fontFileName(%q) = %q, want %q", c.path, got, c.want)
		}
	}
}
