package tests

import (
	"math"
	"testing"

	. "uniclient/ui/text"
)

func mono(advance, height int) Metrics {
	return Metrics{
		Height:  height,
		Advance: func(rune) int { return advance },
	}
}

func wideEllipsis(advance, ellipsis, height int) Metrics {
	return Metrics{
		Height: height,
		Advance: func(r rune) int {
			if r == '…' {
				return ellipsis
			}
			return advance
		},
	}
}

func TestLineHeight(t *testing.T) {
	cases := []struct {
		fontHeight, styleLineHeight, want int
	}{
		{16, 0, 16},
		{16, -1, 16},
		{16, 18, 18},
		{16, 12, 16},
		{20, 20, 20},
	}
	for _, c := range cases {
		if got := LineHeight(c.fontHeight, c.styleLineHeight); got != c.want {
			t.Fatalf("LineHeight(%d, %d) = %d, want %d", c.fontHeight, c.styleLineHeight, got, c.want)
		}
	}
}

func TestLineAscent(t *testing.T) {
	cases := []struct {
		m     Metrics
		lineH int
		want  float64
	}{
		{mono(8, 16), 0, 12.8},
		{mono(8, 16), 12, 12.8},
		{Metrics{Height: 16, Leading: 3}, 0, 9.8},
		{Metrics{Height: 16, Leading: 2}, 0, 10.8},
		{mono(8, 16), 20, 16},
		{mono(8, 20), 0, 16},
		{mono(8, 10), 20, 16},
		{Metrics{Height: 16, Leading: 100}, 0, 0},
		{Metrics{Height: 16, Leading: -5}, 0, 12.8},
	}
	for _, c := range cases {
		got := LineAscent(c.m, c.lineH)
		if math.Abs(got-c.want) > 1e-9 {
			t.Fatalf("LineAscent(h=%d lead=%d lh=%d) = %v, want %v", c.m.Height, c.m.Leading, c.lineH, got, c.want)
		}
	}
}

func TestElide(t *testing.T) {
	cases := []struct {
		text  string
		width int
		m     Metrics
		want  string
	}{
		{"abc", 30, mono(8, 16), "abc"},
		{"abcd", 30, mono(8, 16), "ab…"},
		{"abc", 20, mono(8, 16), "a…"},
		{"abc", 10, mono(8, 16), "…"},
		{"abc", 5, mono(8, 16), "…"},
		{"Hi", 16, mono(8, 16), "Hi"},
		{"", 20, mono(8, 16), ""},
		{"abcd", 25, wideEllipsis(10, 12, 16), "a…"},
	}
	for _, c := range cases {
		got := string(Elide([]rune(c.text), c.width, c.m))
		if got != c.want {
			t.Fatalf("Elide(%q, %d) = %q, want %q", c.text, c.width, got, c.want)
		}
	}
}

func TestLayout(t *testing.T) {
	cases := []struct {
		text   string
		width  int
		lines  []string
		widths []int
		starts []int
	}{
		{"", 24, []string{""}, []int{0}, []int{0}},
		{"a", 24, []string{"a"}, []int{8}, []int{0}},
		{"aaa", 24, []string{"aaa"}, []int{24}, []int{0}},
		{"aa bb cc", 24, []string{"aa ", "bb ", "cc"}, []int{24, 24, 16}, []int{0, 3, 6}},
		{"aaaa", 24, []string{"aaa", "a"}, []int{24, 8}, []int{0, 3}},
		{"x aaaa", 24, []string{"x ", "aaa", "a"}, []int{16, 24, 8}, []int{0, 2, 5}},
		{"aa   bb", 24, []string{"aa   ", "bb"}, []int{40, 16}, []int{0, 5}},
		{" aa", 24, []string{" aa"}, []int{24}, []int{0}},
		{"   aa", 16, []string{"   ", "aa"}, []int{24, 16}, []int{0, 3}},
		{"a", 4, []string{"a"}, []int{8}, []int{0}},
		{"a\nb", 100, []string{"a", "b"}, []int{8, 8}, []int{0, 2}},
		{"a\n", 100, []string{"a", ""}, []int{8, 0}, []int{0, 2}},
		{"\n", 100, []string{"", ""}, []int{0, 0}, []int{0, 1}},
		{"a\n\nb", 100, []string{"a", "", "b"}, []int{8, 0, 8}, []int{0, 2, 3}},
		{"aa bb\ncc dd", 16, []string{"aa ", "bb", "cc ", "dd"}, []int{24, 16, 24, 16}, []int{0, 3, 6, 9}},
	}
	for _, c := range cases {
		doc := Layout(c.text, c.width, mono(8, 16))
		if len(doc.Lines) != len(c.lines) {
			t.Fatalf("Layout(%q, %d): %d lines, want %d: %v", c.text, c.width, len(doc.Lines), len(c.lines), doc.Lines)
		}
		for i, want := range c.lines {
			line := doc.Lines[i]
			if string(line.Runes) != want || line.Width != c.widths[i] || line.Start != c.starts[i] {
				t.Fatalf("Layout(%q, %d) line %d = {%q w%d s%d}, want {%q w%d s%d}",
					c.text, c.width, i, string(line.Runes), line.Width, line.Start, want, c.widths[i], c.starts[i])
			}
		}
		if got := string(doc.Text); got != c.text {
			t.Fatalf("Layout(%q).Text = %q", c.text, got)
		}
	}
}

func TestDocumentHeight(t *testing.T) {
	doc := Layout("aa bb cc", 24, mono(8, 16))
	if got := doc.Height(16); got != 48 {
		t.Fatalf("Height = %d, want 48", got)
	}
	empty := Layout("", 24, mono(8, 16))
	if got := empty.Height(16); got != 16 {
		t.Fatalf("empty Height = %d, want 16", got)
	}
}

func TestCursorAt(t *testing.T) {
	doc := Layout("aa bb cc", 24, mono(8, 16))
	cases := []struct {
		offset int
		line   int
		column int
		x      int
	}{
		{0, 0, 0, 0},
		{2, 0, 2, 16},
		{3, 1, 0, 0},
		{4, 1, 1, 8},
		{5, 1, 2, 16},
		{6, 2, 0, 0},
		{7, 2, 1, 8},
		{8, 2, 2, 16},
		{-3, 0, 0, 0},
		{99, 2, 2, 16},
	}
	for _, c := range cases {
		got := doc.CursorAt(c.offset)
		if got.Line != c.line || got.Column != c.column || got.X != c.x {
			t.Fatalf("CursorAt(%d) = {line %d col %d x %d}, want {line %d col %d x %d}",
				c.offset, got.Line, got.Column, got.X, c.line, c.column, c.x)
		}
	}

	nl := Layout("a\nb", 100, mono(8, 16))
	if got := nl.CursorAt(1); got.Line != 0 || got.Column != 1 || got.X != 8 {
		t.Fatalf("CursorAt(1) on newline = %+v, want {0 1 8}", got)
	}
	if got := nl.CursorAt(2); got.Line != 1 || got.Column != 0 || got.X != 0 {
		t.Fatalf("CursorAt(2) after newline = %+v, want {1 0 0}", got)
	}
}
