package gui

import "testing"

// R28 (R14/B-47 class): the translate bar's language-picker open flag must
// be PER-WINDOW state on App, never package-level. The bar renders in every
// window whose chat has translation on (chat.go gates on the per-chat
// chatTranslateOn, then layoutTranslateBar), so a package transPickerOpen
// meant: opening the picker in window A also expanded it in window B's chat,
// and picking a language (or closing) in either window flipped BOTH —
// cross-window UI bleed, layout-written, frameMu-serialized so no data race,
// exactly the inSearchFromPanel shape R14 fixed.
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
	// The frame snapshot carries the flag so layout reads are pure-frame
	// reads (snapshot() takes a.mu itself — do not hold the lock here).
	f := a.snapshot()
	if !f.transPickerOpen {
		t.Fatal("snapshot() dropped transPickerOpen: the frame must carry the picker-open flag")
	}
}
