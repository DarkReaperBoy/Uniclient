package gui

// Group-call screen (AyuGram parity slice 102): once the user joins a group
// call (call bar Join button), the Voice tab becomes a real call screen —
// participant rows with speaking/muted/hand/video states from the engine's
// polled GroupCallInfo, plus mute / raise-hand / leave controls dispatching
// real engine calls. Pure derivations locked here.

import (
	"testing"

	"uniclient/engine"
)

func TestGCSelfLookup(t *testing.T) {
	ps := []engine.GroupCallParticipant{
		{UserID: "1", DisplayName: "Alice"},
		{UserID: "2", DisplayName: "Bob"},
	}
	if p := gcSelf(ps, "2"); p == nil || p.DisplayName != "Bob" {
		t.Fatalf("self lookup failed: %+v", p)
	}
	if p := gcSelf(ps, "9"); p != nil {
		t.Fatalf("absent self must return nil, got %+v", p)
	}
	if p := gcSelf(nil, "1"); p != nil {
		t.Fatalf("nil list → nil, got %+v", p)
	}
}

func TestGCSelfMuted(t *testing.T) {
	ps := []engine.GroupCallParticipant{
		{UserID: "2", DisplayName: "Bob", IsMuted: true},
	}
	// Self present → server truth wins over the optimistic local mirror.
	if !gcSelfMuted(ps, "2", false) {
		t.Fatal("server muted state must win when self is present")
	}
	// Self not yet in the list → the local mirror is the honest value.
	if !gcSelfMuted(ps, "9", true) {
		t.Fatal("self absent + localMuted=true must report muted")
	}
	if gcSelfMuted(ps, "9", false) {
		t.Fatal("self absent + localMuted=false must report unmuted")
	}
}

func TestGCShowRaiseHand(t *testing.T) {
	// Force-muted by admin (cannot self-unmute) → raise-hand offered.
	forced := []engine.GroupCallParticipant{{UserID: "2", IsMuted: true, CanSelfUnmute: false}}
	if !gcShowRaiseHand(forced, "2") {
		t.Fatal("force-muted self must see the raise-hand button")
	}
	// Self-muted (can unmute freely) → no hand button.
	selfMuted := []engine.GroupCallParticipant{{UserID: "2", IsMuted: true, CanSelfUnmute: true}}
	if gcShowRaiseHand(selfMuted, "2") {
		t.Fatal("self-muted-with-unmute must not see the raise-hand button")
	}
	// Unmuted → no hand button.
	unmuted := []engine.GroupCallParticipant{{UserID: "2", IsMuted: false}}
	if gcShowRaiseHand(unmuted, "2") {
		t.Fatal("unmuted self must not see the raise-hand button")
	}
	// Not in the list yet → no hand button (nothing to raise against).
	if gcShowRaiseHand(forced, "9") {
		t.Fatal("self absent → no raise-hand button")
	}
}

func TestGCRows(t *testing.T) {
	ps := []engine.GroupCallParticipant{
		{UserID: "1", DisplayName: "Alice", IsSpeaking: true},
		{UserID: "2", IsMuted: true, RaisedHandRating: 5},
		{UserID: "3", DisplayName: "Carol", HasVideo: true},
	}
	// No self in the list: plain mapping, order preserved.
	rows := gcRows(ps, "")
	if len(rows) != 3 {
		t.Fatalf("rows len = %d", len(rows))
	}
	if rows[0].name != "Alice" || !rows[0].speaking || rows[0].muted || rows[0].self {
		t.Fatalf("row0 = %+v", rows[0])
	}
	// Anonymous participant gets an honest fallback name.
	if rows[1].name != "Participant" || rows[1].self || !rows[1].muted || !rows[1].hand {
		t.Fatalf("row1 = %+v", rows[1])
	}
	if rows[2].name != "Carol" || !rows[2].video {
		t.Fatalf("row2 = %+v", rows[2])
	}
}

func TestGCCountLabel(t *testing.T) {
	if s := gcCountLabel(0); s != "no participants yet" {
		t.Fatalf("zero = %q", s)
	}
	if s := gcCountLabel(1); s != "1 participant" {
		t.Fatalf("one = %q", s)
	}
	if s := gcCountLabel(7); s != "7 participants" {
		t.Fatalf("many = %q", s)
	}
}

func TestGCJoinedTitle(t *testing.T) {
	if s := gcJoinedTitle(nil, "Fallback"); s != "Fallback" {
		t.Fatalf("nil info → %q", s)
	}
	gc := &engine.GroupCallInfo{Title: "Weekly Sync"}
	if s := gcJoinedTitle(gc, "Fallback"); s != "Weekly Sync" {
		t.Fatalf("titled call → %q", s)
	}
	gc.Title = ""
	if s := gcJoinedTitle(gc, "Fallback"); s != "Fallback" {
		t.Fatalf("empty title → %q", s)
	}
}

func TestGCRowsSortSelfFirst(t *testing.T) {
	ps := []engine.GroupCallParticipant{
		{UserID: "1", DisplayName: "Alice"},
		{UserID: "2", DisplayName: "Me"},
		{UserID: "3", DisplayName: "Carol"},
	}
	rows := gcRows(ps, "2")
	if rows[0].name != "Me" || !rows[0].self {
		t.Fatalf("self must sort first: %+v", rows[0])
	}
	if len(rows) != 3 {
		t.Fatalf("rows len = %d", len(rows))
	}
}
