package gui

import (
	"testing"

	"uniclient/engine"
)

// Folder editor state machine (gui/folders.go, slice 13).

func newDlgApp() *App { return &App{} }

func TestCycleFolderDlgChat(t *testing.T) {
	a := newDlgApp()
	a.folderDlg = &folderDlgState{include: map[string]bool{}, exclude: map[string]bool{}}

	// none → include
	a.cycleFolderDlgChat("c1")
	if !a.folderDlg.include["c1"] || a.folderDlg.exclude["c1"] {
		t.Fatalf("after 1st tap: include=%v exclude=%v", a.folderDlg.include["c1"], a.folderDlg.exclude["c1"])
	}
	// include → exclude
	a.cycleFolderDlgChat("c1")
	if a.folderDlg.include["c1"] || !a.folderDlg.exclude["c1"] {
		t.Fatalf("after 2nd tap: include=%v exclude=%v", a.folderDlg.include["c1"], a.folderDlg.exclude["c1"])
	}
	// exclude → none
	a.cycleFolderDlgChat("c1")
	if a.folderDlg.include["c1"] || a.folderDlg.exclude["c1"] {
		t.Fatalf("after 3rd tap: both should be clear")
	}
}

func TestCycleFolderDlgChatNoDialog(t *testing.T) {
	a := newDlgApp()
	a.cycleFolderDlgChat("c1") // must not panic with no dialog open
}

func TestSetFolderDlgFlag(t *testing.T) {
	a := newDlgApp()
	a.folderDlg = &folderDlgState{}
	for _, key := range []string{"contacts", "nonContacts", "groups", "channels", "bots", "exclMuted", "exclRead", "exclArchived"} {
		a.setFolderDlgFlag(key, true)
	}
	d := a.folderDlg
	if !(d.contacts && d.nonContacts && d.groups && d.channels && d.bots &&
		d.exclMuted && d.exclRead && d.exclArchived) {
		t.Fatalf("flags not all set: %+v", d)
	}
	a.setFolderDlgFlag("groups", false)
	if d.groups {
		t.Fatal("groups should have cleared")
	}
}

func TestSyncFolderDlgSwitches(t *testing.T) {
	st := &folderDlgState{groups: true, exclRead: true}
	syncFolderDlgSwitches(st)
	if !folderDlgSwitch("groups").Value || !folderDlgSwitch("exclRead").Value {
		t.Fatal("switches not synced from state")
	}
	if folderDlgSwitch("bots").Value {
		t.Fatal("bots should be off")
	}
}

func TestFolderDlgEmoticonsSet(t *testing.T) {
	if len(folderDlgEmoticons) < 6 {
		t.Fatalf("emoticon set too small: %d", len(folderDlgEmoticons))
	}
	seen := map[string]bool{}
	for _, e := range folderDlgEmoticons {
		if seen[e] {
			t.Fatalf("duplicate emoticon %q", e)
		}
		seen[e] = true
	}
}

func TestOpenFolderDlgEditPrefill(t *testing.T) {
	a := newDlgApp()
	folder := engine.FolderInfo{
		ID: "7", Name: "Work", ChatIDs: []string{"c1", "c2"},
		ExcludeChatIDs: []string{"c3"}, Groups: true, ExcludeRead: true,
		Emoticon: "🌟",
	}
	a.openFolderDlgEdit(folder)
	d := a.folderDlg
	if d == nil || d.editing != "7" || !d.include["c2"] || !d.exclude["c3"] || !d.groups || !d.exclRead {
		t.Fatalf("edit prefill = %+v", d)
	}
	if folderNameEditor.Text() != "Work" {
		t.Fatalf("name prefill = %q", folderNameEditor.Text())
	}
}
