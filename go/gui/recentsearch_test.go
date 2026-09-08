package gui

import (
	"testing"
)

// Recent searches (AyuGram parity slice 37).

func TestTrimRecentSearch(t *testing.T) {
	got := trimRecentSearch([]string{" alice ", "", "bob", "  ", "carol"})
	want := []string{"alice", "bob", "carol"}
	if len(got) != len(want) {
		t.Fatalf("trim = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("trim[%d] = %q, want %q", i, got[i], want[i])
		}
	}
	long := make([]string, 20)
	for i := range long {
		long[i] = "q"
	}
	if got := trimRecentSearch(long); len(got) != 8 {
		t.Errorf("cap = %d, want 8", len(got))
	}
	if got := trimRecentSearch(nil); len(got) != 0 {
		t.Errorf("nil = %v", got)
	}
}
