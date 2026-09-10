package gui

// Save-to-Downloads GUI half (slice 99, matrix row 158): the context-menu
// gate, the viewer save plan, and the saveOnDone one-shot marks that turn
// a download completion into a Downloads copy.

import (
	"testing"

	"uniclient/engine"
)

func TestSaveToDownloadsMenuGate(t *testing.T) {
	cases := []struct {
		name string
		m    engine.CachedMessage
		want bool
	}{
		{"photo message", engine.CachedMessage{MsgID: "1", HasMedia: true, MediaType: engine.MediaImage}, true},
		{"voice note", engine.CachedMessage{MsgID: "2", HasMedia: true, MediaType: engine.MediaVoice}, true},
		{"gif", engine.CachedMessage{MsgID: "3", HasMedia: true, MediaType: engine.MediaGIF}, true},
		{"plain text", engine.CachedMessage{MsgID: "4"}, false},
		{"service row", engine.CachedMessage{MsgID: "5", HasMedia: true, IsService: true}, false},
	}
	for _, tc := range cases {
		if got := saveToDownloadsMenuGate(tc.m); got != tc.want {
			t.Errorf("%s: saveToDownloadsMenuGate = %v, want %v", tc.name, got, tc.want)
		}
	}
}

func TestViewerSavePlan(t *testing.T) {
	if got := viewerSavePlan(true); got != "copy" {
		t.Errorf("viewerSavePlan(true) = %q, want copy", got)
	}
	if got := viewerSavePlan(false); got != "download" {
		t.Errorf("viewerSavePlan(false) = %q, want download", got)
	}
}

func TestMenuActionsSaveToDownloads(t *testing.T) {
	m := engine.CachedMessage{
		AccountID: "a", ChatID: "c", MsgID: "m1",
		HasMedia: true, MediaType: engine.MediaFile, MediaLocalPath: "/cache/x.bin",
	}
	a := &App{}
	f := frame{menu: &menuTarget{msg: m}}
	found := false
	for _, it := range a.menuActionsFor(f, m) {
		if it.label == "Save to Downloads" {
			found = true
		}
	}
	if !found {
		t.Error("\"Save to Downloads\" missing for a media message")
	}
	// Text message → no item.
	m2 := engine.CachedMessage{AccountID: "a", ChatID: "c", MsgID: "m2"}
	f2 := frame{menu: &menuTarget{msg: m2}}
	for _, it := range a.menuActionsFor(f2, m2) {
		if it.label == "Save to Downloads" {
			t.Error("\"Save to Downloads\" present for a text message")
		}
	}
}

func TestSaveOnDoneMarks(t *testing.T) {
	a := &App{}
	a.setSaveOnDone("acct", "chat", "42", 0)
	if !a.consumeSaveOnDoneLocked("acct", "chat", "42", 0) {
		t.Fatal("consume after set = false, want true")
	}
	if a.consumeSaveOnDoneLocked("acct", "chat", "42", 0) {
		t.Error("second consume = true, want false (one-shot)")
	}
	// Independent of the open mark.
	a.setOpenOnDone("acct", "chat", "42", 0)
	a.setSaveOnDone("acct", "chat", "42", 0)
	if !a.consumeOpenOnDoneLocked("acct", "chat", "42", 0) {
		t.Error("open mark lost when save mark set")
	}
	if !a.consumeSaveOnDoneLocked("acct", "chat", "42", 0) {
		t.Error("save mark lost when open mark set")
	}
}
