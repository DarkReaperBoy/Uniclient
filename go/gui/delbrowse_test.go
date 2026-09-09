package gui

// Deleted-messages browser (slice 97, matrix row 165): pure helpers — row
// preview naming, the header-menu gate, escTarget self-handling, and the
// menu-item list update.

import (
	"testing"

	"uniclient/engine"
)

func TestDeletedRowPreview(t *testing.T) {
	cases := []struct {
		name string
		m    engine.CachedMessage
		want string
	}{
		{
			"plain text",
			engine.CachedMessage{SenderName: "Alice", ContentText: "hello"},
			"Alice: hello",
		},
		{
			"sender fallback to id",
			engine.CachedMessage{SenderID: "u7", ContentText: "hi"},
			"user u7: hi",
		},
		{
			"no sender at all",
			engine.CachedMessage{ContentText: "hi"},
			"someone: hi",
		},
		{
			"first line only",
			engine.CachedMessage{SenderName: "Bob", ContentText: "one\ntwo"},
			"Bob: one",
		},
		{
			"media row uses label",
			engine.CachedMessage{SenderName: "Bob", HasMedia: true, MediaType: engine.MediaImage},
			"Bob: Photo",
		},
		{
			"empty text",
			engine.CachedMessage{SenderName: "Bob", ContentText: "   "},
			"Bob: (no text)",
		},
	}
	for _, tc := range cases {
		if got := deletedRowPreview(tc.m); got != tc.want {
			t.Errorf("%s: deletedRowPreview = %q, want %q", tc.name, got, tc.want)
		}
	}
}

func TestHeaderMenuHasViewDeleted(t *testing.T) {
	// Every chat type that can clear deleted messages can also browse them.
	for _, c := range []engine.ChatInfo{
		{AccountID: "a", ChatID: "u1", Type: engine.ChatTypeDMVal},
		{AccountID: "a", ChatID: "g1", Type: engine.ChatTypeGroupVal},
		{AccountID: "a", ChatID: "c1", Type: engine.ChatTypeChanVal},
	} {
		if !containsAction(headerMenuItems(c, false, false), "viewdeleted") {
			t.Errorf("chat type %d: view-deleted item missing", c.Type)
		}
	}
}

func TestEscTargetDeletedDlgSelfHandled(t *testing.T) {
	f := frame{deletedDlg: &deletedDlgState{}, headerMenu: &headerMenuTarget{}}
	if got := escTarget(f); got != "" {
		t.Errorf("deletedDlg + headerMenu: escTarget = %q, want empty (dialog consumes Esc)", got)
	}
}

func TestDeletedBrowseOrder(t *testing.T) {
	// Newest-first ordering for the browser rows.
	msgs := []engine.CachedMessage{
		{MsgID: "old", Timestamp: 100},
		{MsgID: "new", Timestamp: 300},
		{MsgID: "mid", Timestamp: 200},
	}
	got := sortDeletedNewest(msgs)
	want := []string{"new", "mid", "old"}
	for i := range want {
		if got[i].MsgID != want[i] {
			t.Errorf("sortDeletedNewest[%d] = %s, want %s", i, got[i].MsgID, want[i])
		}
	}
}
