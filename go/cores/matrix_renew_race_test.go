package cores

import (
	"os"
	"strings"
	"testing"
)

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
	mx, err := os.ReadFile("matrix.go")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(mx), "runGroupRenewal(renewCtx, roomID, conf, sess, interval)") {
		t.Error("spawn site must pass the interval captured before `go`")
	}
	if !strings.Contains(string(mx), "interval := matrixRenewInterval") {
		t.Error("spawn site must read matrixRenewInterval on the CALLER goroutine")
	}
}
