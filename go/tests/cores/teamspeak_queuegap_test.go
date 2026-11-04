package tests

import (
	"bytes"
	"log"
	"os"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	. "uniclient/cores"
)

type tsGapLog struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (g *tsGapLog) Write(p []byte) (int, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	return g.buf.Write(p)
}

func (g *tsGapLog) lines() []string {
	g.mu.Lock()
	defer g.mu.Unlock()
	var out []string
	for _, line := range strings.Split(g.buf.String(), "\n") {
		if strings.Contains(line, "waiting for command packet") {
			out = append(out, strings.TrimSpace(line))
		}
	}
	return out
}

func tsQueuedIDSet(line string) map[uint16]bool {
	open := strings.Index(line, "[")
	closing := strings.Index(line, "]")
	ids := map[uint16]bool{}
	if open < 0 || closing < open {
		return ids
	}
	for _, field := range strings.Split(line[open+1:closing], " ") {
		if v, err := strconv.ParseUint(field, 10, 16); err == nil {
			ids[uint16(v)] = true
		}
	}
	return ids
}

func tsGapLineNames(line string, pID uint16) bool {
	return strings.Contains(line, "waiting for command packet "+strconv.Itoa(int(pID))+";")
}

func TestTSCommandQueueLogsGapWithQueuedIDsOnWire(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{ServerName: "Gap Base"})

	var gapLog tsGapLog
	log.SetOutput(&gapLog)
	defer log.SetOutput(os.Stderr)

	ackedBase := srv.AckedCount()
	base := srv.NextPID()

	srv.PushAtPID(base+4, "initserver virtualserver_name="+TsEscape("Held A4"))
	waitForCond(t, func() bool { return srv.AckedCount() >= ackedBase+1 },
		"server never saw the ack for the pID base+4 arrival")
	time.Sleep(150 * time.Millisecond)
	srv.PushAtPID(base+2, "initserver virtualserver_name="+TsEscape("Held A2"))
	waitForCond(t, func() bool { return srv.AckedCount() >= ackedBase+2 },
		"server never saw the ack for the pID base+2 arrival")
	time.Sleep(150 * time.Millisecond)

	lines := gapLog.lines()
	if len(lines) != 1 {
		t.Fatalf("want exactly 1 gap line, got %d: %q", len(lines), lines)
	}
	if !tsGapLineNames(lines[0], base) {
		t.Errorf("gap line must name the expected packet id %d, got %q", base, lines[0])
	}
	ids := tsQueuedIDSet(lines[0])
	if len(ids) == 0 {
		t.Fatalf("gap line lists no queued out-of-order ids: %q", lines[0])
	}
	for id := range ids {
		if id != base+2 && id != base+4 {
			t.Errorf("gap line lists unexpected queued id %d: %q", id, lines[0])
		}
	}
	if got := core.ServerName(); got != "Gap Base" {
		t.Errorf("ServerName = %q — commands beyond the gap must be held, not delivered", got)
	}

	srv.PushAtPID(base, "initserver virtualserver_name="+TsEscape("Filled A0"))
	waitForCond(t, func() bool { return len(gapLog.lines()) == 2 },
		"the new gap after the fill packet never logged")

	lines = gapLog.lines()
	if !tsGapLineNames(lines[1], base+1) {
		t.Errorf("second gap line must name the next expected packet id %d, got %q", base+1, lines[1])
	}
	ids = tsQueuedIDSet(lines[1])
	if len(ids) != 2 || !ids[base+2] || !ids[base+4] {
		t.Errorf("second gap line must list both held ids %d and %d, got %q", base+2, base+4, lines[1])
	}
	if got := core.ServerName(); got != "Filled A0" {
		t.Errorf("ServerName = %q, want %q — the fill must deliver while the held packets stay queued", got, "Filled A0")
	}
}

func TestTSCommandQueueLogsGapOncePerGapOnWire(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{ServerName: "Once Base"})

	var gapLog tsGapLog
	log.SetOutput(&gapLog)
	defer log.SetOutput(os.Stderr)

	ackedBase := srv.AckedCount()
	base := srv.NextPID()

	for i := 2; i <= 16; i += 2 {
		srv.PushAtPID(base+uint16(i), "initserver virtualserver_name=B"+strconv.Itoa(i))
		if i%4 == 0 {
			time.Sleep(2 * time.Millisecond)
		}
	}
	wantAcks := ackedBase + 8
	waitForCond(t, func() bool { return srv.AckedCount() >= wantAcks },
		"server never saw acks for all 8 out-of-order arrivals")
	waitForCond(t, func() bool { return len(gapLog.lines()) == 1 },
		"the gap never logged")
	time.Sleep(250 * time.Millisecond)
	if lines := gapLog.lines(); len(lines) != 1 {
		t.Fatalf("one gap must log ONCE across 8 out-of-order arrivals, got %d lines (B-43): %q", len(lines), lines)
	}
	if got := core.ServerName(); got != "Once Base" {
		t.Errorf("ServerName = %q — every queued rename must be held while the gap persists", got)
	}

	srv.PushAtPID(base+1, "initserver virtualserver_name=B1")
	waitForCond(t, func() bool { return srv.AckedCount() >= wantAcks+1 },
		"server never saw the ack for the base+1 fill")
	time.Sleep(150 * time.Millisecond)
	srv.PushAtPID(base, "initserver virtualserver_name=B0")
	waitForCond(t, func() bool { return len(gapLog.lines()) == 2 && core.ServerName() == "B2" },
		"the drain after the fill never delivered through the queued pID / never re-logged the new gap")

	lines := gapLog.lines()
	if !tsGapLineNames(lines[1], base+3) {
		t.Errorf("second gap line must name the new expected packet id %d, got %q", base+3, lines[1])
	}
	if got := core.ServerName(); got != "B2" {
		t.Fatalf("ServerName = %q, want B2 — pID base+2 hit the wire FIRST yet must deliver last (ordered drain)", got)
	}

	srv.PushAtPID(base+18, "initserver virtualserver_name=B18")
	wantAcks++
	waitForCond(t, func() bool { return srv.AckedCount() >= wantAcks },
		"server never saw the ack for the same-gap extra packet")
	time.Sleep(250 * time.Millisecond)
	if lines := gapLog.lines(); len(lines) != 2 {
		t.Fatalf("an arrival into the SAME gap must not re-log — want 2 lines, got %d: %q", len(lines), lines)
	}
	if got := core.ServerName(); got != "B2" {
		t.Errorf("ServerName = %q after the same-gap extra packet, want still B2", got)
	}
}

