package cores

import (
	"testing"
	"unicode/utf8"
)

// TestTruncateHelperKeepsUTF8Valid: BUGS B-28 — the package's truncate
// helper sliced by BYTES (`s[:maxLen]`), so any multi-byte rune straddling
// the cut produced invalid UTF-8 (mojibake in error messages, thread
// titles, previews). RED before the rune-safe fix.
func TestTruncateHelperKeepsUTF8Valid(t *testing.T) {
	cases := []struct {
		in  string
		max int
	}{
		{"ééééééé", 5},              // cut lands mid-rune
		{"日本語テキストです", 4},            // 3-byte runes
		{"😀😀😀😀😀😀", 5},               // 4-byte runes
		{"ascii only text here", 6}, // ASCII must keep working
		{"ééé", 5},                  // under the limit → unchanged
	}
	for _, c := range cases {
		out := truncate(c.in, c.max)
		if !utf8.ValidString(out) {
			t.Errorf("truncate(%q, %d) = %q — invalid UTF-8 (byte slice split a rune)", c.in, c.max, out)
		}
	}
}

// Semantic pins: cut happens at the rune limit, "..." only on cut, and
// short strings pass through untouched.
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
