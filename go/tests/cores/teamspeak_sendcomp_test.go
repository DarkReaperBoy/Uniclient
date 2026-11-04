package tests

import (
	"strings"
	"testing"
	"time"

	. "uniclient/cores"
)

func newSendCompCore(t *testing.T) (*TeamSpeakCore, *tsScriptedServer) {
	t.Helper()
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })
	core, srv := newScriptedTSCore(t, tsScriptedConfig{ClientID: 1})
	srv.SetResponder(func(line string) []string {
		if strings.HasPrefix(line, "sendtextmessage") {
			return []string{"notifytextmessage targetmode=3 msg=ok invokerid=1", "error id=0 msg=ok"}
		}
		return nil
	})
	return core, srv
}

func sendAndExpect(t *testing.T, core *TeamSpeakCore, srv *tsScriptedServer, text string) string {
	t.Helper()
	srv.ResetCmdPackets()
	if _, err := core.SendMessage("server", OutgoingMessage{Text: text}); err != nil {
		t.Fatalf("SendMessage: %v", err)
	}
	want := "sendtextmessage targetmode=3 msg=" + TsEscape(text)
	got := srv.WaitCommand(t, "sendtextmessage")
	if got != want {
		t.Fatalf("server decoded %q, want the exact command %q — reassembly/decompression on the wire must be byte-perfect", got, want)
	}
	return want
}

func tsIncompressibleText(n int) string {
	rnd := uint32(12345)
	var b strings.Builder
	for b.Len() < n {
		rnd = rnd*1664525 + 1013904223
		b.WriteByte(byte('a' + rnd%26))
	}
	return b.String()
}

func TestTS3SendCommandCompressesLargeCommand(t *testing.T) {
	t.Run("compressible 580-byte command fits one packet", func(t *testing.T) {
		core, srv := newSendCompCore(t)
		text := strings.Repeat("hello teamspeak world this is a test. ", 15)
		sendAndExpect(t, core, srv, text)
		pkts := srv.CmdPackets()
		if len(pkts) != 1 {
			t.Fatalf("command traveled as %d packets, want a single compressed packet", len(pkts))
		}
		if f := pkts[0].flags; f&TsFlagFragmented != 0 || f&TsFlagCompressed == 0 {
			t.Fatalf("flags = %#02x, want command|newprotocol|compressed with no fragmented bit", f)
		}
	})

	t.Run("compressible 2600-byte command still fits one packet", func(t *testing.T) {
		core, srv := newSendCompCore(t)
		text := strings.Repeat("the quick brown fox jumps over the lazy dog. ", 58)
		sendAndExpect(t, core, srv, text)
		pkts := srv.CmdPackets()
		if len(pkts) != 1 {
			t.Fatalf("command traveled as %d packets, want a single compressed packet", len(pkts))
		}
		if f := pkts[0].flags; f&TsFlagFragmented != 0 || f&TsFlagCompressed == 0 {
			t.Fatalf("flags = %#02x, want a single compressed (0x40) packet", f)
		}
	})

	t.Run("incompressible 1500-byte command keeps raw fragmentation", func(t *testing.T) {
		core, srv := newSendCompCore(t)
		text := tsIncompressibleText(1500)
		sendAndExpect(t, core, srv, text)
		pkts := srv.CmdPackets()
		wantPkts := (len("sendtextmessage targetmode=3 msg="+text) + TsMaxPayloadC2S - 1) / TsMaxPayloadC2S
		if len(pkts) != wantPkts {
			t.Fatalf("command traveled as %d packets, want %d raw fragments", len(pkts), wantPkts)
		}
		for i, p := range pkts {
			if p.flags&TsFlagCompressed != 0 {
				t.Fatalf("packet %d has compressed flag %#02x on an incompressible command", i, p.flags)
			}
			wantFrag := i == 0 || i == wantPkts-1
			if (p.flags&TsFlagFragmented != 0) != wantFrag {
				t.Fatalf("packet %d flags %#02x: fragmented=%v, want %v", i, p.flags, p.flags&TsFlagFragmented != 0, wantFrag)
			}
		}
	})

	t.Run("small command stays raw single packet", func(t *testing.T) {
		core, srv := newSendCompCore(t)
		sendAndExpect(t, core, srv, "shorty")
		pkts := srv.CmdPackets()
		if len(pkts) != 1 {
			t.Fatalf("command traveled as %d packets, want exactly one", len(pkts))
		}
		want := byte(TsPktCommand) | TsFlagNewprotocol
		if f := pkts[0].flags; f != want {
			t.Fatalf("flags = %#02x, want %#02x (no compression below the fragment threshold)", f, want)
		}
	})
}

func TestTS3SendCommandPacketIDsSequential(t *testing.T) {
	core, srv := newSendCompCore(t)
	sendAndExpect(t, core, srv, tsIncompressibleText(1200))
	pkts := srv.CmdPackets()
	if len(pkts) != 3 {
		t.Fatalf("command traveled as %d packets, want 3 fragments", len(pkts))
	}
	for i := 1; i < len(pkts); i++ {
		if pkts[i].pID != pkts[i-1].pID+1 {
			t.Fatalf("fragment pIDs not sequential: %v", pkts)
		}
	}
	if pkts[0].pID == pkts[1].pID || pkts[1].pID == pkts[2].pID || pkts[0].pID == pkts[2].pID {
		t.Fatalf("duplicate pIDs: %v", pkts)
	}
}
