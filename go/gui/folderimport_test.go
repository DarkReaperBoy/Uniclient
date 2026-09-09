package gui

// Folder import dialog (slice 94, matrix row 67): escTarget
// self-handling and the content-pane dialog priority entry.

import (
	"testing"
)

func TestEscTargetFolderImportSelfHandled(t *testing.T) {
	f := frame{folderImportDlg: &folderImportState{accountID: "a"}, menu: &menuTarget{}}
	if got := escTarget(f); got != "" {
		t.Errorf("folderImportDlg + menu: escTarget = %q, want empty (dialog consumes Esc)", got)
	}
}

func TestContentPaneDialogSurfaceFolderImport(t *testing.T) {
	f := frame{folderImportDlg: &folderImportState{accountID: "a"}, settingsOpen: true}
	if got := contentDialogSurface(f); got != "folderImport" {
		t.Errorf("folderImport + settings: = %q, want folderImport", got)
	}
	if got := contentDialogSurface(frame{}); got != "" {
		t.Errorf("empty frame = %q, want \"\"", got)
	}
}
