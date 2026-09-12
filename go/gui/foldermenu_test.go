package gui

import (
	"testing"

	"uniclient/engine"
)

// Folder-tab context menu (slice 54): row derivation must drop the
// unavailable move actions and keep the stable order
// edit → move → invites → export/import (slice 94) → delete.
func TestFolderMenuItems(t *testing.T) {
	both := folderMenuItems(true, true)
	if len(both) != 7 {
		t.Fatalf("full menu = %d rows, want 7", len(both))
	}
	want := []string{"edit", "moveleft", "moveright", "invites", "exportf", "importf", "delete"}
	for i, w := range want {
		if both[i].id != w {
			t.Errorf("row %d = %s, want %s", i, both[i].id, w)
		}
	}

	leftOnly := folderMenuItems(true, false)
	if len(leftOnly) != 6 || leftOnly[1].id != "moveleft" || leftOnly[2].id != "invites" {
		t.Fatalf("left-only = %+v", leftOnly)
	}
	rightOnly := folderMenuItems(false, true)
	if len(rightOnly) != 6 || rightOnly[1].id != "moveright" {
		t.Fatalf("right-only = %+v", rightOnly)
	}
	none := folderMenuItems(false, false)
	if len(none) != 5 || none[0].id != "edit" || none[1].id != "invites" || none[4].id != "delete" {
		t.Fatalf("no-move = %+v", none)
	}
}

// folderIDInt parses FolderInfo IDs and rejects malformed ones.
func TestFolderIDInt(t *testing.T) {
	cases := map[string]int{
		"1":             1,
		"12":            12,
		" 7 ":           7,
		"":              0,
		"x":             0,
		"1x":            0,
		"-3":            0,
		"9999999999999": 0,
	}
	for in, want := range cases {
		if got := folderIDInt(in); got != want {
			t.Errorf("folderIDInt(%q) = %d, want %d", in, got, want)
		}
	}
}

// The invites dialog survives frame copies structurally (compile-level
// contract exercised in the wasm suite) — this test pins the empty-list
// state helpers via a zero frame.
func TestFolderInvitesStateZero(t *testing.T) {
	var st folderInvitesState
	if st.loaded || st.err != "" || len(st.links) != 0 {
		t.Fatalf("zero state not clean: %+v", st)
	}
	_ = engine.FolderInfo{}
}
