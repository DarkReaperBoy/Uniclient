package tests

import (
	"testing"
	"time"
	. "uniclient/cores"
)

func TestTakeProofsDrainsStaleProof(t *testing.T) {
	tc := ForTestNewTsConnection(nil, nil, nil, false, nil, map[uint16]*TsPendingCmd{}, make(chan TsProof, 8), [2]map[uint16]*TsDecryptedPkt{}, [64]byte{})
	tc.ForTestFireProof("notifytextmessage", map[string]string{"invokerid": "5"})
	if !tc.ForTestTakeProofs() {
		t.Fatal("stale proof not drained")
	}
	if tc.ForTestTakeProofs() {
		t.Fatal("second take on empty channel reported a proof")
	}
}

func TestTSExecProofChannelSucceedsWithoutReply(t *testing.T) {
	core, tc, cleanup := newExecHarness(t)
	defer cleanup()

	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.ForTestFireProof("notifytextmessage", map[string]string{"invokerid": "5"})
	}()

	rows, err := core.TsExecProof("sendtextmessage targetmode=2 target=1 msg=proof",
		ForTestNewTsWant("invokerid", "notifytextmessage", "5"))
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
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 150 * time.Millisecond
	t.Cleanup(func() { TsExecVoidTimeout = old })

	if _, err := core.TsExec("clientupdate client_nickname=x"); err == nil {
		t.Fatal("silent server with no proof returned success — B-24 regression")
	}
}
