package cores

import (
	"testing"
	"time"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

// B-6 follow-up #3 (F-66, found+fixed same slice): MSC3401 says a
// device must be ignored "if the user's m.room.member event's
// membership field is not join". Our reconcile and GetGroupCall only
// looked at m.call.member content + expires_ts — so a user who LEFT
// THE ROOM kept a live mesh peer (audio still flowing to someone who
// was gone) until their lease expired, and kept counting as a
// participant.
//
// RED (behavioral, WORKLOG 303): reconcile creates the peer anyway and
// GetGroupCall counts the departed member.

// seedRoomMembership records room membership for the call room.
func seedRoomMembership(core *MatrixCore, mem map[id.UserID]event.Membership) {
	core.roomsMu.Lock()
	members := make(map[id.UserID]*matrixMember, len(mem))
	for uid, m := range mem {
		members[uid] = &matrixMember{UserID: uid, Membership: m}
	}
	core.rooms = map[id.RoomID]*matrixRoomState{
		id.RoomID("!room:test"): {ID: id.RoomID("!room:test"), Members: members},
	}
	core.roomsMu.Unlock()
}

// TestReconcileDropsRoomDepartedMembers: bob's m.call.member lease is
// still fresh, but his m.room.member says leave → no peer, no invite.
func TestReconcileDropsRoomDepartedMembers(t *testing.T) {
	srv, puts := newMeshHomeserver(t)
	core := seededMeshCore(t, srv.URL)
	seedRoomMembership(core, map[id.UserID]event.Membership{
		"@alice:test": event.MembershipJoin,
		"@bob:test":   event.MembershipLeave, // bob left the room
	})

	if err := core.reconcileGroupMesh(); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	core.groupMu.Lock()
	peers := len(core.groupPeers)
	core.groupMu.Unlock()
	if peers != 0 {
		t.Fatalf("mesh peer kept for a member who left the room: %d", peers)
	}
	for _, p := range puts.snapshot() {
		if p.Kind == "send" && p.Type == event.CallInvite.Type {
			t.Fatalf("invite sent to a departed member: %s", p.Body)
		}
	}
}

// TestHandleMemberEventDropsPeerWhenMemberLeavesRoom: the leave event
// must re-derive the mesh immediately — waiting half a lease (30 s) to
// drop someone who is GONE is too slow for a kicked-out room.
func TestHandleMemberEventDropsPeerWhenMemberLeavesRoom(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv.URL)
	seedRoomMembership(core, map[id.UserID]event.Membership{
		"@alice:test": event.MembershipJoin,
		"@bob:test":   event.MembershipJoin,
	})

	// Connected first (bob join → peer open).
	if err := core.reconcileGroupMesh(); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	core.groupMu.Lock()
	n := len(core.groupPeers)
	core.groupMu.Unlock()
	if n != 1 {
		t.Fatalf("setup: peers = %d, want 1", n)
	}

	// Bob leaves the room (m.room.member state event).
	sk := "@bob:test"
	evt := &event.Event{
		Type:     event.StateMember,
		RoomID:   id.RoomID("!room:test"),
		Sender:   "@bob:test",
		StateKey: &sk,
		Content:  event.Content{VeryRaw: []byte(`{"membership":"leave"}`)},
	}
	core.handleMemberEvent(evt)

	core.groupMu.Lock()
	n = len(core.groupPeers)
	core.groupMu.Unlock()
	if n != 0 {
		t.Fatalf("peer to the departed member still open: %d (reconcile not triggered by the member event)", n)
	}
}

// TestGetGroupCallExcludesNonJoinMembers: departed members must not
// count as call participants (spec: ignore devices whose m.room.member
// membership is not join).
func TestGetGroupCallExcludesNonJoinMembers(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv.URL) // bob has a fresh call lease

	// Unknown room membership → conservative keep (count = 1).
	cs, err := core.GetGroupCall("!room:test")
	if err != nil || cs == nil {
		t.Fatalf("GetGroupCall: cs=%v err=%v", cs, err)
	}
	if cs.Meta["participants_count"] != "1" {
		t.Fatalf("unknown membership: count = %q, want 1", cs.Meta["participants_count"])
	}

	// Membership known and not join → excluded.
	seedRoomMembership(core, map[id.UserID]event.Membership{
		"@alice:test": event.MembershipJoin,
		"@bob:test":   event.MembershipLeave,
	})
	cs, err = core.GetGroupCall("!room:test")
	if err != nil || cs == nil {
		t.Fatalf("GetGroupCall after leave: cs=%v err=%v", cs, err)
	}
	if cs.Meta["participants_count"] != "0" {
		t.Fatalf("departed member still counted: count = %q, want 0", cs.Meta["participants_count"])
	}
	if len(cs.Participants) != 0 {
		t.Fatalf("departed member still listed: %+v", cs.Participants)
	}
	_ = time.Now
}
