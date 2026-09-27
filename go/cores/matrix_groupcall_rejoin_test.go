package cores

import (
	"strings"
	"testing"
)

// B-6 follow-up #4 (F-67, found+fixed same slice): JoinGroupCall's
// stale-peer sweep read `old := m.groupConfID` AFTER assigning
// `m.groupConfID = conf` — `old != conf` was dead code, so re-joining
// after the room's m.call state changed kept the OLD conf's mesh
// peers: matrixCall.GroupConf stayed stale, outgoing ICE candidates
// were tagged with the old conf_id and the remote (now on the new
// conf) dropped them — ICE could never complete again.
//
// RED (behavioral, WORKLOG 304): the stale peer survives the re-join.

func TestJoinGroupCallClosesStaleConfPeers(t *testing.T) {
	srv, _ := newMeshHomeserver(t)
	core := seededMeshCore(t, srv.URL) // groupConfID = conf_x
	// F-82: cancel the renewal this test spawns — the loop used to
	// survive the test (its first tick reads state long after cleanup)
	// and raced later tests' setup.
	t.Cleanup(func() {
		core.groupMu.Lock()
		if core.groupRenew != nil {
			core.groupRenew()
		}
		core.groupMu.Unlock()
	})
	_, stale := seedCallState(t, core) // peer bound to conf_x

	// The mini-server 404s the m.call state GET → JoinGroupCall mints a
	// NEW conf — exactly the "room's call changed under us" scenario.
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
