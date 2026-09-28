package cores

import (
	"testing"
	"time"
)

// F-85 (slice 320): tsProof generalized to carry the broadcast's FULL
// params (F-83/F-84's {name, clid} only matched a fixed key), so a
// pending command can (a) match on whatever key IT dictates (invokerid
// for channelcreate, cid for channeledit, clid for kick/move/update)
// and (b) read result fields back from the proof — CreateChannel gets
// its new cid from notifychannelcreated's params (in-client
// channelcreate sends NO data row and NO ok-line: wire-proven,
// WORKLOG 320).
//
// Also fixes ClientEdit, which built the `clientedit ...` command and
// then returned nil WITHOUT SENDING IT (silent no-op).
//
// Seam-RED (WORKLOG 320): undefined: tsWant; existing F-84 tests fail
// with "unknown field clid".

// TestProofFieldsRowProvidesResultCID: the proof's params come back as
// a result row — CreateChannel's rows[0]["cid"] extraction works.
func TestProofFieldsRowProvidesResultCID(t *testing.T) {
	core, tc, cleanup := newExecHarness(t)
	defer cleanup()

	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.fireProof("notifychannelcreated", map[string]string{
			"invokerid": "7", "cid": "42", "channel_name": "new-chan",
		})
	}()
	rows, err := core.tsExecProof("channelcreate channel_name=new-chan",
		&tsWant{name: "notifychannelcreated", key: "invokerid", val: "7"})
	if err != nil {
		t.Fatalf("proof must count as success: %v", err)
	}
	if len(rows) == 0 || rows[0]["cid"] != "42" {
		t.Fatalf("proof fields not returned as result row: %v", rows)
	}
}

// TestProofKeyMismatchRejected: a broadcast whose params lack the
// wanted key (or carry a different value) never satisfies the pending
// command — B-24 false-ack guard at the generalized matcher.
func TestProofKeyMismatchRejected(t *testing.T) {
	core, tc, cleanup := newExecHarness(t)
	defer cleanup()
	old := tsExecVoidTimeout
	tsExecVoidTimeout = 200 * time.Millisecond
	t.Cleanup(func() { tsExecVoidTimeout = old })

	go func() {
		time.Sleep(30 * time.Millisecond)
		// right NAME, but no invokerid field (e.g. someone else's event
		// parsed without it): must NOT match want{invokerid: "7"}.
		tc.fireProof("notifychannelcreated", map[string]string{"cid": "7"})
	}()
	if _, err := core.tsExecProof("channelcreate channel_name=x",
		&tsWant{name: "notifychannelcreated", key: "invokerid", val: "7"}); err == nil {
		t.Fatal("mismatched proof accepted — false ack (B-24)")
	}
}
