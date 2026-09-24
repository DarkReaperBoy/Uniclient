package gui

// tests-first for BUGS.md B-14 — labels must not contain invisible
// control characters.
//
// The reaction-"more" button's label was double-encoded mojibake: the
// bytes `C3 A2 C2 8B C2 AF` are a Latin-1 re-encoding of "⋯" (U+22EF),
// which puts a raw U+008B (an invisible C1 control) into the message
// actions row (staticcheck ST1018). The slice-235 source scan found
// exactly ONE such site repo-wide — this test keeps the whole package
// at zero, so any future double-encode fails immediately instead of
// shipping an invisible glyph.

import (
	"os"
	"strings"
	"testing"
)

func TestGUISourcesHaveNoControlCharLabels(t *testing.T) {
	entries, err := os.ReadDir(".")
	if err != nil {
		t.Fatal(err)
	}
	found := 0
	for _, e := range entries {
		name := e.Name()
		if e.IsDir() || !strings.HasSuffix(name, ".go") {
			continue
		}
		data, err := os.ReadFile(name)
		if err != nil {
			t.Fatal(err)
		}
		for i, line := range strings.Split(string(data), "\n") {
			for _, r := range line {
				if r >= 0x80 && r <= 0x9F { // C1 controls: mojibake's fingerprint
					t.Errorf("%s:%d contains control character U+%04X — double-encoded label? (B-14)", name, i+1, r)
					found++
				}
			}
		}
	}
	if found == 0 {
		// The constant itself must be the clean glyph too.
		if reactionMoreLabel != "⋯" {
			t.Errorf("reactionMoreLabel = %q, want ⋯ (U+22EF)", reactionMoreLabel)
		}
	}
}
