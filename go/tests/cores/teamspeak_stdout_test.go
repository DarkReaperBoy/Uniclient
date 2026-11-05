package tests

import (
	"io"
	"os"
	"testing"
	"time"
	. "uniclient/cores"
)

func TestTSReceivePathSilentOnBadPackets(t *testing.T) {
	core, srv := newScriptedTSCore(t, tsScriptedConfig{ServerName: "Intact"})

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
			srv.sendRaw(cmd)

			ack := make([]byte, 13+2)
			ack[12] = 0x06
			srv.sendRaw(ack)

			voice := make([]byte, 13+8)
			voice[12] = 0x00
			srv.sendRaw(voice)
		}
		time.Sleep(300 * time.Millisecond)
	}()
	_ = w.Close()
	out, _ := io.ReadAll(r)
	_ = r.Close()

	if len(out) > 0 {
		t.Errorf("%d bytes of unconditional output on hostile packets (B-42): %.300q", len(out), string(out))
	}
	srv.PushAtGen(0, "initserver virtualserver_name="+TsEscape("Alive"))
	tsWaitServerName(t, core, "Alive", "post-hostile good command — the receive loop must survive the garbage")
}
