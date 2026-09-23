package cores

import (
	"encoding/binary"
	"net"
	"strings"
	"testing"
	"time"
)

// Tests-first for the BUGS.md B-1 SEND path: tsSendCommand must (1) compress
// commands > tsMaxPayloadC2S with tsQuickLZCompress, (2) ship a compressed
// payload that still fits as ONE packet with tsFlagCompressed, (3) fragment
// the compressed stream when even that is too big (0x40 on the first
// fragment), and (4) leave small or incompressible commands byte-for-byte
// unchanged. The oracle mirrors the server: capture UDP, EAX-decrypt with
// the fake-key path, reassemble fragments, QuickLZ-decompress, compare.

// tsTestSender builds a tsConnection whose packets land on a local capture
// socket (cryptoOK=false → the same fake-key EAX path the tests below can
// decrypt).
func tsTestSender(t *testing.T) (*tsConnection, *net.UDPConn) {
	t.Helper()
	target, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 0})
	if err != nil {
		t.Fatalf("capture socket: %v", err)
	}
	sender, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 0})
	if err != nil {
		target.Close()
		t.Fatalf("sender socket: %v", err)
	}
	t.Cleanup(func() { sender.Close(); target.Close() })
	tc := &tsConnection{
		conn:        sender,
		addr:        target.LocalAddr().(*net.UDPAddr),
		clientID:    42,
		pendingCmds: make(map[uint16]*tsPendingCmd),
	}
	return tc, target
}

// tsTestReadPackets collects exactly n packets or fails on timeout.
func tsTestReadPackets(t *testing.T, target *net.UDPConn, n int) [][]byte {
	t.Helper()
	buf := make([]byte, 65535)
	pkts := make([][]byte, 0, n)
	target.SetReadDeadline(time.Now().Add(3 * time.Second))
	for len(pkts) < n {
		nr, _, err := target.ReadFromUDP(buf)
		if err != nil {
			t.Fatalf("expected %d packets, got %d: %v", n, len(pkts), err)
		}
		p := make([]byte, nr)
		copy(p, buf[:nr])
		pkts = append(pkts, p)
	}
	return pkts
}

// tsTestDecode reassembles captured C2S packets exactly like the peer does:
// EAX-decrypt each payload, concatenate (arrival order = send order on
// loopback), QuickLZ-decompress when the FIRST packet carried 0x40.
func tsTestDecode(t *testing.T, pkts [][]byte) (payload []byte, firstFlags byte) {
	t.Helper()
	firstFlags = pkts[0][12]
	for i, pkt := range pkts {
		if len(pkt) < 13 {
			t.Fatalf("packet %d too short: %d bytes", i, len(pkt))
		}
		f := pkt[12]
		if i == 0 && f&tsFlagFragmented != 0 && len(pkts) == 1 {
			t.Fatalf("fragmented flag on a lone packet")
		}
		var mac [8]byte
		copy(mac[:], pkt[:8])
		plain, err := tsEAXDecrypt(tsFakeKey[:], tsFakeNonce[:], pkt[8:13], pkt[13:], mac)
		if err != nil {
			t.Fatalf("decrypt packet %d: %v", i, err)
		}
		payload = append(payload, plain...)
	}
	if firstFlags&tsFlagCompressed != 0 {
		out, err := tsQuickLZDecompress(payload)
		if err != nil {
			t.Fatalf("server-side decompression of our payload failed: %v", err)
		}
		return out, firstFlags
	}
	return payload, firstFlags
}

