package gui

import "testing"

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
