package cores

import (
	"errors"
	"os"
	"strings"
	"testing"
	"time"
)

// F-86 (slice 321, closes B-58): the in-client protocol omits success
// replies (wire-proven for bandel + servergroupaddclient, WORKLOG
// 321), and SetAdmin shipped BROKEN: the GUI's User.ID is the SESSION
// id (clid — GetMembers) but servergroupaddclient wants the DATABASE
// id, so every call answered "invalid clientID" (wire-proven: clid=86
// vs dbid=78). Fix: resolve clid→dbid via clientinfo (data row →
// grace-safe), then confirm the EFFECT via a read-back the protocol
// DOES answer — tsExecVerified: verify==true rescues a silent/lost
// reply; anything else returns the ORIGINAL error unchanged (B-24: a
// real permission-denied stays denied unless the read-back proves the
// goal state already holds).
//
// Seam-RED (WORKLOG 321): undefined: tsExecVerified.

// TestTSExecVerifiedReadbackRescuesSilentSuccess: silent reply + read-
// back says done → success (the modern-server case).
func TestTSExecVerifiedReadbackRescuesSilentSuccess(t *testing.T) {
	core, _, cleanup := newExecHarness(t)
	defer cleanup()
	old := tsExecVoidTimeout
	tsExecVoidTimeout = 150 * time.Millisecond
	t.Cleanup(func() { tsExecVoidTimeout = old })

	rows, err := core.tsExecVerified("bandel banid=5", func() (bool, error) { return true, nil })
	if err != nil {
		t.Fatalf("read-back proved done but exec kept the error: %v", err)
	}
	_ = rows
}

// TestTSExecVerifiedKeepsRealError: silence + read-back says NOT done →
// the original response-lost error survives (no false-ack).
func TestTSExecVerifiedKeepsRealError(t *testing.T) {
	core, _, cleanup := newExecHarness(t)
	defer cleanup()
	old := tsExecVoidTimeout
	tsExecVoidTimeout = 150 * time.Millisecond
	t.Cleanup(func() { tsExecVoidTimeout = old })

	_, err := core.tsExecVerified("bandel banid=5", func() (bool, error) { return false, nil })
	if err == nil || !errors.Is(err, ErrNetwork) {
		t.Fatalf("silent + not-done must keep the error, got %v", err)
	}
}

// TestTSExecVerifiedPermissionDeniedNeedsDoneState: a real semantic
// error (2568) survives unless the read-back proves the goal already
// holds (someone else did it meanwhile → the semantic goal IS met).
func TestTSExecVerifiedPermissionDeniedNeedsDoneState(t *testing.T) {
	core, tc, cleanup := newExecHarness(t)
	defer cleanup()

	// Script the semantic error reply for the command.
	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.cmdCh <- tsResp(t, "error id=2568 msg=insufficient\\sclient\\spermissions failed_permid=214")
	}()

	_, err := core.tsExecVerified("bandel banid=5", func() (bool, error) { return false, nil })
	if err == nil || !errors.Is(err, ErrPermission) {
		t.Fatalf("permission denied must survive when not done, got %v", err)
	}

	// Same error, but the read-back shows the goal state IS in effect →
	// success (the state the caller wanted exists).
	_, err = core.tsExecVerified("bandel banid=5", func() (bool, error) { return true, nil })
	if err != nil {
		t.Fatalf("goal-state-already-true must rescue: %v", err)
	}
}

// TestServerGroupContainsReadBackLogic: the membership read-back
// (servergroupclientlist — data rows, grace-safe) classifies present/
// absent/empty-list/unavailable correctly.
func TestServerGroupContainsReadBackLogic(t *testing.T) {
	core, tc, cleanup := newExecHarness(t)
	defer cleanup()
	old := tsExecVoidTimeout
	tsExecVoidTimeout = 150 * time.Millisecond
	t.Cleanup(func() { tsExecVoidTimeout = old })

	inject := func(rows ...string) {
		go func() {
			time.Sleep(20 * time.Millisecond)
			for _, r := range rows {
				tc.cmdCh <- tsResp(t, r)
			}
		}()
	}

	// present + want present → true
	inject("cldbid=5|cldbid=77", "error id=0 msg=ok")
	if ok, err := core.serverGroupContains(4, 77, true)(); err != nil || !ok {
		t.Fatalf("present/want: ok=%v err=%v", ok, err)
	}
	// present + want absent → false
	inject("cldbid=5|cldbid=77", "error id=0 msg=ok")
	if ok, err := core.serverGroupContains(4, 77, false)(); err != nil || ok {
		t.Fatalf("present/want-absent: ok=%v err=%v", ok, err)
	}
	// absent + want absent → true (del succeeded / already gone)
	inject("cldbid=5", "error id=0 msg=ok")
	if ok, err := core.serverGroupContains(4, 77, false)(); err != nil || !ok {
		t.Fatalf("absent/want-absent: ok=%v err=%v", ok, err)
	}
	// empty list (1281 → ErrNotFound) + want absent → true; + want present → false
	inject("error id=1281 msg=database\\sempty\\sresult\\sset")
	if ok, err := core.serverGroupContains(4, 77, false)(); err != nil || !ok {
		t.Fatalf("empty/want-absent: ok=%v err=%v", ok, err)
	}
	inject("error id=1281 msg=database\\sempty\\sresult\\sset")
	if ok, err := core.serverGroupContains(4, 77, true)(); err != nil || ok {
		t.Fatalf("empty/want-present: ok=%v err=%v", ok, err)
	}
	// unavailable (permission error) → error, never a decision
	inject("error id=2568 msg=insufficient\\sclient\\spermissions")
	if _, err := core.serverGroupContains(4, 77, true)(); err == nil {
		t.Fatal("unavailable read-back must error, not decide")
	}
}

// TestSetAdminAndUnbanUseReadBack: wiring pin — both GUI-reachable
// no-data commands must resolve ids honestly and confirm through
// tsExecVerified (source scan, comments skipped).
func TestSetAdminAndUnbanUseReadBack(t *testing.T) {
	src, err := os.ReadFile("teamspeak.go")
	if err != nil {
		t.Fatal(err)
	}
	body := string(src)
	for _, spec := range []struct{ fn, needle string }{
		{"func (t *TeamSpeakCore) SetAdmin(", "clientinfo clid="},   // clid→dbid resolution (F-86)
		{"func (t *TeamSpeakCore) SetAdmin(", "tsExecVerified("},    // read-back confirm
		{"func (t *TeamSpeakCore) UnbanMember(", "tsExecVerified("}, // read-back confirm
		{"func (t *TeamSpeakCore) UnbanMember(", `banlist`},         // the read-back itself
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
