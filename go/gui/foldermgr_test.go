package gui

import (
	"testing"

	"uniclient/engine"
)

func TestFolderMgrChatsLabel(t *testing.T) {
	cases := []struct {
		n    int
		want string
	}{
		{0, "0 chats"},
		{1, "1 chat"},
		{12, "12 chats"},
	}
	for _, c := range cases {
		if got := folderMgrChatsLabel(c.n); got != c.want {
			t.Errorf("folderMgrChatsLabel(%d) = %q, want %q", c.n, got, c.want)
		}
	}
}

func TestFolderSuggestsVisible(t *testing.T) {
	sug := []engine.SuggestedFolderInfo{
		{Name: "Unread", Description: "Chats with unread messages"},
		{Name: "Channels", Description: "Channels you subscribe to"},
		{Name: "Groups", Description: "Your groups"},
	}
	folders := []engine.FolderInfo{
		{ID: "1", Name: "Channels"},
		{ID: "2", Name: "Work"},
	}
	vis := folderSuggestsVisible(sug, folders)
	if len(vis) != 2 {
		t.Fatalf("visible suggestions = %d, want 2 (Channels exists)", len(vis))
	}
	if vis[0].Name != "Unread" || vis[1].Name != "Groups" {
		t.Fatalf("visible = %v", vis)
	}

	if got := folderSuggestsVisible(sug, nil); len(got) != 3 {
		t.Fatalf("no-folder case = %d, want 3", len(got))
	}

	if got := folderSuggestsVisible(nil, folders); len(got) != 0 {
		t.Fatalf("empty case = %d, want 0", len(got))
	}
}

func TestSwapFolderIDs(t *testing.T) {
	ids := []string{"1", "2", "3", "4"}

	got := swapFolderIDs(ids, 1, -1)
	want := []string{"2", "1", "3", "4"}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("move up = %v, want %v", got, want)
		}
	}

	got = swapFolderIDs(ids, 2, +1)
	want = []string{"1", "2", "4", "3"}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("move down = %v, want %v", got, want)
		}
	}

	for _, c := range []struct{ idx, delta int }{
		{0, -1}, {3, +1}, {-1, 0}, {4, -1},
	} {
		same := swapFolderIDs(ids, c.idx, c.delta)
		for i := range ids {
			if same[i] != ids[i] {
				t.Fatalf("clamp(%d,%d) = %v, want unchanged", c.idx, c.delta, same)
			}
		}
	}

	if ids[0] != "1" || ids[1] != "2" {
		t.Fatalf("input mutated: %v", ids)
	}
}
