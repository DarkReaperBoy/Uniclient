package tests

import (
	"strings"
	"testing"
	. "uniclient/cores"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

func seedCallState(t *testing.T, srv *meshServer, core *MatrixCore) *updateCapture {
	t.Helper()
	uc := newUpdateCapture(core)
	if err := core.ReconcileGroupMesh(); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	waitForRenewalTicks(t, srv.puts, 3)
	return uc
}

func assertCallTornDown(t *testing.T, srv *meshServer, core *MatrixCore, uc *updateCapture, what string) {
	t.Helper()
	if !uc.groupPeerEnded("@bob:test") {
		t.Errorf("%s: mesh peer not torn down (no per-peer Ended update)", what)
	}
	if cs, _ := core.GetGroupCall("!room:test"); cs != nil {
		t.Errorf("%s: call still observable through GetGroupCall: %s", what, cs.ID)
	}
	assertRenewalStopped(t, srv.puts, what)
}

func assertCallKept(t *testing.T, srv *meshServer, core *MatrixCore, uc *updateCapture, what string) {
	t.Helper()
	mark := countMembershipPuts(srv.puts)
	waitForRenewalTicks(t, srv.puts, mark+2)
	if uc.groupPeerEnded("@alice:test") || uc.groupPeerEnded("@bob:test") {
		t.Errorf("%s: peer torn down", what)
	}
	if cs, err := core.GetGroupCall("!room:test"); err != nil || cs == nil || cs.ID != "conf_x" {
		t.Errorf("%s: call no longer observable: cs=%+v err=%v", what, cs, err)
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
	uc := seedCallState(t, srv, core)

	if err := core.LeaveChat("!room:test"); err != nil {
		t.Fatalf("LeaveChat: %v", err)
	}
	assertCallTornDown(t, srv, core, uc, "LeaveChat")

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
	uc := seedCallState(t, srv, core)

	if err := core.LeaveChat("!other:test"); err != nil {
		t.Fatalf("LeaveChat(other): %v", err)
	}
	assertCallKept(t, srv, core, uc, "unrelated LeaveChat")
}

func TestLogoutWhileInCallTearsDown(t *testing.T) {
	srv, puts := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)
	uc := seedCallState(t, srv, core)

	if err := core.Logout(); err != nil {
		t.Fatalf("Logout: %v", err)
	}
	assertCallTornDown(t, srv, core, uc, "Logout")

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
	uc := seedCallState(t, srv, core)

	if err := core.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	assertCallTornDown(t, srv, core, uc, "Close")
}

func TestOwnMemberLeaveEndsGroupCall(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)
	uc := seedCallState(t, srv, core)

	sk := "@alice:test"
	evt := &event.Event{
		Type:     event.StateMember,
		RoomID:   id.RoomID("!room:test"),
		Sender:   "@bob:test",
		StateKey: &sk,
		Content:  event.Content{VeryRaw: []byte(`{"membership":"leave"}`)},
	}
	core.HandleMemberEvent(evt)

	assertCallTornDown(t, srv, core, uc, "own member-leave")
}

func TestOwnMemberJoinKeepsGroupCall(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)
	uc := seedCallState(t, srv, core)

	sk := "@alice:test"
	evt := &event.Event{
		Type:     event.StateMember,
		RoomID:   id.RoomID("!room:test"),
		Sender:   "@alice:test",
		StateKey: &sk,
		Content:  event.Content{VeryRaw: []byte(`{"membership":"join"}`)},
	}
	core.HandleMemberEvent(evt)

	assertCallKept(t, srv, core, uc, "join event")
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
			uc := seedCallState(t, srv, core)

			sk := "@alice:test"
			evt := &event.Event{
				Type:     event.StateMember,
				RoomID:   id.RoomID("!room:test"),
				Sender:   "@bob:test",
				StateKey: &sk,
				Content:  event.Content{VeryRaw: []byte(`{"membership":"` + tc.membership + `"}`)},
			}
			core.HandleMemberEvent(evt)

			assertCallKept(t, srv, core, uc, "membership="+tc.membership)
		})
	}
}

func TestOwnMemberBanEndsGroupCall(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)
	uc := seedCallState(t, srv, core)

	sk := "@alice:test"
	evt := &event.Event{
		Type:     event.StateMember,
		RoomID:   id.RoomID("!room:test"),
		Sender:   "@bob:test",
		StateKey: &sk,
		Content:  event.Content{VeryRaw: []byte(`{"membership":"ban"}`)},
	}
	core.HandleMemberEvent(evt)

	assertCallTornDown(t, srv, core, uc, "own member-ban")
}
