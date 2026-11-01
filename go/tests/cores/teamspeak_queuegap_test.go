package tests

import (
	"bytes"
	"log"
	"os"
	"strings"
	"testing"
	. "uniclient/cores"
)

func TestTSCommandQueueLogsGapWithQueuedIDs(t *testing.T) {
	tc := &TsConnection{}
	rq := tc.ForTestRecvQueue()
	rq[0] = map[uint16]*TsDecryptedPkt{
		7: {},
		9: {},
	}
	ps := tc.ForTestPktState()
	ps[TsPktCommand] = ps[TsPktCommand].ForTestWithNextRecvID(5)

	var buf bytes.Buffer
	log.SetOutput(&buf)
	defer log.SetOutput(os.Stderr)

	tc.ForTestRecvQueueMu().Lock()
	tc.ForTestTsProcessCommandQueue(0)
	tc.ForTestRecvQueueMu().Unlock()

	out := buf.String()
	if !strings.Contains(out, "5") {
		t.Errorf("gap log must name the expected packet id (5), got %q", out)
	}
	if !strings.Contains(out, "7") || !strings.Contains(out, "9") {
		t.Errorf("gap log must list the queued out-of-order ids (7, 9), got %q", out)
	}
}

func TestTSCommandQueueLogsGapOncePerGap(t *testing.T) {
	tc := &TsConnection{}
	rq := tc.ForTestRecvQueue()
	rq[0] = map[uint16]*TsDecryptedPkt{
		7: ForTestNewTsDecryptedPkt(0x02, 7, []byte("k7=v")),
		9: ForTestNewTsDecryptedPkt(0x02, 9, []byte("k9=v")),
	}
	ps := tc.ForTestPktState()
	ps[TsPktCommand] = ps[TsPktCommand].ForTestWithNextRecvID(5)

	var buf bytes.Buffer
	log.SetOutput(&buf)
	defer log.SetOutput(os.Stderr)

	tc.ForTestRecvQueueMu().Lock()
	for i := 0; i < 50; i++ {
		tc.ForTestTsProcessCommandQueue(0)
	}
	tc.ForTestRecvQueueMu().Unlock()

	if n := strings.Count(buf.String(), "waiting for command packet"); n != 1 {
		t.Fatalf("one gap must log ONCE, got %d lines (B-43): %q", n, buf.String())
	}

	tc.ForTestRecvQueueMu().Lock()
	tc.ForTestRecvQueue()[0][5] = ForTestNewTsDecryptedPkt(0x02, 5, []byte("a=b"))
	tc.ForTestRecvQueue()[0][6] = ForTestNewTsDecryptedPkt(0x02, 6, []byte("c=d"))
	tc.ForTestTsProcessCommandQueue(0)
	tc.ForTestRecvQueue()[0][11] = ForTestNewTsDecryptedPkt(0x02, 11, []byte("z=y"))
	tc.ForTestTsProcessCommandQueue(0)
	tc.ForTestRecvQueueMu().Unlock()

	if n := strings.Count(buf.String(), "waiting for command packet"); n != 2 {
		t.Fatalf("a NEW gap after resolution must log again — want 2 total lines, got %d: %q", n, buf.String())
	}
}
