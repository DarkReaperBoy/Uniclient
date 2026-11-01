package tests

import (
	"encoding/binary"
	"net"
	"strings"
	"testing"
	"time"
	. "uniclient/cores"
)

func tsTestSender(t *testing.T) (*TsConnection, *net.UDPConn) {
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
	tc := ForTestNewTsConnection(target.LocalAddr().(*net.UDPAddr), nil, sender, false, nil, make(map[uint16]*TsPendingCmd), nil, [2]map[uint16]*TsDecryptedPkt{}, [64]byte{})
	tc.ForTestClientID().Store(42)
	return tc, target
}

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

func tsTestDecode(t *testing.T, pkts [][]byte) (payload []byte, firstFlags byte) {
	t.Helper()
	firstFlags = pkts[0][12]
	for i, pkt := range pkts {
		if len(pkt) < 13 {
			t.Fatalf("packet %d too short: %d bytes", i, len(pkt))
		}
		f := pkt[12]
		if i == 0 && f&TsFlagFragmented != 0 && len(pkts) == 1 {
			t.Fatalf("fragmented flag on a lone packet")
		}
		var mac [8]byte
		copy(mac[:], pkt[:8])
		plain, err := TsEAXDecrypt(TsFakeKey[:], TsFakeNonce[:], pkt[8:13], pkt[13:], mac)
		if err != nil {
			t.Fatalf("decrypt packet %d: %v", i, err)
		}
		payload = append(payload, plain...)
	}
	if firstFlags&TsFlagCompressed != 0 {
		out, err := TsQuickLZDecompress(payload)
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
			strings.Repeat("hello teamspeak world this is a test. ", 15)
		if len(cmd) <= TsMaxPayloadC2S {
			t.Fatalf("test command too small: %d", len(cmd))
		}
		if _, err := tc.ForTestTsSendCommand(cmd); err != nil {
			t.Fatalf("tsSendCommand: %v", err)
		}
		pkts := tsTestReadPackets(t, target, 1)
		if f := pkts[0][12]; f != byte(TsPktCommand)|TsFlagNewprotocol|TsFlagCompressed {
			t.Fatalf("flags = %#02x, want %#02x (command|newprotocol|compressed)",
				f, byte(TsPktCommand)|TsFlagNewprotocol|TsFlagCompressed)
		}
		payload, _ := tsTestDecode(t, pkts)
		if string(payload) != cmd {
			t.Fatalf("round-trip mismatch: got %d bytes, want %d", len(payload), len(cmd))
		}
	})

	t.Run("compressible 2600-byte command still fits one packet", func(t *testing.T) {
		tc, target := tsTestSender(t)
		cmd := "clientupdate client_description=" +
			strings.Repeat("the quick brown fox jumps over the lazy dog. ", 58)
		if len(cmd) <= TsMaxPayloadC2S {
			t.Fatalf("test command too small: %d", len(cmd))
		}
		if _, err := tc.ForTestTsSendCommand(cmd); err != nil {
			t.Fatalf("tsSendCommand: %v", err)
		}
		pkts := tsTestReadPackets(t, target, 1)
		if f := pkts[0][12]; f&TsFlagFragmented != 0 || f&TsFlagCompressed == 0 {
			t.Fatalf("flags = %#02x, want a single compressed (0x40) packet", f)
		}
		payload, _ := tsTestDecode(t, pkts)
		if string(payload) != cmd {
			t.Fatalf("round-trip mismatch: got %d bytes, want %d", len(payload), len(cmd))
		}
	})

	t.Run("incompressible 1500-byte command keeps raw fragmentation", func(t *testing.T) {
		tc, target := tsTestSender(t)
		rnd := uint32(12345)
		var b strings.Builder
		for b.Len() < 1500 {
			rnd = rnd*1664525 + 1013904223
			b.WriteByte(byte(rnd >> 24))
		}
		cmd := b.String()
		if _, err := tc.ForTestTsSendCommand(cmd); err != nil {
			t.Fatalf("tsSendCommand: %v", err)
		}
		wantPkts := (len(cmd) + TsMaxPayloadC2S - 1) / TsMaxPayloadC2S
		pkts := tsTestReadPackets(t, target, wantPkts)
		for i, p := range pkts {
			f := p[12]
			if f&TsFlagCompressed != 0 {
				t.Fatalf("packet %d has compressed flag %#02x on an incompressible command", i, f)
			}
			wantFrag := i == 0 || i == wantPkts-1
			if (f&TsFlagFragmented != 0) != wantFrag {
				t.Fatalf("packet %d flags %#02x: fragmented=%v, want %v", i, f, f&TsFlagFragmented != 0, wantFrag)
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
		if len(cmd) >= TsMaxPayloadC2S {
			t.Fatalf("test command too big: %d", len(cmd))
		}
		if _, err := tc.ForTestTsSendCommand(cmd); err != nil {
			t.Fatalf("tsSendCommand: %v", err)
		}
		pkts := tsTestReadPackets(t, target, 1)
		want := byte(TsPktCommand) | TsFlagNewprotocol
		if f := pkts[0][12]; f != want {
			t.Fatalf("flags = %#02x, want %#02x (no compression below the fragment threshold)", f, want)
		}
		payload, _ := tsTestDecode(t, pkts)
		if string(payload) != cmd {
			t.Fatalf("payload mismatch: %q", payload)
		}
	})
}

func TestTS3SendCommandPacketIDsSequential(t *testing.T) {
	tc, target := tsTestSender(t)
	rnd := uint32(999)
	var b strings.Builder
	for b.Len() < 1200 {
		rnd = rnd*1664525 + 1013904223
		b.WriteByte(byte(rnd >> 24))
	}
	first, err := tc.ForTestTsSendCommand(b.String())
	if err != nil {
		t.Fatalf("tsSendCommand: %v", err)
	}
	pkts := tsTestReadPackets(t, target, 3)
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
