package tests

import (
	"strings"
	"testing"
	. "uniclient/cores"

	"maunium.net/go/mautrix/id"
)

func TestEndCallLeavesGroupCall(t *testing.T) {
	srv, puts := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)

	pc, err := core.CreatePeerConnection()
	if err != nil {
		t.Fatalf("pc: %v", err)
	}
	key := GroupPeerKey("@bob:test", "BOB1")
	renewCanceled := false
	core.ForTestGroupMu().Lock()
	core.ForTestSetGroupPeers(map[string]*MatrixCall{key: ForTestNewMatrixCall("conf_x", "conf_x", id.RoomID("!room:test"), "", pc)})
	core.ForTestSetGroupRenew(func() { renewCanceled = true })
	core.ForTestGroupMu().Unlock()

	if err := core.EndCall("conf_x"); err != nil {
		t.Fatalf("EndCall(conf) = %v, want nil (leave the group call)", err)
	}
	if !renewCanceled {
		t.Fatal("renewal was not canceled — membership would renew forever")
	}
	core.ForTestGroupMu().Lock()
	conf := core.ForTestGroupConfID()
	peers := len(core.ForTestGroupPeers())
	core.ForTestGroupMu().Unlock()
	if conf != "" {
		t.Fatalf("conf still joined after EndCall: %s", conf)
	}
	if peers != 0 {
		t.Fatalf("%d mesh peers still open after EndCall", peers)
	}
	if cs, err := core.GetGroupCall("!room:test"); err != nil || cs != nil {
		t.Fatalf("GetGroupCall after leave: cs=%v err=%v, want (nil,nil)", cs, err)
	}

	var leaveBody string
	for _, p := range puts.snapshot() {
		if p.Kind == "state" && p.Type == MatrixCallMemberEventType && strings.Contains(p.Body, `"m.calls":[]`) {
			leaveBody = p.Body
		}
	}
	if leaveBody == "" {
		t.Fatalf("no empty-membership leave published; puts=%+v", puts.snapshot())
	}

	if err := core.EndCall("nope"); err == nil {
		t.Fatal("EndCall(unknown) must stay ErrNotFound")
	}
}

func TestSendVoiceFrameAfterLeaveIsNoop(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)
	if err := core.ReconcileGroupMesh(); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if err := core.EndCall("conf_x"); err != nil {
		t.Fatalf("EndCall: %v", err)
	}
	if err := core.SendVoiceFrame([]byte{0xf8, 0xff, 0xfe}); err != nil {
		t.Fatalf("SendVoiceFrame after leave: %v", err)
	}
}
