package tests

import (
	"strings"
	"testing"
	"time"

	. "uniclient/cores"
)

func TestProofMatchingClidSucceeds(t *testing.T) {
	core, srv := newScriptedTSCore(t, tsScriptedConfig{})
	srv.SetResponder(func(line string) []string {
		if strings.HasPrefix(line, "clientmove") {
			return []string{"notifyclientmoved clid=7 ctid=2"}
		}
		return nil
	})
	if _, err := core.TsExecProof("clientmove clid=7 cid=2",
		NewTsWant("notifyclientmoved", "clid", "7")); err != nil {
		t.Fatalf("matching proof must count as success: %v", err)
	}
}

func TestProofWrongClidIsRejected(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 200 * time.Millisecond
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{})
	srv.SetResponder(func(line string) []string {
		if strings.HasPrefix(line, "clientmove") {
			return []string{"notifyclientmoved clid=9 ctid=2"}
		}
		return nil
	})
	if _, err := core.TsExecProof("clientmove clid=7 cid=2",
		NewTsWant("notifyclientmoved", "clid", "7")); err == nil {
		t.Fatal("wrong-clid proof accepted — false ack (B-24)")
	}
}

func TestProofWrongNameIsRejected(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 200 * time.Millisecond
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{})
	srv.SetResponder(func(line string) []string {
		if strings.HasPrefix(line, "clientmove") {
			return []string{"notifyclientupdated clid=7 client_talk_power=1"}
		}
		return nil
	})
	if _, err := core.TsExecProof("clientmove clid=7 cid=2",
		NewTsWant("notifyclientmoved", "clid", "7")); err == nil {
		t.Fatal("wrong-name proof accepted — false ack (B-24)")
	}
}

func TestStaleProofsDrainedBeforeSend(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 200 * time.Millisecond
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{ClientID: 7})
	srv.SetResponder(func(string) []string { return nil })

	srv.Push("notifyclientmoved clid=7 ctid=9")
	deadline := time.Now().Add(2 * time.Second)
	selfMoved := false
	for !selfMoved {
		cs, err := core.GetGroupCall("ch:9")
		if err != nil {
			t.Fatalf("GetGroupCall: %v", err)
		}
		for _, p := range cs.Participants {
			if p.UserID == "7" {
				selfMoved = true
			}
		}
		if time.Now().After(deadline) {
			t.Fatal("stale notifyclientmoved never reached the client — cannot prove the drain")
		}
		time.Sleep(20 * time.Millisecond)
	}

	if _, err := core.TsExecProof("clientmove clid=7 cid=2",
		NewTsWant("notifyclientmoved", "clid", "7")); err == nil {
		t.Fatal("stale matching proof accepted after the send — false ack (B-24): takeProofs must drain pre-send proofs")
	}
}
