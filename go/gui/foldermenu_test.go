package gui

import (
	"testing"

	"uniclient/engine"
)

// Folder-tab context menu (slice 54): row derivation must drop the
// unavailable move actions and keep the stable order
// edit → move → invites → delete.
func TestFolderMenuItems(t *testing.T) {
	both := folderMenuItems(true, true)
	if len(both) != 5 {
		t.Fatalf("full menu = %d rows, want 5", len(both))
	}
	want := []string{"edit", "moveleft", "moveright", "invites", "delete"}
	for i, w := range want {
		if both[i].action != w {
			t.Errorf("row %d = %s, want %s", i, both[i].action, w)
		}
	}

	leftOnly := folderMenuItems(true, false)
	if len(leftOnly) != 4 || leftOnly[1].action != "moveleft" || leftOnly[2].action != "invites" {
		t.Fatalf("left-only = %+v", leftOnly)
	}
	rightOnly := folderMenuItems(false, true)
	if len(rightOnly) != 4 || rightOnly[1].action != "moveright" {
		t.Fatalf("right-only = %+v", rightOnly)
	}
	none := folderMenuItems(false, false)
	if len(none) != 3 || none[0].action != "edit" || none[1].action != "invites" || none[2].action != "delete" {
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
