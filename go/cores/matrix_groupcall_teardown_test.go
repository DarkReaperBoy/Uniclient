package cores

import (
	"strings"
	"testing"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

// B-6 follow-up #2 (F-64, found+fixed same slice): ONLY EndCall knew
// how to leave a group call. Leaving the ROOM (LeaveChat), logging
// out, or closing the core all left the call joined: the renewal
// goroutine kept publishing membership forever, mesh peers stayed
// open, and voice kept flowing with no way to stop it.
//
// RED (behavioral, WORKLOG 302): with the current code each of these
// leaves `core.groupConfID` set — `call still joined after LeaveChat`.

// seedCallState gives the core a conf + a live peer + a renewal
// watcher, and returns the watch flag + the peer call.
func seedCallState(t *testing.T, core *MatrixCore) (*bool, *matrixCall) {
	t.Helper()
	pc, err := core.createPeerConnection()
	if err != nil {
		t.Fatalf("pc: %v", err)
	}
	canceled := false
	call := &matrixCall{
		ID: "conf_x", RoomID: id.RoomID("!room:test"), GroupConf: "conf_x",
		State: CallStateConnecting, pc: pc,
	}
	core.groupMu.Lock()
	core.groupPeers = map[string]*matrixCall{
		groupPeerKey("@bob:test", "BOB1"): call,
	}
	core.groupRenew = func() { canceled = true }
	core.groupMu.Unlock()
	return &canceled, call
}

func assertCallTornDown(t *testing.T, core *MatrixCore, canceled *bool, call *matrixCall, what string) {
	t.Helper()
	if !*canceled {
		t.Errorf("%s: renewal not canceled — membership would publish forever", what)
	}
	core.groupMu.Lock()
	conf := core.groupConfID
	peers := len(core.groupPeers)
	core.groupMu.Unlock()
	if conf != "" {
		t.Errorf("%s: call still joined: %s", what, conf)
	}
	if peers != 0 {
		t.Errorf("%s: %d mesh peers still open", what, peers)
	}
	if call.State != CallStateEnded {
		t.Errorf("%s: peer call state = %v, want ended", what, call.State)
	}
}

// hasLeavePut returns the index of the empty-membership state PUT and
// of the given follow-up PUT, for order assertions.
func putOrder(puts *meshPuts, kind string) (stateIdx, otherIdx int) {
	stateIdx, otherIdx = -1, -1
	for i, p := range puts.snapshot() {
		if p.Kind == "state" && p.Type == matrixCallMemberEventType && containsEmptyCalls(p.Body) {
			stateIdx = i
		}
		if p.Kind == kind {
			otherIdx = i
		}
	}
	return stateIdx, otherIdx
}

// containsEmptyCalls matches the MSC3401 leave payload {"m.calls":[]}.
// (The first version had a `len >= 16` guard that rejected the 14-byte
// body — self-caught in slice 302: both order tests failed while the
// puts log showed the publish RIGHT THERE.)
func containsEmptyCalls(body string) bool {
	return strings.Contains(body, `"m.calls":[]`)
}

// TestLeaveChatWhileInCallTearsDown: leaving the room must leave the
// call first — the empty membership MUST precede the room leave (you
// cannot write state after leaving).
func TestLeaveChatWhileInCallTearsDown(t *testing.T) {
	srv, puts := newMeshHomeserver(t)
	core := seededMeshCore(t, srv.URL)
	canceled, call := seedCallState(t, core)

	if err := core.LeaveChat("!room:test"); err != nil {
		t.Fatalf("LeaveChat: %v", err)
	}
	assertCallTornDown(t, core, canceled, call, "LeaveChat")

	if cs, err := core.GetGroupCall("!room:test"); err != nil || cs != nil {
		t.Fatalf("GetGroupCall after LeaveChat: cs=%v err=%v, want (nil,nil)", cs, err)
	}
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

// TestLeaveChatOtherRoomKeepsCall: leaving an UNRELATED room must not
// tear down the active call.
func TestLeaveChatOtherRoomKeepsCall(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv.URL)
	canceled, _ := seedCallState(t, core)

	if err := core.LeaveChat("!other:test"); err != nil {
		t.Fatalf("LeaveChat(other): %v", err)
	}
	if *canceled {
		t.Fatal("leaving an unrelated room canceled the call's renewal")
	}
	core.groupMu.Lock()
	conf := core.groupConfID
	peers := len(core.groupPeers)
	core.groupMu.Unlock()
	if conf != "conf_x" || peers != 1 {
		t.Fatalf("unrelated LeaveChat tore the call down: conf=%q peers=%d", conf, peers)
	}
}

// TestLogoutWhileInCallTearsDown: logout must leave the call while the
// token still works (publish BEFORE client.Logout invalidates it).
func TestLogoutWhileInCallTearsDown(t *testing.T) {
	srv, puts := newMeshHomeserver(t)
	core := seededMeshCore(t, srv.URL)
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

// TestCloseWhileInCallTearsDown: Close's own doc comment promises it
// "ends active calls" — it must for group calls too.
func TestCloseWhileInCallTearsDown(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv.URL)
	canceled, call := seedCallState(t, core)

	if err := core.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	assertCallTornDown(t, core, canceled, call, "Close")
}

// TestOwnMemberLeaveEndsGroupCall (F-65): a m.room.member leave/ban
// for OUR OWN mxid in the call's room (kicked, banned, room dissolved)
// must end the call — otherwise the renewal goroutine and the mesh run
// forever with nothing to publish to.
//
// Behavioral RED (WORKLOG 302, hook swapped out): `call still joined`
// after the departure event.
func TestOwnMemberLeaveEndsGroupCall(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv.URL)
	canceled, call := seedCallState(t, core)

	sk := "@alice:test"
	evt := &event.Event{
		Type:     event.StateMember,
		RoomID:   id.RoomID("!room:test"),
		Sender:   "@bob:test", // an admin kicked us
		StateKey: &sk,
		Content:  event.Content{VeryRaw: []byte(`{"membership":"leave"}`)},
	}
	core.handleMemberEvent(evt)

	assertCallTornDown(t, core, canceled, call, "own member-leave")
}

// TestOwnMemberJoinKeepsGroupCall: a plain join/invite event for our
// own membership must NOT tear anything down (the hook is narrow).
func TestOwnMemberJoinKeepsGroupCall(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv.URL)
	canceled, _ := seedCallState(t, core)

	sk := "@alice:test"
	evt := &event.Event{
		Type:     event.StateMember,
		RoomID:   id.RoomID("!room:test"),
		Sender:   "@alice:test",
		StateKey: &sk,
		Content:  event.Content{VeryRaw: []byte(`{"membership":"join"}`)},
	}
	core.handleMemberEvent(evt)

	if !*canceled == false { // renewal must be untouched
		t.Fatal("renewal canceled by a join event")
	}
	core.groupMu.Lock()
	conf := core.groupConfID
	peers := len(core.groupPeers)
	core.groupMu.Unlock()
	if conf != "conf_x" || peers != 1 {
		t.Fatalf("join event tore the call down: conf=%q peers=%d", conf, peers)
	}
}
