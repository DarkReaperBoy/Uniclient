package gui

import (
	"os"
	"runtime"
	"strings"
	"testing"
)

func TestGUISourcesHaveNoControlCharLabels(t *testing.T) {
	if runtime.GOOS == "js" {
		t.Skip("source files are unreachable on js/wasm (no filesystem by design)")
	}
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
				if r >= 0x80 && r <= 0x9F {
					t.Errorf("%s:%d contains control character U+%04X — double-encoded label? (B-14)", name, i+1, r)
					found++
				}
			}
		}
	}
	if found == 0 {
		if reactionMoreLabel != "⋯" {
			t.Errorf("reactionMoreLabel = %q, want ⋯ (U+22EF)", reactionMoreLabel)
		}
	}
}
