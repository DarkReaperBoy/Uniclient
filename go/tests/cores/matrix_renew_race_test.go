package tests

import (
	"os"
	"strings"
	"testing"
)

func TestRenewalGoroutineDoesNotReadIntervalGlobal(t *testing.T) {
	src, err := os.ReadFile("../../cores/matrix_groupcall.go")
	if err != nil {
		t.Fatal(err)
	}
	body := string(src)
	for _, line := range strings.Split(body, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "//") {
			continue
		}
		if strings.Contains(line, "NewTicker(MatrixRenewInterval)") {
			t.Errorf("racy global read inside the spawned goroutine: %s", trimmed)
		}
	}
	mx, err := os.ReadFile("../../cores/matrix.go")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(mx), "runGroupRenewal(renewCtx, roomID, conf, sess, interval)") {
		t.Error("spawn site must pass the interval captured before `go`")
	}
	if !strings.Contains(string(mx), "interval := MatrixRenewInterval") {
		t.Error("spawn site must read MatrixRenewInterval on the CALLER goroutine")
	}
}
