package tests

import (
	"testing"
	. "uniclient/utils"
	"unicode/utf8"
)

func TestTruncateEllipsis(t *testing.T) {
	cases := []struct {
		in   string
		max  int
		want string
	}{
		{"hello", 10, "hello"},
		{"hello", 5, "hello"},
		{"hello world", 5, "hello..."},
		{"ééééééé", 5, "ééééé..."},
		{"日本語テスト", 3, "日本語..."},
		{"😀😀😀😀", 4, "😀😀😀😀"},
		{"😀😀😀😀😀", 4, "😀😀😀😀..."},
		{"", 5, ""},
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
		{"日本語", 5, "日本語"},
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
