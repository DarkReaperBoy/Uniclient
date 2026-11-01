package tests

import (
	"testing"
	"time"
	. "uniclient/cores"
)

func TestProofFieldsRowProvidesResultCID(t *testing.T) {
	core, tc, cleanup := newExecHarness(t)
	defer cleanup()

	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.ForTestFireProof("notifychannelcreated", map[string]string{
			"invokerid": "7", "cid": "42", "channel_name": "new-chan",
		})
	}()
	rows, err := core.TsExecProof("channelcreate channel_name=new-chan",
		ForTestNewTsWant("invokerid", "notifychannelcreated", "7"))
	if err != nil {
		t.Fatalf("proof must count as success: %v", err)
	}
	if len(rows) == 0 || rows[0]["cid"] != "42" {
		t.Fatalf("proof fields not returned as result row: %v", rows)
	}
}

func TestProofKeyMismatchRejected(t *testing.T) {
	core, tc, cleanup := newExecHarness(t)
	defer cleanup()
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 200 * time.Millisecond
	t.Cleanup(func() { TsExecVoidTimeout = old })

	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.ForTestFireProof("notifychannelcreated", map[string]string{"cid": "7"})
	}()
	if _, err := core.TsExecProof("channelcreate channel_name=x",
		ForTestNewTsWant("invokerid", "notifychannelcreated", "7")); err == nil {
		t.Fatal("mismatched proof accepted — false ack (B-24)")
	}
}