func TestTS3SendCommandCompressesLargeCommand(t *testing.T) {
	t.Run("compressible 580-byte command fits one packet", func(t *testing.T) {
		tc, target := tsTestSender(t)
		cmd := "sendtextmessage targetmode=3 msg=" +
			strings.Repeat("hello teamspeak world this is a test. ", 15) // 573 chars
		if len(cmd) <= tsMaxPayloadC2S {
			t.Fatalf("test command too small: %d", len(cmd))
		}
		if _, err := tc.tsSendCommand(cmd); err != nil {
			t.Fatalf("tsSendCommand: %v", err)
		}
		pkts := tsTestReadPackets(t, target, 1)
		if f := pkts[0][12]; f != byte(tsPktCommand)|tsFlagNewprotocol|tsFlagCompressed {
			t.Fatalf("flags = %#02x, want %#02x (command|newprotocol|compressed)",
				f, byte(tsPktCommand)|tsFlagNewprotocol|tsFlagCompressed)
		}
		payload, _ := tsTestDecode(t, pkts)
		if string(payload) != cmd {
			t.Fatalf("round-trip mismatch: got %d bytes, want %d", len(payload), len(cmd))
		}
	})

	t.Run("compressible 2600-byte command still fits one packet", func(t *testing.T) {
		tc, target := tsTestSender(t)
		cmd := "clientupdate client_description=" +
			strings.Repeat("the quick brown fox jumps over the lazy dog. ", 58) // ~2675
		if len(cmd) <= tsMaxPayloadC2S {
			t.Fatalf("test command too small: %d", len(cmd))
		}
		if _, err := tc.tsSendCommand(cmd); err != nil {
			t.Fatalf("tsSendCommand: %v", err)
		}
		// The whole win: 2600+ bytes used to be 6 raw fragments.
		pkts := tsTestReadPackets(t, target, 1)
		if f := pkts[0][12]; f&tsFlagFragmented != 0 || f&tsFlagCompressed == 0 {
			t.Fatalf("flags = %#02x, want a single compressed (0x40) packet", f)
		}
		payload, _ := tsTestDecode(t, pkts)
		if string(payload) != cmd {
			t.Fatalf("round-trip mismatch: got %d bytes, want %d", len(payload), len(cmd))
		}
	})

	t.Run("incompressible 1500-byte command keeps raw fragmentation", func(t *testing.T) {
		tc, target := tsTestSender(t)
		// Deterministic pseudo-random bytes: QuickLZ ratio give-up → the
		// stored-raw stream is LARGER than the input, so tsSendCommand
		// must fall back to raw fragmentation with NO 0x40 anywhere.
		rnd := uint32(12345)
		var b strings.Builder
		for b.Len() < 1500 {
			rnd = rnd*1664525 + 1013904223
			b.WriteByte(byte(rnd >> 24))
		}
		cmd := b.String()
		if _, err := tc.tsSendCommand(cmd); err != nil {
			t.Fatalf("tsSendCommand: %v", err)
		}
		wantPkts := (len(cmd) + tsMaxPayloadC2S - 1) / tsMaxPayloadC2S
		pkts := tsTestReadPackets(t, target, wantPkts)
		for i, p := range pkts {
			f := p[12]
			if f&tsFlagCompressed != 0 {
				t.Fatalf("packet %d has compressed flag %#02x on an incompressible command", i, f)
			}
			wantFrag := i == 0 || i == wantPkts-1
			if (f&tsFlagFragmented != 0) != wantFrag {
				t.Fatalf("packet %d flags %#02x: fragmented=%v, want %v", i, f, f&tsFlagFragmented != 0, wantFrag)
			}
		}
		payload, _ := tsTestDecode(t, pkts)
		if string(payload) != cmd {
			t.Fatalf("fragment reassembly mismatch: got %d bytes, want %d", len(payload), len(cmd))
		}
	})

	t.Run("small command stays raw single packet", func(t *testing.T) {
		tc, target := tsTestSender(t)
		cmd := "clientupdate client_nickname=shorty"
		if len(cmd) >= tsMaxPayloadC2S {
			t.Fatalf("test command too big: %d", len(cmd))
		}
		if _, err := tc.tsSendCommand(cmd); err != nil {
			t.Fatalf("tsSendCommand: %v", err)
		}
		pkts := tsTestReadPackets(t, target, 1)
		want := byte(tsPktCommand) | tsFlagNewprotocol
		if f := pkts[0][12]; f != want {
			t.Fatalf("flags = %#02x, want %#02x (no compression below the fragment threshold)", f, want)
		}
		payload, _ := tsTestDecode(t, pkts)
		if string(payload) != cmd {
			t.Fatalf("payload mismatch: %q", payload)
		}
	})
}

// TestTS3SendCommandPacketIDsSequential guards the pID bookkeeping across
// the new compress→fragment decision (each packet still consumes one ID).
func TestTS3SendCommandPacketIDsSequential(t *testing.T) {
	tc, target := tsTestSender(t)
	rnd := uint32(999)
	var b strings.Builder
	for b.Len() < 1200 {
		rnd = rnd*1664525 + 1013904223
		b.WriteByte(byte(rnd >> 24))
	}
	first, err := tc.tsSendCommand(b.String())
	if err != nil {
		t.Fatalf("tsSendCommand: %v", err)
	}
	pkts := tsTestReadPackets(t, target, 3) // 1200 > 487 → 3 fragments
	ids := make([]uint16, len(pkts))
	for i, p := range pkts {
		ids[i] = binary.BigEndian.Uint16(p[8:10])
	}
	if ids[0] != first {
		t.Fatalf("returned pID %#x != first fragment pID %#x", first, ids[0])
	}
	if ids[1] != ids[0]+1 || ids[2] != ids[1]+1 {
		t.Fatalf("fragment pIDs not sequential: %#x %#x %#x", ids[0], ids[1], ids[2])
	}
	if ids[0] == ids[1] || ids[1] == ids[2] || ids[0] == ids[2] {
		t.Fatalf("duplicate pIDs: %#x %#x %#x", ids[0], ids[1], ids[2])
	}
}
