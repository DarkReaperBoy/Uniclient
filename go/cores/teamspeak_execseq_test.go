package cores

import (
	"testing"
	"time"
)

// TestTSExecConcurrentCallsKeepTheirOwnResponses: BUGS B-35 — tsExec
// stored its response channel in the SHARED tc.execCh field, so a
// second concurrent caller (e.g. SetConnectionInfo spawned by a
// notifyconnectioninforequest DURING an in-flight sendtext) replaced
// the channel under the first caller: the first command's response was
// delivered to the SECOND caller and the first starved until the void
// timeout — a false "response lost" while the response was visibly on
// the wire (RoundTrip debug trace, slice 251). RED before the fix:
// the two callers get each other's rows.
func TestTSExecConcurrentCallsKeepTheirOwnResponses(t *testing.T) {
	old := tsExecVoidTimeout
	tsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { tsExecVoidTimeout = old })

	core, tc, done := newExecHarness(t)
	defer done()

	// Scripted responses arrive in command order: cmd1's answer, then
	// cmd2's — the server always answers in the order commands were
	// received.
	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.cmdCh <- tsResp(t, "who=first")
		tc.cmdCh <- tsResp(t, "error id=0 msg=ok")
		time.Sleep(60 * time.Millisecond)
		tc.cmdCh <- tsResp(t, "who=second")
		tc.cmdCh <- tsResp(t, "error id=0 msg=ok")
	}()

	type result struct {
		rows []map[string]string
		err  error
	}
	c1 := make(chan result, 1)
	c2 := make(chan result, 1)
	go func() {
		rows, err := core.tsExec("command-one")
		c1 <- result{rows, err}
	}()
	// Fire the second caller while the first is still waiting — that is
	// exactly the notify→SetConnectionInfo overlap.
	time.Sleep(10 * time.Millisecond)
	go func() {
		rows, err := core.tsExec("command-two")
		c2 <- result{rows, err}
	}()

	r1 := <-c1
	r2 := <-c2
	if r1.err != nil {
		t.Fatalf("command-one: %v", r1.err)
	}
	if r2.err != nil {
		t.Fatalf("command-two: %v", r2.err)
	}
	if len(r1.rows) == 0 || r1.rows[0]["who"] != "first" {
		t.Errorf("command-one got the wrong response: %v (cross-talk, B-35)", r1.rows)
	}
	if len(r2.rows) == 0 || r2.rows[0]["who"] != "second" {
		t.Errorf("command-two got the wrong response: %v (cross-talk, B-35)", r2.rows)
	}
}
