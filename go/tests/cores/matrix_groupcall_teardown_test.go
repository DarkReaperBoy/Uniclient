package tests

import (
	"strings"
	"testing"
	. "uniclient/cores"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

func seedCallState(t *testing.T, core *MatrixCore) (*bool, *MatrixCall) {
	t.Helper()
	canceled := false
	core.ForTestGroupMu().Lock()
	prevRenew := core.ForTestGroupRenew()
	core.ForTestSetGroupRenew(func() {
		canceled = true
		if prevRenew != nil {
			prevRenew()
		}
	})
	core.ForTestGroupMu().Unlock()
	if err := core.ReconcileGroupMesh(); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	core.ForTestGroupMu().Lock()
	call := core.ForTestGroupPeers()[GroupPeerKey("@bob:test", "BOB1")]
	core.ForTestGroupMu().Unlock()
	if call == nil {
		t.Fatal("setup: bob peer not created by reconcile")
	}
	return &canceled, call
}

func assertCallTornDown(t *testing.T, core *MatrixCore, canceled *bool, call *MatrixCall, what string) {
	t.Helper()
	if !*canceled {
		t.Errorf("%s: renewal not canceled — membership would publish forever", what)
	}
	core.ForTestGroupMu().Lock()
	peers := len(core.ForTestGroupPeers())
	core.ForTestGroupMu().Unlock()
	if cs, _ := core.GetGroupCall("!room:test"); cs != nil {
		t.Errorf("%s: call still observable through GetGroupCall: %s", what, cs.ID)
	}
	if peers != 0 {
		t.Errorf("%s: %d mesh peers still open", what, peers)
	}
	if call.State != CallStateEnded {
		t.Errorf("%s: peer call state = %v, want ended", what, call.State)
	}
}

func putOrder(puts *meshPuts, kind string) (stateIdx, otherIdx int) {
	stateIdx, otherIdx = -1, -1
	for i, p := range puts.snapshot() {
		if p.Kind == "state" && p.Type == MatrixCallMemberEventType && containsEmptyCalls(p.Body) {
			stateIdx = i
		}
		if p.Kind == kind {
			otherIdx = i
		}
	}
	return stateIdx, otherIdx
}

func containsEmptyCalls(body string) bool {
	return strings.Contains(body, `"m.calls":[]`)
}

func TestLeaveChatWhileInCallTearsDown(t *testing.T) {
	srv, puts := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)
	canceled, call := seedCallState(t, core)

	if err := core.LeaveChat("!room:test"); err != nil {
		t.Fatalf("LeaveChat: %v", err)
	}
	assertCallTornDown(t, core, canceled, call, "LeaveChat")

	if err := core.SendVoiceFrame([]byte{0xf8, 0xff, 0xfe}); err != nil {
		t.Fatalf("SendVoiceFrame after LeaveChat: %v", err)
	}

	stateIdx, leaveIdx := putOrder(puts, "leave")
	if stateIdx < 0 {
		t.Fatalf("no empty-membership publish before leaving; puts=%+v", puts.snapshot())
	}
	if leaveIdx < 0 {
		t.Fatalf("no room-leave POST; puts=%+v", puts.snapshot())
	}
	if stateIdx > leaveIdx {
		t.Fatalf("empty membership (idx %d) published AFTER room leave (idx %d) — state write would 403", stateIdx, leaveIdx)
	}
}

func TestLeaveChatOtherRoomKeepsCall(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)
	canceled, _ := seedCallState(t, core)

	if err := core.LeaveChat("!other:test"); err != nil {
		t.Fatalf("LeaveChat(other): %v", err)
	}
	if *canceled {
		t.Fatal("leaving an unrelated room canceled the call's renewal")
	}
	cs, err := core.GetGroupCall("!room:test")
	if err != nil || cs == nil || cs.ID != "conf_x" {
		t.Fatalf("unrelated LeaveChat tore the call down: cs=%+v err=%v", cs, err)
	}
	core.ForTestGroupMu().Lock()
	peers := len(core.ForTestGroupPeers())
	core.ForTestGroupMu().Unlock()
	if peers != 1 {
		t.Fatalf("unrelated LeaveChat tore the call down: peers=%d", peers)
	}
}

