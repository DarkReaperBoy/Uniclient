package tests

import (
	"testing"
	"time"
	. "uniclient/cores"
)

func TestProofMatchingClidSucceeds(t *testing.T) {
	core, tc, cleanup := newExecHarness(t)
	defer cleanup()

	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.ForTestFireProof("notifyclientmoved", map[string]string{"clid": "7"})
	}()
	if _, err := core.TsExecProof("clientmove clid=7 cid=2",
		ForTestNewTsWant("clid", "notifyclientmoved", "7")); err != nil {
		t.Fatalf("matching proof must count as success: %v", err)
	}
}

func TestProofWrongClidIsRejected(t *testing.T) {
	core, tc, cleanup := newExecHarness(t)
	defer cleanup()
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 200 * time.Millisecond
	t.Cleanup(func() { TsExecVoidTimeout = old })

	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.ForTestFireProof("notifyclientmoved", map[string]string{"clid": "9"})
	}()
	if _, err := core.TsExecProof("clientmove clid=7 cid=2",
		ForTestNewTsWant("clid", "notifyclientmoved", "7")); err == nil {
		t.Fatal("wrong-clid proof accepted — false ack (B-24)")
	}
}

func TestProofWrongNameIsRejected(t *testing.T) {
	core, tc, cleanup := newExecHarness(t)
	defer cleanup()
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 200 * time.Millisecond
	t.Cleanup(func() { TsExecVoidTimeout = old })

	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.ForTestFireProof("notifyclientupdated", map[string]string{"clid": "7"})
	}()
	if _, err := core.TsExecProof("clientmove clid=7 cid=2",
		ForTestNewTsWant("clid", "notifyclientmoved", "7")); err == nil {
		t.Fatal("wrong-name proof accepted — false ack (B-24)")
	}
}

func TestStaleProofsDrainedBeforeSend(t *testing.T) {
	core, tc, cleanup := newExecHarness(t)
	defer cleanup()
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 200 * time.Millisecond
	t.Cleanup(func() { TsExecVoidTimeout = old })

	tc.ForTestFireProof("notifyclientmoved", map[string]string{"clid": "7"})

	if _, err := core.TsExecProof("clientmove clid=7 cid=2",
		ForTestNewTsWant("clid", "notifyclientmoved", "7")); err == nil {
		t.Fatal("stale proof from a previous command satisfied the new one — false ack (B-24)")
	}
}
