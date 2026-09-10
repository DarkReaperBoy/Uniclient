package engine

// Folder export/import (slice 94, matrix row 67): pure encode/parse
// round-trips, validation, and the create-skip semantics.

import (
	"strings"
	"testing"
)

func sampleFolders() []FolderInfo {
	return []FolderInfo{
		{
			ID: "1", Name: "Work", Emoticon: "💼",
			ChatIDs:       []string{"10", "11"},
			PinnedChatIDs: []string{"10"},
			Groups:        true,
			ExcludeMuted:  true,
		},
		{
			ID: "2", Name: "News", Channels: true,
			ExcludeRead: true,
		},
	}
}

func TestFoldersExportRoundTrip(t *testing.T) {
	fs := sampleFolders()
	blob, err := encodeFoldersExport(fs)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(blob, `"uniclient_folders": 1`) {
		t.Fatalf("missing envelope marker: %s", blob[:80])
	}
	got, err := parseFoldersExport(blob)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 {
		t.Fatalf("parsed %d folders, want 2", len(got))
	}
	if got[0].Name != "Work" || got[0].Emoticon != "💼" {
		t.Errorf("f0 = %+v", got[0])
	}
	if len(got[0].Chats) != 2 || got[0].Chats[0] != "10" {
		t.Errorf("f0 chats = %v", got[0].Chats)
	}
	if !got[0].Groups || !got[0].ExcludeMuted || got[0].Channels {
		t.Errorf("f0 flags = %+v", got[0])
	}
	if !got[1].Channels || !got[1].ExcludeRead || got[1].Groups {
		t.Errorf("f1 flags = %+v", got[1])
	}
}

func TestParseFoldersExportValidation(t *testing.T) {
	if _, err := parseFoldersExport(""); err == nil {
		t.Error("empty accepted")
	}
	if _, err := parseFoldersExport("   "); err == nil {
		t.Error("blank accepted")
	}
	if _, err := parseFoldersExport("not json at all"); err == nil {
		t.Error("garbage accepted")
	}
	// Wrong / missing version marker.
	if _, err := parseFoldersExport(`{"folders":[{"name":"x"}]}`); err == nil {
		t.Error("missing version accepted")
	}
	if _, err := parseFoldersExport(`{"uniclient_folders":99,"folders":[{"name":"x"}]}`); err == nil {
		t.Error("wrong version accepted")
	}
	// Empty folder list.
	if _, err := parseFoldersExport(`{"uniclient_folders":1,"folders":[]}`); err == nil {
		t.Error("empty list accepted")
	}
	// Nameless folder.
	if _, err := parseFoldersExport(`{"uniclient_folders":1,"folders":[{"name":"  "}]}`); err == nil {
		t.Error("nameless folder accepted")
	}
}

func TestExportToOpts(t *testing.T) {
	o := exportToOpts(folderExport{
		Groups: true, ExcludeMuted: true, Emoticon: "⚡",
		Pinned: []string{"7"}, Exclude: []string{"9"},
	})
	if !o.Groups || !o.ExcludeMuted || o.Channels {
		t.Errorf("flags = %+v", o)
	}
	if o.Emoticon != "⚡" || len(o.PinnedChatIDs) != 1 || len(o.ExcludeChatIDs) != 1 {
		t.Errorf("opts = %+v", o)
	}
}
