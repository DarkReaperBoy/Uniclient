package engine

import (
	"path/filepath"
	"testing"

	"uniclient/utils"
)

// Recent searches (AyuGram parity slice 37): engine AddRecentSearch
// dedupes, moves to front, and caps at 8.

func newRecentsEngine(t *testing.T) *Engine {
	dir := t.TempDir()
	v, err := utils.CreateVault(filepath.Join(dir, "vault.db"), "test")
	if err != nil {
		t.Fatal(err)
	}
	cfg := utils.DefaultConfig()
	return &Engine{vault: v, config: &cfg}
}

func TestAddRecentSearchOrderAndCap(t *testing.T) {
	e := newRecentsEngine(t)
	for _, q := range []string{"one", "two", "three", "four", "five", "six", "seven", "eight", "nine"} {
		if err := e.AddRecentSearch(q); err != nil {
			t.Fatal(err)
		}
	}
	got := e.GetConfig().RecentSearches
	if len(got) != 8 {
		t.Fatalf("len = %d, want 8 (capped)", len(got))
	}
	if got[0] != "nine" {
		t.Errorf("front = %q, want nine (most recent first)", got[0])
	}
	if got[7] != "two" {
		t.Errorf("back = %q, want two (oldest evicted)", got[7])
	}
}

func TestAddRecentSearchDedupe(t *testing.T) {
	e := newRecentsEngine(t)
	_ = e.AddRecentSearch("alpha")
	_ = e.AddRecentSearch("beta")
	if err := e.AddRecentSearch("ALPHA"); err != nil { // case-insensitive dedupe
		t.Fatal(err)
	}
	got := e.GetConfig().RecentSearches
	if len(got) != 2 {
		t.Fatalf("len = %d, want 2", len(got))
	}
	if got[0] != "ALPHA" {
		t.Errorf("front = %q, want ALPHA", got[0])
	}
}

func TestAddRecentSearchEmpty(t *testing.T) {
	e := newRecentsEngine(t)
	if err := e.AddRecentSearch("   "); err != nil {
		t.Fatal(err)
	}
	if got := e.GetConfig().RecentSearches; len(got) != 0 {
		t.Fatalf("whitespace-only added: %v", got)
	}
}

func TestClearRecentSearches(t *testing.T) {
	e := newRecentsEngine(t)
	_ = e.AddRecentSearch("x")
	if err := e.ClearRecentSearches(); err != nil {
		t.Fatal(err)
	}
	if got := e.GetConfig().RecentSearches; len(got) != 0 {
		t.Fatalf("clear left %v", got)
	}
}
