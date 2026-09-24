package cores

import (
	"context"
	"errors"
	"net"
	"testing"
	"time"
)

// tsExec harness: a real UDP socket (the concrete *net.UDPConn type
// can't be faked) pointed at a throwaway local address, plus a
// goroutine that plays the dispatcher's role (cmdCh → execCh while
// execWait) so tests control exactly which responses arrive — or that
// none ever do.
func newExecHarness(t *testing.T) (*TeamSpeakCore, *tsConnection, func()) {
	t.Helper()
	ua, err := net.ResolveUDPAddr("udp", "127.0.0.1:9")
	if err != nil {
		t.Fatal(err)
	}
	conn, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 0})
	if err != nil {
		t.Fatal(err)
	}
	tc := &tsConnection{
		conn:        conn,
		addr:        ua,
		cmdCh:       make(chan tsIncomingCmd, 16),
		pendingCmds: map[uint16]*tsPendingCmd{},
	}
	core := &TeamSpeakCore{tsConn: tc, ctx: context.Background()}
	stop := make(chan struct{})
	go func() {
		for {
			select {
			case cmd := <-tc.cmdCh:
				tc.execMu.Lock()
				if tc.execWait {
					select {
					case tc.execCh <- cmd:
					default:
					}
				}
				tc.execMu.Unlock()
			case <-stop:
				return
			}
		}
	}()
	return core, tc, func() { close(stop); conn.Close() }
}

func tsResp(t *testing.T, line string) tsIncomingCmd {
	t.Helper()
	name, params := tsParseCommand([]byte(line))
	return tsIncomingCmd{name: name, params: params, raw: line}
}

// TestTSExecSilentServerIsAnErrorNotFalseAck: BUGS B-24 — the void
// deadline returned `result, nil` when NOTHING ever arrived. Every TS3
// command is answered by an `error id=` line, so silence = the UDP
// response was lost — and a nil there is a FALSE ACK for
// state-changing commands (clientmove "joined" a channel the server
// never moved us into). RED before the fix: this test passes a silent
// server and demands an ErrNetwork-family error.
func TestTSExecSilentServerIsAnErrorNotFalseAck(t *testing.T) {
	old := tsExecVoidTimeout
	tsExecVoidTimeout = 150 * time.Millisecond
	t.Cleanup(func() { tsExecVoidTimeout = old })

	core, _, done := newExecHarness(t)
	defer done()

	rows, err := core.tsExec("clientmove clid=1 cid=2")
	if err == nil {
		t.Fatalf("silent server returned SUCCESS (rows=%v) — false ack (B-24): a lost response must surface as an error", rows)
	}
	if !errors.Is(err, ErrNetwork) {
		t.Errorf("err = %v, want ErrNetwork family", err)
	}
}

// TestTSExecConsumesDataThenOk: the success path (data line + error
// id=0 terminator) must keep returning rows — the fix may only change
// PURE silence.
func TestTSExecConsumesDataThenOk(t *testing.T) {
	old := tsExecVoidTimeout
	tsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { tsExecVoidTimeout = old })

	core, tc, done := newExecHarness(t)
	defer done()

	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.cmdCh <- tsResp(t, "channel_id=42 channel_name=Lobby")
		tc.cmdCh <- tsResp(t, "error id=0 msg=ok")
	}()

	rows, err := core.tsExec("channelinfo cid=42")
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	if len(rows) == 0 || rows[0]["channel_id"] != "42" {
		t.Fatalf("rows = %v", rows)
	}
}

// TestTSExecMapsErrorResponse: a structured error must still map
// (permission denied → ErrPermission), not be swallowed by the timeout
// machinery.
func TestTSExecMapsErrorResponse(t *testing.T) {
	old := tsExecVoidTimeout
	tsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { tsExecVoidTimeout = old })

	core, tc, done := newExecHarness(t)
	defer done()

	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.cmdCh <- tsResp(t, "error id=2568 msg=insufficient\\sclient\\spermissions")
	}()

	_, err := core.tsExec("clientmove clid=1 cid=2")
	if !errors.Is(err, ErrPermission) {
		t.Fatalf("err = %v, want ErrPermission", err)
	}
}
