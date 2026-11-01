package gui

import "testing"

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
	f := a.snapshot()
	if !f.inSearchFromPanel {
		t.Fatal("snapshot() dropped inSearchFromPanel: the frame must carry the picker-open flag")
	}
}
