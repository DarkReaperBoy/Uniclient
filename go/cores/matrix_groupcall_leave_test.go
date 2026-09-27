package cores

import (
	"strings"
	"testing"

	"maunium.net/go/mautrix/id"
)

// B-6 follow-up (F-63, found+fixed same slice): EndCall only knew the 1:1 table — a
// group conf ID is never in activeCalls, so the GUI's hang-up returned
// ErrNotFound: the user could NOT leave a group call, membership kept
// renewing forever, and voice kept flowing.
//
// RED (behavioral, WORKLOG 301): current EndCall returns `not found`
// for the conf id and the conf stays joined.

// TestEndCallLeavesGroupCall pins the full leave contract: renewal
// canceled, conf cleared, mesh peers closed, empty membership
// published (MSC3401: leave the call, stay in the room), unknown 1:1
// ids keep reporting not-found.
func TestEndCallLeavesGroupCall(t *testing.T) {
	srv, puts := newMeshHomeserver(t)
	core := seededMeshCore(t, srv.URL) // conf_x + bob member

	// A live peer connection, as reconcile would create.
	pc, err := core.createPeerConnection()
	if err != nil {
		t.Fatalf("pc: %v", err)
	}
	key := groupPeerKey("@bob:test", "BOB1")
	renewCanceled := false
	core.groupMu.Lock()
	core.groupPeers = map[string]*matrixCall{key: {
		ID: "conf_x", RoomID: id.RoomID("!room:test"), GroupConf: "conf_x",
		pc: pc,
	}}
	// context.CancelFunc is just a func() — watch that leave calls it.
	core.groupRenew = func() { renewCanceled = true }
	core.groupMu.Unlock()

	if err := core.EndCall("conf_x"); err != nil {
		t.Fatalf("EndCall(conf) = %v, want nil (leave the group call)", err)
	}
	if !renewCanceled {
		t.Fatal("renewal was not canceled — membership would renew forever")
	}
	core.groupMu.Lock()
	conf := core.groupConfID
	peers := len(core.groupPeers)
	core.groupMu.Unlock()
	if conf != "" {
		t.Fatalf("conf still joined after EndCall: %s", conf)
	}
	if peers != 0 {
		t.Fatalf("%d mesh peers still open after EndCall", peers)
	}
	if cs, err := core.GetGroupCall("!room:test"); err != nil || cs != nil {
		t.Fatalf("GetGroupCall after leave: cs=%v err=%v, want (nil,nil)", cs, err)
	}

	// Membership must be published with an EMPTY calls array so the
	// other side's reconcile closes its peer too.
	var leaveBody string
	for _, p := range puts.snapshot() {
		if p.Kind == "state" && p.Type == matrixCallMemberEventType && strings.Contains(p.Body, `"m.calls":[]`) {
			leaveBody = p.Body
		}
	}
	if leaveBody == "" {
		t.Fatalf("no empty-membership leave published; puts=%+v", puts.snapshot())
	}

	// Unknown 1:1 ids still report not-found (existing contract).
	if err := core.EndCall("nope"); err == nil {
		t.Fatal("EndCall(unknown) must stay ErrNotFound")
	}
}

// TestSendVoiceFrameAfterLeaveIsNoop: leaving tears the fan-out down —
// a late mic frame must not touch anything and must not error.
func TestSendVoiceFrameAfterLeaveIsNoop(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv.URL)
	if err := core.reconcileGroupMesh(); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if err := core.EndCall("conf_x"); err != nil {
		t.Fatalf("EndCall: %v", err)
	}
	if err := core.SendVoiceFrame([]byte{0xf8, 0xff, 0xfe}); err != nil {
		t.Fatalf("SendVoiceFrame after leave: %v", err)
	}
}
