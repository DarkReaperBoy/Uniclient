package cores

import (
	"testing"
	"time"
)

// F-83 (slice 318, closes B-25): the in-client TS3 protocol does NOT
// reliably send `error id=0` success replies — proven on BOTH live
// servers (wire evidence, WORKLOG 318): clientupdate succeeded on
// 3.13.7 (notifyclientupdated broadcast) and on arcticblaze, yet
// tsExec's B-24 "silence = lost" rule returned a network error for
// the successful command; local sendtextmessage DELIVERED the message
// (peer received it) while the sender reported "response lost".
//
// Fix: in-band PROOF channel — for sendtextmessage the server's own
// notifytextmessage echo back to us (invokerID == self) is definitive
// proof the send was accepted, with or without an ok-line. tsExecProof
// accepts an optional proof channel (nil = old behavior, unchanged for
// every other command — TestTSExecSilentServerIsAnErrorNotFalseAck
// must keep passing).
//
// Seam-RED (WORKLOG 318): undefined: tsExecProof / selfEcho /
// takeSelfEcho.

func TestTakeProofsDrainsStaleProof(t *testing.T) {
	tc := &tsConnection{proofs: make(chan tsProof, 8)}
	// A stale proof from a PREVIOUS send must be drainable before the
	// next command — otherwise it would falsely satisfy the next exec.
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

	// No server reply will ever arrive; the in-band proof fires instead
	// (what SendMessage wires to the self-text echo).
	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.fireProof("notifytextmessage", map[string]string{"invokerid": "5"})
	}()

	rows, err := core.tsExecProof("sendtextmessage targetmode=2 target=1 msg=proof",
		&tsWant{name: "notifytextmessage", key: "invokerid", val: "5"})
	if err != nil {
		t.Fatalf("proof channel must count as success: %v", err)
	}
	// F-85: the proof's params come back as a result row.
	if len(rows) != 1 || rows[0]["invokerid"] != "5" {
		t.Fatalf("proof fields not returned as result row: %v", rows)
	}
}

func TestTSExecProofNilKeepsSilenceAnError(t *testing.T) {
	// Regression guard: without a proof channel, silence must stay the
	// B-24 error (the proof opt-in must not soften the default path).
	core, _, cleanup := newExecHarness(t)
	defer cleanup()
	old := tsExecVoidTimeout
	tsExecVoidTimeout = 150 * time.Millisecond
	t.Cleanup(func() { tsExecVoidTimeout = old })

	if _, err := core.tsExec("clientupdate client_nickname=x"); err == nil {
		t.Fatal("silent server with no proof returned success — B-24 regression")
	}
}
