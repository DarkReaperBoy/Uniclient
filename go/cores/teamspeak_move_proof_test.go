package cores

import (
	"testing"
	"time"
)

func TestProofMatchingClidSucceeds(t *testing.T) {
	core, tc, cleanup := newExecHarness(t)
	defer cleanup()

	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.fireProof("notifyclientmoved", map[string]string{"clid": "7"})
	}()
	if _, err := core.tsExecProof("clientmove clid=7 cid=2",
		&tsWant{name: "notifyclientmoved", key: "clid", val: "7"}); err != nil {
		t.Fatalf("matching proof must count as success: %v", err)
	}
}

func TestProofWrongClidIsRejected(t *testing.T) {
	core, tc, cleanup := newExecHarness(t)
	defer cleanup()
	old := tsExecVoidTimeout
	tsExecVoidTimeout = 200 * time.Millisecond
	t.Cleanup(func() { tsExecVoidTimeout = old })

	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.fireProof("notifyclientmoved", map[string]string{"clid": "9"})
	}()
	if _, err := core.tsExecProof("clientmove clid=7 cid=2",
		&tsWant{name: "notifyclientmoved", key: "clid", val: "7"}); err == nil {
		t.Fatal("wrong-clid proof accepted — false ack (B-24)")
	}
}

func TestProofWrongNameIsRejected(t *testing.T) {
	core, tc, cleanup := newExecHarness(t)
	defer cleanup()
	old := tsExecVoidTimeout
	tsExecVoidTimeout = 200 * time.Millisecond
	t.Cleanup(func() { tsExecVoidTimeout = old })

	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.fireProof("notifyclientupdated", map[string]string{"clid": "7"})
	}()
	if _, err := core.tsExecProof("clientmove clid=7 cid=2",
		&tsWant{name: "notifyclientmoved", key: "clid", val: "7"}); err == nil {
		t.Fatal("wrong-name proof accepted — false ack (B-24)")
	}
}

func TestStaleProofsDrainedBeforeSend(t *testing.T) {
	core, tc, cleanup := newExecHarness(t)
	defer cleanup()
	old := tsExecVoidTimeout
	tsExecVoidTimeout = 200 * time.Millisecond
	t.Cleanup(func() { tsExecVoidTimeout = old })

	tc.fireProof("notifyclientmoved", map[string]string{"clid": "7"})

	if _, err := core.tsExecProof("clientmove clid=7 cid=2",
		&tsWant{name: "notifyclientmoved", key: "clid", val: "7"}); err == nil {
		t.Fatal("stale proof from a previous command satisfied the new one — false ack (B-24)")
	}
}
