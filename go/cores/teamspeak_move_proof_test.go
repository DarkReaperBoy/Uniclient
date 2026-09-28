package cores

import (
	"testing"
	"time"
)

// F-84 (slice 319, closes B-58): the in-client TS3 protocol omits
// `error id=0` success replies for OTHER no-data commands too —
// wire-proven for `clientmove` (WORKLOG 319: the server broadcast
// `notifyclientmoved ctid=2 reasonid=0 clid=37` while tsExec reported
// "response lost"; same probe on clientupdate in slice 318). F-83
// fixed only sendtextmessage via its selfEcho channel; this slice
// generalizes that channel into a TYPED proof (name + clid) and wires
// every no-data command whose success the server broadcasts:
//   clientmove   → notifyclientmoved  (clid = the moved client)
//   clientupdate → notifyclientupdated (clid = self)
//
// The name+clid match is the anti-false-ack guard (B-24): an
// unrelated concurrent event must NOT satisfy a pending command, and
// a stale proof from a previous command must be drained before send.
//
// Seam-RED (WORKLOG 319): undefined: tsProof / fireProof.

// TestProofMatchingClidSucceeds: the broadcast about EXACTLY the
// pending command's target counts as success (silent-success servers).
func TestProofMatchingClidSucceeds(t *testing.T) {
	core, tc, cleanup := newExecHarness(t)
	defer cleanup()

	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.fireProof("notifyclientmoved", "7")
	}()
	if _, err := core.tsExecProof("clientmove clid=7 cid=2",
		&tsProof{name: "notifyclientmoved", clid: "7"}); err != nil {
		t.Fatalf("matching proof must count as success: %v", err)
	}
}

// TestProofWrongClidIsRejected: an event about a DIFFERENT client
// (concurrent unrelated move) must never satisfy the pending command —
// the B-24 false-ack guard.
func TestProofWrongClidIsRejected(t *testing.T) {
	core, tc, cleanup := newExecHarness(t)
	defer cleanup()
	old := tsExecVoidTimeout
	tsExecVoidTimeout = 200 * time.Millisecond
	t.Cleanup(func() { tsExecVoidTimeout = old })

	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.fireProof("notifyclientmoved", "9") // NOT our clid=7
	}()
	if _, err := core.tsExecProof("clientmove clid=7 cid=2",
		&tsProof{name: "notifyclientmoved", clid: "7"}); err == nil {
		t.Fatal("wrong-clid proof accepted — false ack (B-24)")
	}
}

// TestProofWrongNameIsRejected: a matching clid under a different
// event name proves nothing about the pending command.
func TestProofWrongNameIsRejected(t *testing.T) {
	core, tc, cleanup := newExecHarness(t)
	defer cleanup()
	old := tsExecVoidTimeout
	tsExecVoidTimeout = 200 * time.Millisecond
	t.Cleanup(func() { tsExecVoidTimeout = old })

	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.fireProof("notifyclientupdated", "7") // right clid, wrong event
	}()
	if _, err := core.tsExecProof("clientmove clid=7 cid=2",
		&tsProof{name: "notifyclientmoved", clid: "7"}); err == nil {
		t.Fatal("wrong-name proof accepted — false ack (B-24)")
	}
}

// TestStaleProofsDrainedBeforeSend: a proof left over from a PREVIOUS
// (timed-out) command must not satisfy the next one.
func TestStaleProofsDrainedBeforeSend(t *testing.T) {
	core, tc, cleanup := newExecHarness(t)
	defer cleanup()
	old := tsExecVoidTimeout
	tsExecVoidTimeout = 200 * time.Millisecond
	t.Cleanup(func() { tsExecVoidTimeout = old })

	// Stale proof sits in the buffer BEFORE this exec starts.
	tc.fireProof("notifyclientmoved", "7")

	if _, err := core.tsExecProof("clientmove clid=7 cid=2",
		&tsProof{name: "notifyclientmoved", clid: "7"}); err == nil {
		t.Fatal("stale proof from a previous command satisfied the new one — false ack (B-24)")
	}
}
