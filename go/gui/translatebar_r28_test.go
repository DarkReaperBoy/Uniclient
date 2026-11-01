package gui

import "testing"

func TestTransPickerIsPerWindow(t *testing.T) {
	a, b := &App{}, &App{}
	a.mu.Lock()
	a.transPickerOpen = true
	a.mu.Unlock()
	b.mu.Lock()
	leaked := b.transPickerOpen
	b.mu.Unlock()
	if leaked {
		t.Fatal("translate picker state leaked across App instances: package-level state (R28)")
	}
	f := a.snapshot()
	if !f.transPickerOpen {
		t.Fatal("snapshot() dropped transPickerOpen: the frame must carry the picker-open flag")
	}
}
