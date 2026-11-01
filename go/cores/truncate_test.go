package cores

import (
	"testing"
	"unicode/utf8"
)

func TestTruncateHelperKeepsUTF8Valid(t *testing.T) {
	cases := []struct {
		in  string
		max int
	}{
		{"ééééééé", 5},
		{"日本語テキストです", 4},
		{"😀😀😀😀😀😀", 5},
		{"ascii only text here", 6},
		{"ééé", 5},
	}
	for _, c := range cases {
		out := truncate(c.in, c.max)
		if !utf8.ValidString(out) {
			t.Errorf("truncate(%q, %d) = %q — invalid UTF-8 (byte slice split a rune)", c.in, c.max, out)
		}
	}
}

func TestTruncateHelperSemantics(t *testing.T) {
	if got := truncate("hello", 10); got != "hello" {
		t.Errorf("short string = %q", got)
	}
	if got := truncate("hello world", 5); got != "hello..." {
		t.Errorf("cut = %q, want hello...", got)
	}
	if got := truncate("", 5); got != "" {
		t.Errorf("empty = %q", got)
	}
}
