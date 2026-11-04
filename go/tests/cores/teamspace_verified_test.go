package tests

import (
	"errors"
	"os"
	"strings"
	"testing"
	"time"

	. "uniclient/cores"
)

func TestTSExecVerifiedReadbackRescuesSilentSuccess(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 150 * time.Millisecond
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{})
	srv.SetResponder(func(string) []string { return nil })

	rows, err := core.TsExecVerified("bandel banid=5", func() (bool, error) { return true, nil })
	if err != nil {
		t.Fatalf("read-back proved done but exec kept the error: %v", err)
	}
	_ = rows
}

func TestTSExecVerifiedKeepsRealError(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 150 * time.Millisecond
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{})
	srv.SetResponder(func(string) []string { return nil })

	_, err := core.TsExecVerified("bandel banid=5", func() (bool, error) { return false, nil })
	if err == nil || !errors.Is(err, ErrNetwork) {
		t.Fatalf("silent + not-done must keep the error, got %v", err)
	}
}

func TestTSExecVerifiedPermissionDeniedNeedsDoneState(t *testing.T) {
	core, srv := newScriptedTSCore(t, tsScriptedConfig{})
	srv.SetResponder(func(string) []string {
		return []string{"error id=2568 msg=insufficient\\sclient\\spermissions failed_permid=214"}
	})

	_, err := core.TsExecVerified("bandel banid=5", func() (bool, error) { return false, nil })
	if err == nil || !errors.Is(err, ErrPermission) {
		t.Fatalf("permission denied must survive when not done, got %v", err)
	}

	_, err = core.TsExecVerified("bandel banid=5", func() (bool, error) { return true, nil })
	if err != nil {
		t.Fatalf("goal-state-already-true must rescue: %v", err)
	}
}

func TestServerGroupContainsReadBackLogic(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{})
	var q tsScriptedQueue
	srv.SetResponder(func(string) []string { return q.take() })

	q.add("cldbid=5|cldbid=77", "error id=0 msg=ok")
	if ok, err := core.ServerGroupContains(4, 77, true)(); err != nil || !ok {
		t.Fatalf("present/want: ok=%v err=%v", ok, err)
	}
	q.add("cldbid=5|cldbid=77", "error id=0 msg=ok")
	if ok, err := core.ServerGroupContains(4, 77, false)(); err != nil || ok {
		t.Fatalf("present/want-absent: ok=%v err=%v", ok, err)
	}
	q.add("cldbid=5", "error id=0 msg=ok")
	if ok, err := core.ServerGroupContains(4, 77, false)(); err != nil || !ok {
		t.Fatalf("absent/want-absent: ok=%v err=%v", ok, err)
	}
	q.add("error id=1281 msg=database\\sempty\\sresult\\sset")
	if ok, err := core.ServerGroupContains(4, 77, false)(); err != nil || !ok {
		t.Fatalf("empty/want-absent: ok=%v err=%v", ok, err)
	}
	q.add("error id=1281 msg=database\\sempty\\sresult\\sset")
	if ok, err := core.ServerGroupContains(4, 77, true)(); err != nil || ok {
		t.Fatalf("empty/want-present: ok=%v err=%v", ok, err)
	}
	q.add("error id=2568 msg=insufficient\\sclient\\spermissions")
	if _, err := core.ServerGroupContains(4, 77, true)(); err == nil {
		t.Fatal("unavailable read-back must error, not decide")
	}
}

func TestSetAdminAndUnbanUseReadBack(t *testing.T) {
	src, err := os.ReadFile("../../cores/teamspeak.go")
	if err != nil {
		t.Fatal(err)
	}
	body := string(src)
	for _, spec := range []struct{ fn, needle string }{
		{"func (t *TeamSpeakCore) SetAdmin(", "clientinfo clid="},
		{"func (t *TeamSpeakCore) SetAdmin(", "TsExecVerified("},
		{"func (t *TeamSpeakCore) UnbanMember(", "TsExecVerified("},
		{"func (t *TeamSpeakCore) UnbanMember(", `banlist`},
	} {
		start := strings.Index(body, spec.fn)
		if start < 0 {
			t.Fatalf("cannot find %s", spec.fn)
		}
		end := strings.Index(body[start:], "\nfunc ")
		if end < 0 {
			end = len(body) - start
		}
		region := body[start : start+end]
		clean := []string{}
		for _, line := range strings.Split(region, "\n") {
			trim := strings.TrimSpace(line)
			if strings.HasPrefix(trim, "//") {
				continue
			}
			clean = append(clean, trim)
		}
		if !strings.Contains(strings.Join(clean, "\n"), spec.needle) {
			t.Errorf("%s missing %q (F-86 wiring)", spec.fn, spec.needle)
		}
	}
}
