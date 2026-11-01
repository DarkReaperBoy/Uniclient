package tests

import (
	"io"
	"os"
	"testing"
)

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
			cmd := make([]byte, 13+16)
			cmd[12] = 0x02 | 0x20
			tc.ForTestTsHandlePacket(cmd)

			ack := make([]byte, 13+2)
			ack[12] = 0x06
			tc.ForTestTsHandlePacket(ack)

			voice := make([]byte, 13+8)
			voice[12] = 0x00
			tc.ForTestTsHandlePacket(voice)
		}
	}()
	_ = w.Close()
	out, _ := io.ReadAll(r)
	_ = r.Close()

	if len(out) > 0 {
		t.Errorf("%d bytes of unconditional output on hostile packets (B-42): %.300q", len(out), string(out))
	}
}
