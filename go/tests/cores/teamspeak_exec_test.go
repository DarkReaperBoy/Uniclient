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
		for {
			select {
			case cmd := <-tc.ForTestCmdCh():
				tc.ForTestExecMu().Lock()
				if tc.ForTestExecWait() {
					select {
					case tc.ForTestExecCh() <- cmd:
					default:
					}
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