func TestTSCommandQueueS2CFragmentReassembly(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })

	t.Run("plain fragments reassemble in order", func(t *testing.T) {
		core, srv := newScriptedTSCore(t, tsScriptedConfig{ServerName: "Frag Base"})
		base := srv.NextPID()
		name := strings.Repeat("F", 700)
		srv.PushFragmentedAtPID(base, "initserver virtualserver_name="+name, 300, false)
		waitForCond(t, func() bool { return core.ServerName() == name },
			"the 3-fragment S2C initserver never reassembled into ServerName")
		if next := srv.NextPID(); next != base+3 {
			t.Errorf("fragments consumed pIDs up to %d, want %d", next, base+3)
		}
	})

	t.Run("compressed fragments reassemble and decompress", func(t *testing.T) {
		core, srv := newScriptedTSCore(t, tsScriptedConfig{ServerName: "CFrag Base"})
		base := srv.NextPID()
		name := strings.Repeat("C", 600)
		frags := srv.FragmentsAtPID(base, "initserver virtualserver_name="+name, 16, true)
		if len(frags) < 3 {
			t.Fatalf("want at least 3 compressed fragments, got %d", len(frags))
		}
		if f := frags[0].flags; f&TsFlagCompressed == 0 || f&TsFlagFragmented == 0 {
			t.Fatalf("first fragment flags %#02x must carry compressed+fragmented", f)
		}
		for _, fr := range frags[1 : len(frags)-1] {
			if fr.flags&TsFlagCompressed != 0 || fr.flags&TsFlagFragmented != 0 {
				t.Fatalf("middle fragment flags %#02x must carry neither flag", fr.flags)
			}
		}
		if f := frags[len(frags)-1].flags; f&TsFlagFragmented == 0 || f&TsFlagCompressed != 0 {
			t.Fatalf("last fragment flags %#02x must carry fragmented only", f)
		}
		for _, fr := range frags {
			srv.SendS2CFragment(fr)
		}
		waitForCond(t, func() bool { return core.ServerName() == name },
			"the compressed fragmented S2C initserver never landed")
	})

	t.Run("single compressed packet decompresses", func(t *testing.T) {
		core, srv := newScriptedTSCore(t, tsScriptedConfig{ServerName: "Single Base"})
		base := srv.NextPID()
		name := strings.Repeat("S", 600)
		frags := srv.FragmentsAtPID(base, "initserver virtualserver_name="+name, 4096, true)
		if len(frags) != 1 {
			t.Fatalf("want a single compressed packet, got %d", len(frags))
		}
		if f := frags[0].flags; f&TsFlagCompressed == 0 || f&TsFlagFragmented != 0 {
			t.Fatalf("flags %#02x must carry compressed without fragmented", f)
		}
		srv.SendS2CFragment(frags[0])
		waitForCond(t, func() bool { return core.ServerName() == name },
			"the single compressed S2C initserver never decompressed")
	})

	t.Run("delayed first fragment reassembles through the gap", func(t *testing.T) {
		core, srv := newScriptedTSCore(t, tsScriptedConfig{ServerName: "Delayed Base"})

		var gapLog tsGapLog
		log.SetOutput(&gapLog)
		defer log.SetOutput(os.Stderr)

		base := srv.NextPID()
		name := strings.Repeat("D", 700)
		frags := srv.FragmentsAtPID(base, "initserver virtualserver_name="+name, 300, false)
		if len(frags) != 3 {
			t.Fatalf("want 3 fragments, got %d", len(frags))
		}
		srv.SendS2CFragment(frags[1])
		srv.SendS2CFragment(frags[2])
		waitForCond(t, func() bool { return len(gapLog.lines()) == 1 },
			"the missing first fragment never produced a gap log")
		if got := core.ServerName(); got != "Delayed Base" {
			t.Errorf("ServerName = %q — the fragment tail must be held until the first fragment arrives", got)
		}
		srv.SendS2CFragment(frags[0])
		waitForCond(t, func() bool { return core.ServerName() == name },
			"the reassembled name never landed after the delayed first fragment")
	})
}
