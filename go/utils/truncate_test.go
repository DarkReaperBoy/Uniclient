package utils

import (
	"testing"
	"unicode/utf8"
)

// Truncate/TruncateEllipsis are the shared display-preview cutters
// (B-28): rune-based, never split a multi-byte character, ellipsis only
// when a cut actually happened.

func TestTruncateEllipsis(t *testing.T) {
	cases := []struct {
		in   string
		max  int
		want string
	}{
		{"hello", 10, "hello"},         // under limit → unchanged
		{"hello", 5, "hello"},          // exactly at limit → unchanged
		{"hello world", 5, "hello..."}, // cut + ellipsis
		{"ééééééé", 5, "ééééé..."},     // rune boundary
		{"日本語テスト", 3, "日本語..."},        // 3-byte runes exactly at limit... no: 5 runes > 3 → cut
		{"😀😀😀😀", 4, "😀😀😀😀"},            // 4 runes == limit → unchanged (4-byte runes!)
		{"😀😀😀😀😀", 4, "😀😀😀😀..."},        // 5 > 4 → cut at 4 runes
		{"", 5, ""}, // empty
	}
	for _, c := range cases {
		got := TruncateEllipsis(c.in, c.max)
		if got != c.want {
			t.Errorf("TruncateEllipsis(%q, %d) = %q, want %q", c.in, c.max, got, c.want)
		}
		if !utf8.ValidString(got) {
			t.Errorf("TruncateEllipsis(%q, %d) produced invalid UTF-8: %q", c.in, c.max, got)
		}
	}
}

func TestTruncateNoEllipsis(t *testing.T) {
	cases := []struct {
		in   string
		max  int
		want string
	}{
		{"hello", 10, "hello"},
		{"hello world", 5, "hello"},
		{"ééééé", 3, "ééé"},
		{"日本語", 5, "日本語"}, // 3 runes ≤ 5 → unchanged even though... bytes=9>5 under the OLD byte rule
		{"", 5, ""},
	}
	for _, c := range cases {
		got := Truncate(c.in, c.max)
		if got != c.want {
			t.Errorf("Truncate(%q, %d) = %q, want %q", c.in, c.max, got, c.want)
		}
		if !utf8.ValidString(got) {
			t.Errorf("Truncate(%q, %d) produced invalid UTF-8", c.in, c.max)
		}
	}
}
