package tests

import (
	"strings"
	"testing"
	. "uniclient/cores"
)

func TestEndCallLeavesGroupCall(t *testing.T) {
	srv, puts := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)
	uc := newUpdateCapture(core)

	if err := core.ReconcileGroupMesh(); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	waitForRenewalTicks(t, puts, 3)

	if err := core.EndCall("conf_x"); err != nil {
		t.Fatalf("EndCall(conf) = %v, want nil (leave the group call)", err)
	}
	if !uc.groupPeerEnded("@bob:test") {
		t.Fatal("mesh peer not torn down after EndCall (no per-peer Ended update)")
	}
	if cs, err := core.GetGroupCall("!room:test"); err != nil || cs != nil {
		t.Fatalf("GetGroupCall after leave: cs=%v err=%v, want (nil,nil)", cs, err)
	}
	assertRenewalStopped(t, puts, "EndCall")

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
