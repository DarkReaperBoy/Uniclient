package gui

// Composer char counter (slice 88, AyuGram parity row 124): the remaining
// character count appears under the a.wid.composer near Telegram's per-message
// limit and turns red past it; the send paths refuse over-limit drafts.

import (
	"strings"
	"testing"
	"unicode/utf8"
)

func TestCharCounterState(t *testing.T) {
	const limit = 4096
	// Hidden far from the limit.
	if lbl, vis, over := charCounterState("hello", limit); vis || lbl != "" || over {
		t.Errorf("short draft: %q %v %v — counter must hide", lbl, vis, over)
	}
	// Shows near the limit (remaining <= 128).
	n := limit - 128
	if lbl, vis, over := charCounterState(strings.Repeat("a", n), limit); !vis || lbl != "128" || over {
		t.Errorf("at 128 remaining: %q %v %v", lbl, vis, over)
	}
	// Exact limit: shows 0, not over.
	if lbl, vis, over := charCounterState(strings.Repeat("a", limit), limit); !vis || lbl != "0" || over {
		t.Errorf("at limit: %q %v %v", lbl, vis, over)
	}
	// Past the limit: negative + red.
	if lbl, vis, over := charCounterState(strings.Repeat("a", limit+7), limit); !vis || lbl != "-7" || !over {
		t.Errorf("over limit: %q %v %v", lbl, vis, over)
	}
	// Rune counting, not bytes: CJK counts one per character.
	cjk := strings.Repeat("界", limit-100) // 3 bytes each
	if lbl, vis, over := charCounterState(cjk, limit); !vis || lbl != "100" || over {
		t.Errorf("rune count: %q %v %v — want 100 remaining", lbl, vis, over)
	}
	if utf8.RuneCountInString(cjk) != limit-100 {
		t.Fatalf("test premise: rune count mismatch")
	}
}

func TestComposerOverLimitGate(t *testing.T) {
	if composerOverLimit("short") {
		t.Error("short draft must not be over")
	}
	if !composerOverLimit(strings.Repeat("x", composerCharLimit+1)) {
		t.Error("one past the limit must be over")
	}
	if composerOverLimit(strings.Repeat("x", composerCharLimit)) {
		t.Error("exactly at the limit is fine")
	}
}
