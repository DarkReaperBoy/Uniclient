package tests

import (
	"fmt"
	"strings"
	"testing"
	"time"
	. "uniclient/cores"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

func seedRoomMembership(t *testing.T, srv *meshServer, core *MatrixCore, mem map[id.UserID]event.Membership) {
	t.Helper()
	events := make([]string, 0, len(mem))
	for uid, m := range mem {
		events = append(events, fmt.Sprintf(`{"type":"m.room.member","state_key":%q,"content":{"membership":%q}}`, string(uid), string(m)))
	}
	srv.setRoomState("[" + strings.Join(events, ",") + "]")
	if _, err := core.GetChatInfo("!room:test"); err != nil {
		t.Fatalf("seed room membership: %v", err)
	}
}

func TestReconcileDropsRoomDepartedMembers(t *testing.T) {
	srv, puts := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)
	seedRoomMembership(t, srv, core, map[id.UserID]event.Membership{
		"@alice:test": event.MembershipJoin,
		"@bob:test":   event.MembershipLeave,
	})

	if err := core.ReconcileGroupMesh(); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	core.ForTestGroupMu().Lock()
	peers := len(core.ForTestGroupPeers())
	core.ForTestGroupMu().Unlock()
	if peers != 0 {
		t.Fatalf("mesh peer kept for a member who left the room: %d", peers)
	}
	for _, p := range puts.snapshot() {
		if p.Kind == "send" && p.Type == event.CallInvite.Type {
			t.Fatalf("invite sent to a departed member: %s", p.Body)
		}
	}
}

func TestHandleMemberEventDropsPeerWhenMemberLeavesRoom(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)
	seedRoomMembership(t, srv, core, map[id.UserID]event.Membership{
		"@alice:test": event.MembershipJoin,
		"@bob:test":   event.MembershipJoin,
	})

	if err := core.ReconcileGroupMesh(); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	core.ForTestGroupMu().Lock()
	n := len(core.ForTestGroupPeers())
	core.ForTestGroupMu().Unlock()
	if n != 1 {
		t.Fatalf("setup: peers = %d, want 1", n)
	}

	sk := "@bob:test"
	evt := &event.Event{
		Type:     event.StateMember,
		RoomID:   id.RoomID("!room:test"),
		Sender:   "@bob:test",
		StateKey: &sk,
		Content:  event.Content{VeryRaw: []byte(`{"membership":"leave"}`)},
	}
	core.HandleMemberEvent(evt)

	core.ForTestGroupMu().Lock()
	n = len(core.ForTestGroupPeers())
	core.ForTestGroupMu().Unlock()
	if n != 0 {
		t.Fatalf("peer to the departed member still open: %d (reconcile not triggered by the member event)", n)
	}
}

func TestGetGroupCallExcludesNonJoinMembers(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)

	cs, err := core.GetGroupCall("!room:test")
	if err != nil || cs == nil {
		t.Fatalf("GetGroupCall: cs=%v err=%v", cs, err)
	}
	if cs.Meta["participants_count"] != "1" {
		t.Fatalf("unknown membership: count = %q, want 1", cs.Meta["participants_count"])
	}

	seedRoomMembership(t, srv, core, map[id.UserID]event.Membership{
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