func TestLogoutWhileInCallTearsDown(t *testing.T) {
	srv, puts := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)
	canceled, call := seedCallState(t, core)

	if err := core.Logout(); err != nil {
		t.Fatalf("Logout: %v", err)
	}
	assertCallTornDown(t, core, canceled, call, "Logout")

	stateIdx, logoutIdx := putOrder(puts, "logout")
	if stateIdx < 0 || logoutIdx < 0 {
		t.Fatalf("want empty-membership PUT then logout POST; puts=%+v", puts.snapshot())
	}
	if stateIdx > logoutIdx {
		t.Fatalf("empty membership (idx %d) AFTER logout (idx %d) — token already dead", stateIdx, logoutIdx)
	}
}

func TestCloseWhileInCallTearsDown(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)
	canceled, call := seedCallState(t, core)

	if err := core.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	assertCallTornDown(t, core, canceled, call, "Close")
}

func TestOwnMemberLeaveEndsGroupCall(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)
	canceled, call := seedCallState(t, core)

	sk := "@alice:test"
	evt := &event.Event{
		Type:     event.StateMember,
		RoomID:   id.RoomID("!room:test"),
		Sender:   "@bob:test",
		StateKey: &sk,
		Content:  event.Content{VeryRaw: []byte(`{"membership":"leave"}`)},
	}
	core.HandleMemberEvent(evt)

	assertCallTornDown(t, core, canceled, call, "own member-leave")
}

func TestOwnMemberJoinKeepsGroupCall(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)
	canceled, _ := seedCallState(t, core)

	sk := "@alice:test"
	evt := &event.Event{
		Type:     event.StateMember,
		RoomID:   id.RoomID("!room:test"),
		Sender:   "@alice:test",
		StateKey: &sk,
		Content:  event.Content{VeryRaw: []byte(`{"membership":"join"}`)},
	}
	core.HandleMemberEvent(evt)

	if *canceled {
		t.Fatal("renewal canceled by a join event")
	}
	if cs, err := core.GetGroupCall("!room:test"); err != nil || cs == nil || cs.ID != "conf_x" {
		t.Fatalf("join event tore the call down: cs=%+v err=%v", cs, err)
	}
	core.ForTestGroupMu().Lock()
	peers := len(core.ForTestGroupPeers())
	core.ForTestGroupMu().Unlock()
	if peers != 1 {
		t.Fatalf("join event tore the call down: peers=%d", peers)
	}
}

func TestOwnMemberNonDepartureKeepsGroupCall(t *testing.T) {
	for _, tc := range []struct {
		name       string
		membership string
	}{
		{"replayed invite", "invite"},
		{"malformed empty membership", ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			srv, _ := newMeshHomeserver(t)
			core := seededMeshCore(t, srv)
			canceled, call := seedCallState(t, core)

			sk := "@alice:test"
			evt := &event.Event{
				Type:     event.StateMember,
				RoomID:   id.RoomID("!room:test"),
				Sender:   "@bob:test",
				StateKey: &sk,
				Content:  event.Content{VeryRaw: []byte(`{"membership":"` + tc.membership + `"}`)},
			}
			core.HandleMemberEvent(evt)

			if *canceled {
				t.Fatalf("membership=%q event canceled the renewal — call torn down", tc.membership)
			}
			if cs, err := core.GetGroupCall("!room:test"); err != nil || cs == nil || cs.ID != "conf_x" {
				t.Fatalf("membership=%q event tore the call down: cs=%+v err=%v", tc.membership, cs, err)
			}
			core.ForTestGroupMu().Lock()
			peers := len(core.ForTestGroupPeers())
			core.ForTestGroupMu().Unlock()
			if peers != 1 || call.State == CallStateEnded {
				t.Fatalf("membership=%q event tore the call down: peers=%d state=%v",
					tc.membership, peers, call.State)
			}
		})
	}
}

func TestOwnMemberBanEndsGroupCall(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)
	canceled, call := seedCallState(t, core)

	sk := "@alice:test"
	evt := &event.Event{
		Type:     event.StateMember,
		RoomID:   id.RoomID("!room:test"),
		Sender:   "@bob:test",
		StateKey: &sk,
		Content:  event.Content{VeryRaw: []byte(`{"membership":"ban"}`)},
	}
	core.HandleMemberEvent(evt)

	assertCallTornDown(t, core, canceled, call, "own member-ban")
}
