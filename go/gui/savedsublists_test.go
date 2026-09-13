package gui

import (
	"testing"

	"uniclient/cores"
)

// Saved Messages sublists (slice 197): the pure GUI halves — the
// sublist-row ordering (pinned first, then newest activity), the bar
// title of an open sublist scope, and the row preview text.

func TestSortSavedSublists(t *testing.T) {
	lists := []cores.SavedSublistInfo{
		{PeerID: "1", PeerName: "older", LastMsgTime: 100},
		{PeerID: "2", PeerName: "pinned old", IsPinned: true, LastMsgTime: 50},
		{PeerID: "3", PeerName: "newest", LastMsgTime: 300},
	}
	got := sortSavedSublists(lists)
	if len(got) != 3 || got[0].PeerID != "2" || got[1].PeerID != "3" || got[2].PeerID != "1" {
		t.Fatalf("order = %v %v %v, want pinned(2) → newest(3) → older(1)", got[0].PeerID, got[1].PeerID, got[2].PeerID)
	}
	// Input not mutated.
	if lists[0].PeerID != "1" {
		t.Errorf("input slice was mutated")
	}
}

func TestSavedScopeBarTitle(t *testing.T) {
	if got := savedScopeBarTitle("My Channel"); got != "Saved from My Channel" {
		t.Errorf("titled = %q", got)
	}
	if got := savedScopeBarTitle(""); got != "Saved messages" {
		t.Errorf("empty = %q, want the generic title", got)
	}
}

func TestSavedSublistRowTitle(t *testing.T) {
	if got := savedSublistRowTitle(cores.SavedSublistInfo{PeerName: "Durov"}); got != "Durov" {
		t.Errorf("titled = %q", got)
	}
	if got := savedSublistRowTitle(cores.SavedSublistInfo{}); got != "Saved messages" {
		t.Errorf("fallback = %q, want Saved messages", got)
	}
}

func TestSavedSublistPreview(t *testing.T) {
	if got := savedSublistPreview(cores.SavedSublistInfo{LastMsgText: "hello"}); got != "hello" {
		t.Errorf("preview = %q", got)
	}
	long := ""
	for i := 0; i < 100; i++ {
		long += "x"
	}
	if got := savedSublistPreview(cores.SavedSublistInfo{LastMsgText: long}); len(got) != 61 {
		t.Errorf("long preview len = %d, want trimmed to 61 (58 + ellipsis)", len(got))
	}
	if got := savedSublistPreview(cores.SavedSublistInfo{}); got != "" {
		t.Errorf("empty preview = %q", got)
	}
}
