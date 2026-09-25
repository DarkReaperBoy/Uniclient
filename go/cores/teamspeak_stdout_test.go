package cores

import (
	"io"
	"os"
	"testing"
)

// TestTSReceivePathSilentOnBadPackets: BUGS B-42 — the TeamSpeak
// receive path printed decrypt/decompress/drop diagnostics
// UNCONDITIONALLY to stdout, so a hostile or misconfigured server
// could make the client emit one line per packet (flood vector on an
// unbuffered stdout syscall; a GUI app has no console to absorb it
// anyway). The file's own convention is tsLogf (UNICLIENT_TS3_DEBUG
// gated). RED pre-fix: captured stdout is non-empty. GREEN: silent.
func TestTSReceivePathSilentOnBadPackets(t *testing.T) {
	_, tc := newWireFuzzCore(t)

	old := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	os.Stdout = w
	func() {
		defer func() { os.Stdout = old }()
		for i := 0; i < 50; i++ {
			// Framing-valid packets that fail everything downstream:
			// fake-key command decrypt, ack decrypt, voice crypto.
			cmd := make([]byte, 13+16)
			cmd[12] = 0x02 | 0x20 // tsPktCommand | newprotocol
			tc.tsHandlePacket(cmd)

			ack := make([]byte, 13+2)
			ack[12] = 0x06 // tsPktAck
			tc.tsHandlePacket(ack)

			voice := make([]byte, 13+8)
			voice[12] = 0x00 // tsPktVoice
			tc.tsHandlePacket(voice)
		}
	}()
	_ = w.Close()
	out, _ := io.ReadAll(r)
	_ = r.Close()

	if len(out) > 0 {
		t.Errorf("%d bytes of unconditional output on hostile packets (B-42): %.300q", len(out), string(out))
	}
}
