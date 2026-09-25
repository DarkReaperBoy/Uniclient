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

// TestTSCommandQueueLogsGapOncePerGap: BUGS B-43 — the B-19 gap
// diagnostic fired on EVERY packet arriving while one gap was open
// (the slice-247 live storms: 229 identical lines per run), so a
// hostile server could flood stderr the same way B-42 flooded stdout.
// One line per gap (re-log only when the EXPECTED id changes), and a
// fresh gap after resolution must still log. RED pre-fix: 50 lines
// for one gap.
func TestTSCommandQueueLogsGapOncePerGap(t *testing.T) {
	tc := &tsConnection{}
	tc.recvQueue[0] = map[uint16]*tsDecryptedPkt{
		7: {pID: 7, flags: 0x02, plaintext: []byte("k7=v")},
		9: {pID: 9, flags: 0x02, plaintext: []byte("k9=v")},
	}
	tc.pktState[tsPktCommand].nextRecvID = 5

	var buf bytes.Buffer
	log.SetOutput(&buf)
	defer log.SetOutput(os.Stderr)

	tc.recvQueueMu.Lock()
	for i := 0; i < 50; i++ {
		tc.tsProcessCommandQueue(0) // 50 packets arrive during the SAME gap
	}
	tc.recvQueueMu.Unlock()

	if n := strings.Count(buf.String(), "waiting for command packet"); n != 1 {
		t.Fatalf("one gap must log ONCE, got %d lines (B-43): %q", n, buf.String())
	}

	// Resolve the gap (5 and 6 arrive): queue drains 5,6,7,9 → empty →
	// gap state resets. Then open a NEW gap (10 missing, 11 queued).
	tc.recvQueueMu.Lock()
	tc.recvQueue[0][5] = &tsDecryptedPkt{pID: 5, flags: 0x02, plaintext: []byte("a=b")}
	tc.recvQueue[0][6] = &tsDecryptedPkt{pID: 6, flags: 0x02, plaintext: []byte("c=d")}
	tc.tsProcessCommandQueue(0)
	tc.recvQueue[0][11] = &tsDecryptedPkt{pID: 11, flags: 0x02, plaintext: []byte("z=y")}
	tc.tsProcessCommandQueue(0)
	tc.recvQueueMu.Unlock()

	if n := strings.Count(buf.String(), "waiting for command packet"); n != 2 {
		t.Fatalf("a NEW gap after resolution must log again — want 2 total lines, got %d: %q", n, buf.String())
	}
}
