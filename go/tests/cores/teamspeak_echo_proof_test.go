package tests

import (
	"strings"
	"testing"
	"time"

	. "uniclient/cores"
)

func TestTSExecProofChannelSucceedsWithoutReply(t *testing.T) {
	core, srv := newScriptedTSCore(t, tsScriptedConfig{ClientID: 5})
	srv.SetResponder(func(line string) []string {
		if strings.HasPrefix(line, "sendtextmessage") {
			return []string{"notifytextmessage targetmode=1 msg=proof invokerid=5 invokername=alice"}
		}
		return nil
	})

	rows, err := core.TsExecProof("sendtextmessage targetmode=2 target=1 msg=proof",
		NewTsWant("notifytextmessage", "invokerid", "5"))
	if err != nil {
		t.Fatalf("proof channel must count as success: %v", err)
	}
	if len(rows) != 1 || rows[0]["invokerid"] != "5" {
		t.Fatalf("proof fields not returned as result row: %v", rows)
	}
}

func TestTSExecProofNilKeepsSilenceAnError(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 150 * time.Millisecond
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{})
	srv.SetResponder(func(string) []string { return nil })

	if _, err := core.TsExec("clientupdate client_nickname=x"); err == nil {
		t.Fatal("silent server with no proof returned success — B-24 regression")
	}
}
