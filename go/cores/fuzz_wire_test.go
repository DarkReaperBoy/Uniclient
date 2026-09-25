package cores

import (
	"net"
	"testing"

	"uniclient/utils"
)

// Hostile-server fuzzing (slice 260): everything a remote server can
// put on the wire goes through these parsers, and a panic in any of
// them kills the whole client (§1.10 — drop the packet, never the
// app). Contract: never panic.

func FuzzTSCommand(f *testing.F) {
	f.Add([]byte(""))
	f.Add([]byte("error id=0 msg=ok"))
	f.Add([]byte("error id=2568 msg=insufficient\\sclient\\spermissions failed_permid=139"))
	f.Add([]byte("notifyclientmoved ctid=43 clid=7"))
	f.Add([]byte("channellist cid=1 channel_name=x|cid=2 channel_name=y"))
	f.Add([]byte{0x00, 0xFF, 0x0A, 0x0D})
	f.Add([]byte("key=" + string(make([]byte, 4096))))
	f.Fuzz(func(t *testing.T, data []byte) {
		_, _ = tsParseCommand(data)
	})
}

func FuzzTSPacket(f *testing.F) {
	f.Add([]byte{})
	f.Add([]byte{0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 0, 2, 0x02})
	f.Add([]byte{0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 0, 2, 0x62})
	f.Add(make([]byte, 13))               // header-only, empty payload
	f.Add(append(make([]byte, 13), 0xAA)) // header + one byte
	f.Fuzz(func(t *testing.T, data []byte) {
		_, _, _, _, _ = tsParseS2CPacket(data)
	})
}

func FuzzTSEAXDecrypt(f *testing.F) {
	f.Add([]byte{}, []byte{}, []byte{})
	f.Add([]byte{1, 2, 3}, []byte{4, 5, 6, 7}, []byte{0, 0, 0, 0, 0, 0, 0, 0})
	f.Add(make([]byte, 16), make([]byte, 5), make([]byte, 8))
	f.Fuzz(func(t *testing.T, header, ciphertext, mac []byte) {
		if len(mac) != 8 {
			t.Skip()
		}
		var macIn [8]byte
		copy(macIn[:], mac)
		// Fake-key path: what pre-crypto and hostile inputs hit.
		_, _ = tsEAXDecrypt(tsFakeKey[:], tsFakeNonce[:], header, ciphertext, macIn)
	})
}

// FuzzTSHandleServerCommand dispatches a parsed server line through the
// REAL notify handlers on a production-shaped core. Setup is hoisted
// (a per-iteration vault build throttles the worker to ~5 execs/s).
func FuzzTSHandleServerCommand(f *testing.F) {
	f.Add([]byte(""))
	f.Add([]byte("notifyclientmoved ctid=43 clid=7"))
	f.Add([]byte("notifycliententerview ctid=44 clid=9 client_nickname=x"))
	f.Add([]byte("notifytextmessage targetmode=3 invokerid=5 msg=hi"))
	f.Add([]byte("notifyclientpoke invokerid=5 invokername=b msg=p"))
	f.Add([]byte("notifychannelcreated cid=77 channel_name=z"))
	f.Add([]byte("notifyclientupdated clid=7 client_talk_power=20"))
	f.Add([]byte("channellist cid=1 channel_name=a|cid=2 channel_name=b"))
	f.Add([]byte("initserver virtualserver_name=x aclid=7"))

	core, _ := newWireFuzzCore(f)

	f.Fuzz(func(t *testing.T, data []byte) {
		name, params := tsParseCommand(data)
		if name == "notifyconnectioninforequest" {
			// Spawns a SetConnectionInfo exec goroutine per hit — unit-
			// tested elsewhere; fuzzing it would fork thousands of workers.
			t.Skip()
		}
		core.tsHandleServerCommand(tsIncomingCmd{name: name, params: params, raw: string(data)})
	})
}

// FuzzMumbleURL: mumble:// links are user/paste-controlled — parsing
// must never panic (§1.10).
func FuzzMumbleURL(f *testing.F) {
	f.Add("")
	f.Add("mumble://user:pass@host:64738/Channel/Sub")
	f.Add("mumble://host/Channel?version=1.2.3")
	f.Add("mumble://")
	f.Add("mumble://[::1]:64738/")
	f.Add("mumble://" + string(make([]byte, 4096)))
	f.Fuzz(func(t *testing.T, raw string) {
		_, _, _, _, _, _ = ParseMumbleURL(raw)
	})
}

// newWireFuzzCore builds a production-shaped core + connection exactly
// the way tsConnect leaves them before the receive loop runs:
// constructor maps, fully-initialized tsConnection (pendingCmds, both
// recvQueues, buffered cmdCh), a live UDP socket so handler-spawned
// command goroutines have somewhere to write, and a distinguishable
// self identity. Cleanup registers on t. Shared by the wire fuzz
// targets (called once, hoisted) and the receive-path unit tests.
func newWireFuzzCore(t testing.TB) (*TeamSpeakCore, *tsConnection) {
	t.Helper()
	vault, err := utils.CreateVault(t.TempDir()+"/fuzz.vault", "fuzz")
	if err != nil {
		t.Fatal(err)
	}
	core := NewTeamSpeakCore(utils.NewSessionStore(vault, "fuzz"))
	rx, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	tx, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		rx.Close()
		t.Fatal(err)
	}
	t.Cleanup(func() { rx.Close(); tx.Close(); vault.Close() })
	core.tsConn = &tsConnection{
		conn:        tx,
		addr:        rx.LocalAddr().(*net.UDPAddr),
		owner:       core,
		pendingCmds: make(map[uint16]*tsPendingCmd),
		recvQueue:   [2]map[uint16]*tsDecryptedPkt{make(map[uint16]*tsDecryptedPkt), make(map[uint16]*tsDecryptedPkt)},
		cmdCh:       make(chan tsIncomingCmd, 64),
	}
	core.myClientID = 7
	return core, core.tsConn
}
