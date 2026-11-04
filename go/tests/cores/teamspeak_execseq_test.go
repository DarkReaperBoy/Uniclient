package tests

import (
	"strings"
	"testing"
	"time"

	. "uniclient/cores"
)

func TestTSExecConcurrentCallsKeepTheirOwnResponses(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{})
	srv.SetResponder(func(line string) []string {
		if strings.Contains(line, "command-one") {
			return []string{"who=first", "error id=0 msg=ok"}
		}
		if strings.Contains(line, "command-two") {
			return []string{"who=second", "error id=0 msg=ok"}
		}
		return nil
	})

	type result struct {
		rows []map[string]string
		err  error
	}
	c1 := make(chan result, 1)
	c2 := make(chan result, 1)
	go func() {
		rows, err := core.TsExec("command-one")
		c1 <- result{rows, err}
	}()
	go func() {
		rows, err := core.TsExec("command-two")
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
