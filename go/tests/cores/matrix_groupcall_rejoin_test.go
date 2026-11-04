package tests

import (
	"testing"
	"time"
	. "uniclient/cores"
)

func TestJoinGroupCallClosesStaleConfPeers(t *testing.T) {
	srv, puts := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)
	uc := seedCallState(t, srv, core)
	srv.setCallConf("conf_new")

	sess, err := core.JoinGroupCall("!room:test")
	if err != nil {
		t.Fatalf("JoinGroupCall: %v", err)
	}
	if sess.ID != "conf_new" {
		t.Fatalf("setup: conf = %s, want conf_new (server started a new call)", sess.ID)
	}

	if !uc.groupPeerEnded("@bob:test") {
		t.Error("stale peer not closed after conf change (no per-peer Ended update)")
	}

	fireGroupMemberEvent(t, core, "@bob:test", MatrixCallMemberContent{Calls: []MatrixCallMemberCall{{
		CallID: "conf_new",
		Devices: []MatrixCallDevice{{DeviceID: "BOB1", SessionID: "bs2",
			ExpiresTS: time.Now().UnixMilli() + 60_000}},
	}}})
	if err := core.ReconcileGroupMesh(); err != nil {
		t.Fatalf("reconcile on the new conf: %v", err)
	}
	waitForCond(t, func() bool { return countConfInvites(puts, "conf_new") == 1 },
		"mesh not re-established on the new conf after the stale sweep")
}
