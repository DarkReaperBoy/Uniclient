package cores

import (
	"testing"
	"time"
)

func TestTSExecConcurrentCallsKeepTheirOwnResponses(t *testing.T) {
	old := tsExecVoidTimeout
	tsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { tsExecVoidTimeout = old })

	core, tc, done := newExecHarness(t)
	defer done()

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
