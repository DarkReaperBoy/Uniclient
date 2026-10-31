package gui

import "testing"

// R29 (§1.10 dead-UI class): the profile panel's Music section renders in
// EVERY window (the info panel is an every-window surface — R22's own
// finding), but its tap-through opens the playlist via layoutContentPaneDialog,
// which only the MAIN window ever renders (the separate branch returns before
// any content-pane dialog). In a separate chat window the button was shown
// and tappable but could only ever set invisible state — a dead button is
// forbidden ("what cannot work is HIDDEN, never faked"). The section is
// hidden in separate windows; the main window's panel for the same peer
// still shows it fully.
func TestProfileMusicHiddenInSeparateWindows(t *testing.T) {
	main := &App{}
	if !profileMusicSectionShown(main) {
		t.Fatal("main window must show the profile Music section")
	}
	sep := &App{separate: &chatKey{AccountID: "acc", ChatID: "chat"}}
	if profileMusicSectionShown(sep) {
		t.Fatal("separate windows never render the playlist dialog — the section must be hidden there (R29)")
	}
}
