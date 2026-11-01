package cores

import (
	"testing"
	"time"
)

func TestTakeProofsDrainsStaleProof(t *testing.T) {
	tc := &tsConnection{proofs: make(chan tsProof, 8)}
	tc.fireProof("notifytextmessage", map[string]string{"invokerid": "5"})
	if !tc.takeProofs() {
		t.Fatal("stale proof not drained")
	}
	if tc.takeProofs() {
		t.Fatal("second take on empty channel reported a proof")
	}
}

func TestTSExecProofChannelSucceedsWithoutReply(t *testing.T) {
	core, tc, cleanup := newExecHarness(t)
	defer cleanup()

	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.fireProof("notifytextmessage", map[string]string{"invokerid": "5"})
	}()

	rows, err := core.tsExecProof("sendtextmessage targetmode=2 target=1 msg=proof",
		&tsWant{name: "notifytextmessage", key: "invokerid", val: "5"})
	if err != nil {
		t.Fatalf("proof channel must count as success: %v", err)
	}
	if len(rows) != 1 || rows[0]["invokerid"] != "5" {
		t.Fatalf("proof fields not returned as result row: %v", rows)
	}
}

func TestTSExecProofNilKeepsSilenceAnError(t *testing.T) {
	core, _, cleanup := newExecHarness(t)
	defer cleanup()
	old := tsExecVoidTimeout
	tsExecVoidTimeout = 150 * time.Millisecond
	t.Cleanup(func() { tsExecVoidTimeout = old })

	if _, err := core.tsExec("clientupdate client_nickname=x"); err == nil {
		t.Fatal("silent server with no proof returned success — B-24 regression")
	}
}
