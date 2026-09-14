package gui

import (
	"testing"

	"uniclient/cores"
)

// Saved Messages sublists (slice 197): the pure GUI halves — the
// sublist-row ordering (pinned first, then newest activity), the bar
// title of an open sublist scope, and the row preview text.

func TestSortSavedSublists(t *testing.T) {
	// Slice 204: the pinned block preserves the SERVER order (the pin
	// order — messages.getSavedDialogs returns it, and reordering must
	// be visible); only the unpinned tail falls back to newest-first.
	lists := []cores.SavedSublistInfo{
		{PeerID: "1", PeerName: "older", LastMsgTime: 100},
		{PeerID: "2", PeerName: "pinned old", IsPinned: true, LastMsgTime: 50},
		{PeerID: "3", PeerName: "newest", LastMsgTime: 300},
		{PeerID: "4", PeerName: "pinned newer", IsPinned: true, LastMsgTime: 900},
	}
	got := sortSavedSublists(lists)
	if len(got) != 4 || got[0].PeerID != "2" || got[1].PeerID != "4" || got[2].PeerID != "3" || got[3].PeerID != "1" {
		t.Fatalf("order = %v %v %v %v, want pinned server order (2,4) → newest(3) → older(1)",
			got[0].PeerID, got[1].PeerID, got[2].PeerID, got[3].PeerID)
	}
	// Input not mutated.
	if lists[0].PeerID != "1" {
		t.Errorf("input slice was mutated")
	}
}

// TestSavedSublistMenuActions (slice 204): pinned rows get the move
// entries (bounded by the block edges), every row gets pin-toggle +
// the destructive delete entry.
func TestSavedSublistMenuActions(t *testing.T) {
	if got := savedSublistMenuActions(true, false, true); len(got) != 3 ||
		got[0] != "Unpin" || got[1] != "Move down" || got[2] != "Delete messages" {
		t.Errorf("pinned top = %v", got)
	}
	if got := savedSublistMenuActions(true, true, false); got[0] != "Unpin" ||
		!savedMenuHas(got, "Move up") || savedMenuHas(got, "Move down") {
		t.Errorf("pinned bottom = %v", got)
	}
	if got := savedSublistMenuActions(true, true, true); len(got) != 4 {
		t.Errorf("pinned middle = %v", got)
	}
	if got := savedSublistMenuActions(false, false, false); len(got) != 2 ||
		got[0] != "Pin" || got[1] != "Delete messages" {
		t.Errorf("unpinned = %v", got)
	}
}

// TestSavedSublistMovePeers (slice 204): moving inside the pinned block
// swaps exactly the two neighbors; moving at the block edge is a no-op.
func TestSavedSublistMovePeers(t *testing.T) {
	lists := []cores.SavedSublistInfo{
		{PeerID: "a", IsPinned: true},
		{PeerID: "b", IsPinned: true},
		{PeerID: "c", IsPinned: true},
		{PeerID: "d"},
	}
	if got := savedSublistMovePeers(lists, 1, -1); len(got) != 3 || got[0] != "b" || got[1] != "a" || got[2] != "c" {
		t.Errorf("move up = %v", got)
	}
	if got := savedSublistMovePeers(lists, 1, 1); len(got) != 3 || got[0] != "a" || got[1] != "c" || got[2] != "b" {
		t.Errorf("move down = %v", got)
	}
	if got := savedSublistMovePeers(lists, 0, -1); got[0] != "a" || got[1] != "b" || got[2] != "c" {
		t.Errorf("edge move up = %v (want no-op)", got)
	}
	if got := savedSublistMovePeers(lists, 2, 1); got[0] != "a" || got[1] != "b" || got[2] != "c" {
		t.Errorf("edge move down = %v (want no-op)", got)
	}
}

func savedMenuHas(xs []string, s string) bool {
	for _, x := range xs {
		if x == s {
			return true
		}
	}
	return false
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

// TestSavedTagBarTitle (slice 199): the tag scope's bar title.
func TestSavedTagBarTitle(t *testing.T) {
	if got := savedTagBarTitle("🔥", "Important"); got != "Tag 🔥 · Important" {
		t.Errorf("titled = %q", got)
	}
	if got := savedTagBarTitle("🔥", ""); got != "Tag 🔥" {
		t.Errorf("bare emoji = %q", got)
	}
}

// TestSavedTagRowLabel (slice 199): tag row titles with fallbacks.
func TestSavedTagRowLabel(t *testing.T) {
	if got := savedTagRowLabel(cores.SavedReactionTagInfo{Emoji: "❤", Title: "Favorites"}); got != "Favorites" {
		t.Errorf("titled = %q", got)
	}
	if got := savedTagRowLabel(cores.SavedReactionTagInfo{Emoji: "❤"}); got != "❤" {
		t.Errorf("fallback = %q, want the emoji", got)
	}
}

// TestTagsSectionVisible (slice 199): honest premium gating.
func TestTagsSectionVisible(t *testing.T) {
	tags := []cores.SavedReactionTagInfo{{Emoji: "🔥", Count: 3}}
	if tagsSectionVisible(true, tags) != true {
		t.Error("premium with tags must show the section")
	}
	if tagsSectionVisible(false, tags) {
		t.Error("non-premium must never see the section (dead UI ban)")
	}
	if tagsSectionVisible(true, nil) {
		t.Error("no tags on the server = no section (nothing to show)")
	}
}
