package gui

import "testing"

// R14 (B-47 class): the in-chat search from-user picker's open flag must be
// PER-WINDOW state on App, never package-level — a package var is written and
// read by every window's GUI loop (main + separate chat windows render the
// same chatHeader search button), an unsynchronized cross-goroutine access
// whose value also bleeds between windows. Mirrors the slice-168 rule the
// App struct comment states: per-window interactive state lives on the App.
func TestInSearchFromPanelIsPerWindow(t *testing.T) {
	a, b := &App{}, &App{}
	a.mu.Lock()
	a.inSearchFromPanel = true
	a.mu.Unlock()
	b.mu.Lock()
	leaked := b.inSearchFromPanel
	b.mu.Unlock()
	if leaked {
		t.Fatal("from-user picker state leaked across App instances: package-level state (R14)")
	}
	// The frame snapshot carries the flag so layout code never reads it from
	// anywhere but its own window's frame (the pure-frame read pattern).
	// snapshot() takes a.mu itself — holding it here would self-deadlock
	// (the exact bug CI run 41174703134 caught: this test hung the whole
	// native gui package for its 10-minute timeout).
	f := a.snapshot()
	if !f.inSearchFromPanel {
		t.Fatal("snapshot() dropped inSearchFromPanel: the frame must carry the picker-open flag")
	}
}
