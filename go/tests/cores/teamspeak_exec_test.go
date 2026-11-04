package tests

import (
	"context"
	"errors"
	"net"
	"testing"
	"time"
	. "uniclient/cores"
)

func newExecHarness(t *testing.T) (*TeamSpeakCore, *TsConnection, func()) {
	t.Helper()
	ua, err := net.ResolveUDPAddr("udp", "127.0.0.1:9")
	if err != nil {
		t.Fatal(err)
	}
	conn, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 0})
	if err != nil {
		t.Fatal(err)
	}
	tc := ForTestNewTsConnection(ua, make(chan TsIncomingCmd, 16), conn, false, nil, map[uint16]*TsPendingCmd{}, make(chan TsProof, 8), [2]map[uint16]*TsDecryptedPkt{}, [64]byte{})
	core := ForTestNewTeamSpeakCore(false, nil, nil, context.Background(), 0, 0, 0, tc)
	stop := make(chan struct{})
	go func() {
		idle := time.NewTicker(200 * time.Microsecond)
		defer idle.Stop()
		var pending []TsIncomingCmd
		flush := func() {
			for len(pending) > 0 {
				select {
				case tc.ForTestExecCh() <- pending[0]:
					pending = pending[1:]
				default:
					return
				}
			}
		}
		for {
			select {
			case cmd := <-tc.ForTestCmdCh():
				tc.ForTestExecMu().Lock()
				if tc.ForTestExecWait() {
					flush()
					select {
					case tc.ForTestExecCh() <- cmd:
					default:
					}
				} else {
					pending = append(pending, cmd)
				}
				tc.ForTestExecMu().Unlock()
			case <-idle.C:
				tc.ForTestExecMu().Lock()
				if tc.ForTestExecWait() {
					flush()
				}
				tc.ForTestExecMu().Unlock()
			case <-stop:
				return
			}
		}
	}()
	return core, tc, func() { close(stop); conn.Close() }
}

func tsResp(t *testing.T, line string) TsIncomingCmd {
	t.Helper()
	name, params := TsParseCommand([]byte(line))
	return *ForTestNewTsIncomingCmd(name, params, line)
}

func TestTSExecSilentServerIsAnErrorNotFalseAck(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 150 * time.Millisecond
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, _, done := newExecHarness(t)
	defer done()

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

	core, tc, done := newExecHarness(t)
	defer done()

	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.ForTestCmdCh() <- tsResp(t, "channel_id=42 channel_name=Lobby")
		tc.ForTestCmdCh() <- tsResp(t, "error id=0 msg=ok")
	}()

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

	core, tc, done := newExecHarness(t)
	defer done()

	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.ForTestCmdCh() <- tsResp(t, "error id=2568 msg=insufficient\\sclient\\spermissions")
	}()

	_, err := core.TsExec("clientmove clid=1 cid=2")
	if !errors.Is(err, ErrPermission) {
		t.Fatalf("err = %v, want ErrPermission", err)
	}
}

func TestTSExecDeliversResponsesQueuedBeforeTheCall(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, tc, done := newExecHarness(t)
	defer done()

	tc.ForTestCmdCh() <- tsResp(t, "channel_id=7 channel_needed_talk_power=9999")
	landed := make(chan struct{})
	go func() {
		for i := 0; i < 16; i++ {
			tc.ForTestCmdCh() <- tsResp(t, "who=filler")
		}
		close(landed)
		tc.ForTestCmdCh() <- tsResp(t, "error id=0 msg=ok")
	}()
	select {
	case <-landed:
	case <-time.After(200 * time.Millisecond):
	}

	rows, err := core.TsExec("channelinfo cid=7")
	if err != nil {
		t.Fatalf("TsExec: %v — responses queued before the call never reached the exec (the pump drops cmds consumed while execWait is false; CI run 41790936340)", err)
	}
	power := ""
	for _, r := range rows {
		if v, ok := r["channel_needed_talk_power"]; ok {
			power = v
		}
	}
	if power != "9999" {
		t.Errorf("pre-queued channelinfo row lost by the harness pump: channel_needed_talk_power = %q, want 9999 (CI run 41790936340: TestGetGroupCallReportsTalkPowerBlocked)", power)
	}
}
