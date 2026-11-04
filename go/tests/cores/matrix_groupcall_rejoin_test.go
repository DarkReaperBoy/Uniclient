package tests

import (
	"testing"
	. "uniclient/cores"
)

func TestJoinGroupCallClosesStaleConfPeers(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv)
	_, stale := seedCallState(t, core)
	srv.setCallConf("conf_new")

	sess, err := core.JoinGroupCall("!room:test")
	if err != nil {
		t.Fatalf("JoinGroupCall: %v", err)
	}
	if sess.ID != "conf_new" {
		t.Fatalf("setup: conf = %s, want conf_new (server started a new call)", sess.ID)
	}

	if stale.State != CallStateEnded {
		t.Errorf("stale peer not closed after conf change: state=%v", stale.State)
	}
	core.ForTestGroupMu().Lock()
	_, survived := core.ForTestGroupPeers()[GroupPeerKey("@bob:test", "BOB1")]
	core.ForTestGroupMu().Unlock()
	if survived {
		t.Errorf("stale conf_x peer still registered after joining %s", sess.ID)
	}
}
