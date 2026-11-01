package cores

import (
	"strings"
	"testing"
)

func TestJoinGroupCallClosesStaleConfPeers(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv.URL)
	t.Cleanup(func() {
		core.groupMu.Lock()
		if core.groupRenew != nil {
			core.groupRenew()
		}
		core.groupMu.Unlock()
	})
	_, stale := seedCallState(t, core)

	sess, err := core.JoinGroupCall("!room:test")
	if err != nil {
		t.Fatalf("JoinGroupCall: %v", err)
	}
	if sess.ID == "conf_x" || strings.HasPrefix(sess.ID, "conf_x") {
		t.Fatalf("setup: expected a DIFFERENT conf, got %s", sess.ID)
	}

	if stale.State != CallStateEnded {
		t.Errorf("stale peer not closed after conf change: state=%v", stale.State)
	}
	core.groupMu.Lock()
	_, survived := core.groupPeers[groupPeerKey("@bob:test", "BOB1")]
	confNow := core.groupConfID
	core.groupMu.Unlock()
	if survived {
		t.Errorf("stale conf_x peer still registered after joining %s", confNow)
	}
}
