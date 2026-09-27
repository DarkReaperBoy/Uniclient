package cores

import (
	"os"
	"strings"
	"testing"
)

// F-82 (slice 317): DATA RACE caught by -race —
// `runGroupRenewal` read the package-global `matrixRenewInterval`
// INSIDE the spawned goroutine (asynchronously, at goroutine start),
// while tests write that global from the sequential test goroutine
// (renewTestCore). A renewal goroutine spawned by an earlier test's
// JoinGroupCall gets scheduled late → read/write race
// (race detector trace in WORKLOG 317). `rejoin_test` additionally
// never cancelled its renewal, leaving the loop alive into later tests.
//
// Fix: the interval is read ONCE at the spawn site (caller goroutine —
// happens-before ordered w.r.t. test setup/cleanup) and passed as a
// parameter; spawned goroutines never touch the global again.
//
// Pin: no racy read of the global survives inside the renewal code.

func TestRenewalGoroutineDoesNotReadIntervalGlobal(t *testing.T) {
	src, err := os.ReadFile("matrix_groupcall.go")
	if err != nil {
		t.Fatal(err)
	}
	body := string(src)
	for _, line := range strings.Split(body, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "//") {
			continue
		}
		if strings.Contains(line, "NewTicker(matrixRenewInterval)") {
			t.Errorf("racy global read inside the spawned goroutine: %s", trimmed)
		}
	}
	// The spawn site must capture the interval BEFORE `go` (caller
	// goroutine = ordered w.r.t. every test statement).
	mx, err := os.ReadFile("matrix.go")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(mx), "runGroupRenewal(renewCtx, roomID, conf, sess, interval)") {
		t.Error("spawn site must pass the interval captured before `go`")
	}
	// And the interval must actually be captured there.
	if !strings.Contains(string(mx), "interval := matrixRenewInterval") {
		t.Error("spawn site must read matrixRenewInterval on the CALLER goroutine")
	}
}
