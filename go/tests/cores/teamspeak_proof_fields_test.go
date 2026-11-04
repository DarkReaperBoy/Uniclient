package tests

import (
	"strings"
	"testing"
	"time"

	. "uniclient/cores"
)

func TestProofFieldsRowProvidesResultCID(t *testing.T) {
	core, srv := newScriptedTSCore(t, tsScriptedConfig{})
	srv.SetResponder(func(line string) []string {
		if strings.HasPrefix(line, "channelcreate") {
			return []string{"notifychannelcreated cid=42 cpid=1 channel_order=0 channel_name=new-chan invokerid=7"}
		}
		return nil
	})
	rows, err := core.TsExecProof("channelcreate channel_name=new-chan",
		NewTsWant("notifychannelcreated", "invokerid", "7"))
	if err != nil {
		t.Fatalf("proof must count as success: %v", err)
	}
	if len(rows) == 0 || rows[0]["cid"] != "42" {
		t.Fatalf("proof fields not returned as result row: %v", rows)
	}
}

func TestProofKeyMismatchRejected(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 200 * time.Millisecond
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{})
	srv.SetResponder(func(line string) []string {
		if strings.HasPrefix(line, "channelcreate") {
			return []string{"notifychannelcreated cid=7 cpid=1 channel_order=0 channel_name=x"}
		}
		return nil
	})
	if _, err := core.TsExecProof("channelcreate channel_name=x",
		NewTsWant("notifychannelcreated", "invokerid", "7")); err == nil {
		t.Fatal("mismatched proof accepted — false ack (B-24)")
	}
}
