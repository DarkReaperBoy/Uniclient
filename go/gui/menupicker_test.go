package gui

import (
	"testing"
)

// Full reaction picker (slice 55): the quick bar keeps at most 7 pills
// and flags the expandable ⋯ toggle only when reactions remain.
func TestQuickReactions(t *testing.T) {
	seven := []string{"1", "2", "3", "4", "5", "6", "7"}
	quick, more := quickReactions(seven)
	if len(quick) != 7 || more {
		t.Fatalf("exactly seven: quick=%v more=%v", quick, more)
	}

	eight := append([]string{}, seven...)
	eight = append(eight, "8")
	quick, more = quickReactions(eight)
	if len(quick) != 7 || quick[6] != "7" || !more {
		t.Fatalf("eight: quick=%v more=%v", quick, more)
	}

	quick, more = quickReactions(nil)
	if quick != nil || more {
		t.Fatalf("empty: quick=%v more=%v", quick, more)
	}

	quick, more = quickReactions([]string{"a"})
	if len(quick) != 1 || quick[0] != "a" || more {
		t.Fatalf("one: quick=%v more=%v", quick, more)
	}
}
