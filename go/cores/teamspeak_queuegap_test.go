package cores

// tests-first for BUGS.md B-19 — the command-queue gap branch must
// surface out-of-order diagnostics instead of doing dead work.
//
// Pre-pitch the branch built `keys` from recvQueue and dropped the
// slice on an empty line (staticcheck SA4010): a wasted allocation on
// every gap event and the intended queued-packet logging never
// happened.

import (
	"bytes"
	"log"
	"os"
	"strings"
	"testing"
)

func TestTSCommandQueueLogsGapWithQueuedIDs(t *testing.T) {
	tc := &tsConnection{}
	tc.recvQueue[0] = map[uint16]*tsDecryptedPkt{
		7: {},
		9: {},
	}
	tc.pktState[tsPktCommand].nextRecvID = 5 // 5,6 missing; 7,9 queued

	var buf bytes.Buffer
	log.SetOutput(&buf)
	defer log.SetOutput(os.Stderr)

	tc.recvQueueMu.Lock()
	tc.tsProcessCommandQueue(0)
	tc.recvQueueMu.Unlock()

	out := buf.String()
	if !strings.Contains(out, "5") {
		t.Errorf("gap log must name the expected packet id (5), got %q", out)
	}
	if !strings.Contains(out, "7") || !strings.Contains(out, "9") {
		t.Errorf("gap log must list the queued out-of-order ids (7, 9), got %q", out)
	}
}
