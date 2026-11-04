package tests

import (
	"errors"
	"strings"
	"testing"
	"time"

	. "uniclient/cores"
)

func TestTSExecSilentServerIsAnErrorNotFalseAck(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 150 * time.Millisecond
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{})
	srv.SetResponder(func(string) []string { return nil })

	rows, err := core.TsExec("clientmove clid=1 cid=2")
	if err == nil {
		t.Fatalf("silent server returned SUCCESS (rows=%v) — false ack (B-24): a lost response must surface as an error", rows)
	}
	if !errors.Is(err, ErrNetwork) {
		t.Errorf("err = %v, want ErrNetwork family", err)
	}
}

func TestTSExecConsumesDataThenOk(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{})
	srv.SetResponder(func(line string) []string {
		if strings.HasPrefix(line, "channelinfo") {
			return []string{"channel_id=42 channel_name=Lobby", "error id=0 msg=ok"}
		}
		return nil
	})

	rows, err := core.TsExec("channelinfo cid=42")
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if len(rows) == 0 || rows[0]["channel_id"] != "42" {
		t.Fatalf("rows = %v", rows)
	}
}

func TestTSExecMapsErrorResponse(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{})
	srv.SetResponder(func(string) []string {
		return []string{"error id=2568 msg=insufficient\\sclient\\spermissions"}
	})

	_, err := core.TsExec("clientmove clid=1 cid=2")
	if !errors.Is(err, ErrPermission) {
		t.Fatalf("err = %v, want ErrPermission", err)
	}
}

func TestTSExecWaitsForDelayedTerminator(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{})
	srv.SetResponder(func(line string) []string {
		if strings.HasPrefix(line, "channelinfo") {
			time.AfterFunc(60*time.Millisecond, func() { srv.Push("error id=0 msg=ok") })
			return []string{"channel_id=7 channel_needed_talk_power=9999"}
		}
		return nil
	})

	rows, err := core.TsExec("channelinfo cid=7")
	if err != nil {
		t.Fatalf("TsExec: %v — the data line landed but the delayed terminator never completed the exchange", err)
	}
	power := ""
	for _, r := range rows {
		if v, ok := r["channel_needed_talk_power"]; ok {
			power = v
		}
	}
	if power != "9999" {
		t.Errorf("data row lost while waiting for the delayed terminator: channel_needed_talk_power = %q, want 9999", power)
	}
}

func TestTSExecDataTimeoutReturnsRows(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{})
	srv.SetResponder(func(line string) []string {
		if strings.HasPrefix(line, "channelinfo") {
			return []string{"channel_id=7 channel_needed_talk_power=5"}
		}
		return nil
	})

	rows, err := core.TsExec("channelinfo cid=7")
	if err != nil {
		t.Fatalf("TsExec: %v — a data-only response must resolve via the quiet timeout, not error", err)
	}
	if len(rows) == 0 || rows[0]["channel_needed_talk_power"] != "5" {
		t.Errorf("data-only rows = %v, want channel_needed_talk_power=5", rows)
	}
}

func TestTSExecProofWaitsForTerminator(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{})
	srv.SetResponder(func(line string) []string {
		if strings.HasPrefix(line, "command-a") {
			time.AfterFunc(80*time.Millisecond, func() { srv.Push("error id=0 msg=ok") })
			return []string{"notifyclientmoved clid=7 ctid=2"}
		}
		if strings.HasPrefix(line, "command-b") {
			time.AfterFunc(250*time.Millisecond, func() {
				srv.Push("who=mine")
				srv.Push("error id=0 msg=ok")
			})
			return nil
		}
		return nil
	})

	if _, err := core.TsExecProof("command-a", NewTsWant("notifyclientmoved", "clid", "7")); err != nil {
		t.Fatalf("command-a: %v", err)
	}
	rows, err := core.TsExec("command-b")
	if err != nil {
		t.Fatalf("command-b: %v", err)
	}
	if len(rows) == 0 || rows[0]["who"] != "mine" {
		t.Fatalf("command-b rows = %v — the previous command's straggler terminator satisfied this exec (cross-talk, B-35 family: the proof path must consume its own terminator)", rows)
	}
}
