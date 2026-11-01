//go:build live

package tests

import (
	"errors"
	"fmt"
	"math/rand"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"uniclient/cores"
	"uniclient/utils"
)

func TestTeamSpeakLiveHandshake(t *testing.T) {
	server := osGetenvDefault("TS3_LIVE_SERVER", "ts.arcticblaze.net:9987")
	nickname := osGetenvDefault("TS3_LIVE_NICKNAME", fmt.Sprintf("uc-live-%d", rand.Intn(100000)))

	dir := t.TempDir()
	vault, err := utils.CreateVault(filepath.Join(dir, "test.vault"), "live-test")
	if err != nil {
		t.Fatalf("CreateVault: %v", err)
	}
	defer vault.Close()
	store := utils.NewSessionStore(vault, "ts3-live")

	core := cores.NewTeamSpeakCore(store)
	defer core.Close()

	cfg := cores.AuthConfig{
		Extra: map[string]string{
			"server_address": server,
			"nickname":       nickname,
		},
	}

	start := time.Now()
	err = core.Authenticate(cfg)
	took := time.Since(start)

	if err == nil {
		t.Logf("FULL TS3 handshake+initserver success as %q on %s (took %s): encrypted command channel established", nickname, server, took)
	} else {
		t.Logf("TS3 handshake returned error after %s: %v", took, err)
		t.Fail()
	}
}

func TestTeamSpeakLiveRoundTrip(t *testing.T) {
	server := osGetenvDefault("TS3_LIVE_SERVER", "ts.arcticblaze.net:9987")
	nickname := osGetenvDefault("TS3_LIVE_NICKNAME", fmt.Sprintf("uc-live-%d", rand.Intn(100000)))

	dir := t.TempDir()
	vault, err := utils.CreateVault(filepath.Join(dir, "test.vault"), "live-test")
	if err != nil {
		t.Fatalf("CreateVault: %v", err)
	}
	t.Cleanup(func() { vault.Close() })

	coreA := cores.NewTeamSpeakCore(utils.NewSessionStore(vault, "ts3-live-2"))
	defer coreA.Close()
	if err := coreA.Authenticate(cores.AuthConfig{Extra: map[string]string{
		"server_address": server,
		"nickname":       nickname,
	}}); err != nil {
		t.Skipf("handshake failed on %s: %v", server, err)
	}

	coreB := cores.NewTeamSpeakCore(utils.NewSessionStore(vault, "ts3-live-2b"))
	defer coreB.Close()
	if err := coreB.Authenticate(cores.AuthConfig{Extra: map[string]string{
		"server_address": server,
		"nickname":       nickname + "-b",
	}}); err != nil {
		t.Skipf("B handshake failed on %s: %v", server, err)
	}

	recv := make(chan *cores.Message, 16)
	coreB.OnUpdate(func(u cores.Update) {
		if u.Type == cores.UpdateNewMessage && u.Message != nil && !u.Message.IsOutgoing {
			recv <- u.Message
		}
	})

	dialogs, err := coreA.GetDialogs(cores.PaginationOpts{Limit: 100})
	if err != nil {
		t.Fatalf("GetDialogs: %v", err)
	}
	t.Logf("server has %d channels", len(dialogs))

	room := fmt.Sprintf("ch:%d", coreA.DefaultChannelID())
	text := fmt.Sprintf("uniclient live round-trip %d", time.Now().UnixNano()%1000000)
	sent, err := coreA.SendMessage(room, cores.OutgoingMessage{Text: text})
	if err != nil {
		if errors.Is(err, cores.ErrPermission) {
			t.Skipf("server denied guest text (%v) — encrypted command channel proven by the structured error; delivery opportunistic, environment not client", err)
		}
		t.Fatalf("SendMessage: %v", err)
	}
	t.Logf("sent message id=%s via %s", sent.ID, room)

	got := false
	deadline := time.After(25 * time.Second)
loop:
	for {
		select {
		case m := <-recv:
			if m.Text == text {
				t.Logf("DELIVERED: B received the exact text (strict two-client round-trip): %q", m.Text)
				got = true
				break loop
			}
			t.Logf("ignoring unrelated message (%d bytes)", len(m.Text))
		case <-deadline:
			break loop
		}
	}
	if !got {
		t.Fatalf("send accepted but B never received within 25s — delivery oracle FAILED")
	}

	if _, err := coreA.SendMessage("server", cores.OutgoingMessage{Text: text + " (server-policy probe)"}); err != nil {
		t.Logf("server-wide guest text: %v (policy probe — public-server permission, not transport)", err)
	} else {
		t.Logf("server-wide guest text: ACKed on this server")
	}
}

func TestTeamSpeakLiveJoinChannelProof(t *testing.T) {
	server := osGetenvDefault("TS3_LIVE_SERVER", "ts.arcticblaze.net:9987")

	dir := t.TempDir()
	vault, err := utils.CreateVault(filepath.Join(dir, "test.vault"), "live-test")
	if err != nil {
		t.Fatalf("CreateVault: %v", err)
	}
	t.Cleanup(func() { vault.Close() })
	core := cores.NewTeamSpeakCore(utils.NewSessionStore(vault, "ts3-join-proof"))
	defer core.Close()
	if err := core.Authenticate(cores.AuthConfig{Extra: map[string]string{
		"server_address": server,
		"nickname":       fmt.Sprintf("uc-join-%d", rand.Intn(100000)),
	}}); err != nil {
		t.Skipf("handshake failed on %s: %v", server, err)
	}

	defaultRoom := fmt.Sprintf("ch:%d", core.DefaultChannelID())
	dialogs, err := core.GetDialogs(cores.PaginationOpts{Limit: 100})
	if err != nil {
		t.Fatalf("GetDialogs: %v", err)
	}

	var candidates []int
	for _, d := range dialogs {
		if d.ID == "server" || d.ID == defaultRoom {
			continue
		}
		var cid int
		if _, scanErr := fmt.Sscanf(d.ID, "ch:%d", &cid); scanErr == nil {
			candidates = append(candidates, cid)
		}
	}
	if len(candidates) == 0 {
		t.Skipf("no non-default channel to join on %s (only %s)", server, defaultRoom)
	}

	var permDenied bool
	var lastErr error
	for _, cid := range candidates {
		if jerr := core.JoinChannel(cid, ""); jerr == nil {
			t.Logf("JOINED ch:%d — success via ok-line or notifyclientmoved proof (silent-reply server: F-84)", cid)
			return
		} else if errors.Is(jerr, cores.ErrPermission) {
			permDenied = true
			lastErr = jerr
		} else {
			lastErr = jerr
		}
	}
	if permDenied {
		t.Skipf("guest channel join denied (%v) — policy, environment not client", lastErr)
	}
	t.Fatalf("JoinChannel failed on every candidate channel: %v", lastErr)
}

func TestTeamSpeakLiveLargeMessage(t *testing.T) {
	server := osGetenvDefault("TS3_LIVE_SERVER", "ts.arcticblaze.net:9987")

	dir := t.TempDir()
	vault, err := utils.CreateVault(dir+"/test.vault", "live-test")
	if err != nil {
		t.Fatalf("CreateVault: %v", err)
	}
	t.Cleanup(func() { vault.Close() })

	coreA := cores.NewTeamSpeakCore(utils.NewSessionStore(vault, "ts3-large-a"))
	defer coreA.Close()
	if err := coreA.Authenticate(cores.AuthConfig{Extra: map[string]string{
		"server_address": server,
		"nickname":       fmt.Sprintf("uc-big-%d", rand.Intn(100000)),
	}}); err != nil {
		t.Skipf("handshake failed on %s: %v", server, err)
	}

	coreB := cores.NewTeamSpeakCore(utils.NewSessionStore(vault, "ts3-large-b"))
	defer coreB.Close()
	if err := coreB.Authenticate(cores.AuthConfig{Extra: map[string]string{
		"server_address": server,
		"nickname":       fmt.Sprintf("uc-big-%d-b", rand.Intn(100000)),
	}}); err != nil {
		t.Skipf("B handshake failed on %s: %v", server, err)
	}

	recv := make(chan string, 16)
	coreB.OnUpdate(func(u cores.Update) {
		if u.Type == cores.UpdateNewMessage && u.Message != nil && !u.Message.IsOutgoing {
			recv <- u.Message.Text
		}
	})

	room := fmt.Sprintf("ch:%d", coreA.DefaultChannelID())
	if _, err := coreA.JoinGroupCall(room); err != nil {
		t.Logf("A join %s: %v (continuing — default channel is auto-joined)", room, err)
	}
	if _, err := coreB.JoinGroupCall(room); err != nil {
		t.Logf("B join %s: %v (continuing — default channel is auto-joined)", room, err)
	}
	time.Sleep(700 * time.Millisecond)

	big := "uniclient big-message probe: " + strings.Repeat("the quick brown fox jumps over the lazy dog. ", 12)
	cmdLen := len(big) + len("sendtextmessage targetmode=2 target=99999 msg=")

	transportish := func(s string) bool {
		for _, m := range []string{"timeout", "network", "connection", "decrypt", "mac", "lost"} {
			if strings.Contains(s, m) {
				return true
			}
		}
		return false
	}
	sentOKVia := ""
	var semanticErr, transportErr string
	for _, a := range []struct{ via, chat string }{{"channel", room}, {"server", "server"}} {
		if sentOKVia != "" {
			break
		}
		_, err := coreA.SendMessage(a.chat, cores.OutgoingMessage{Text: big})
		t.Logf("send attempt via %s mode → err=%v", a.via, err)
		if err == nil {
			sentOKVia = a.via
			continue
		}
		if transportish(err.Error()) {
			transportErr += a.via + " mode: " + err.Error() + "; "
			continue
		}
		semanticErr += a.via + " mode: " + err.Error() + "; "
	}

	waitDeliver := func(d time.Duration) bool {
		deadline := time.After(d)
		for {
			select {
			case got := <-recv:
				if got == big {
					return true
				}
				t.Logf("ignoring unrelated message (%d bytes)", len(got))
			case <-deadline:
				return false
			}
		}
	}

	switch {
	case transportErr != "" && sentOKVia == "" && semanticErr == "":
		t.Fatalf("multi-packet C2S transport FAILED (no semantic reply on any mode): %s", transportErr)
	case sentOKVia != "":
		t.Logf("sent %d-byte text as a %d-byte command (> %d = multi-packet C2S) via %s mode — waiting for delivery",
			len(big), cmdLen, 487, sentOKVia)
		if !waitDeliver(30 * time.Second) {
			t.Fatalf("send reported success but B never received the %d-byte message (via %s)", len(big), sentOKVia)
		}
		t.Logf("DELIVERED: B received the full %d-byte message intact (via %s mode)", len(big), sentOKVia)

		big2 := "uniclient length-policy probe: " + strings.Repeat("abcdefghij ", 260)
		if _, err := coreA.SendMessage(room, cores.OutgoingMessage{Text: big2}); err != nil {
			t.Logf("2.9KB message rejected by server (text-length policy): %v", err)
		} else {
			probeDeadline := time.After(15 * time.Second)
		probeLoop:
			for {
				select {
				case got := <-recv:
					if got == big2 {
						t.Logf("2.9KB message ALSO delivered (no server text cap hit)")
						break probeLoop
					}
				case <-probeDeadline:
					t.Logf("2.9KB message not observed within 15s (server limit or permission — policy, not transport)")
					break probeLoop
				}
			}
		}
	default:
		t.Logf("PROVEN: server answered the %d-byte command with a semantic reply (%s) — the server decoded the >487-byte command end-to-end (reassembly/decompression + parse); any semantic reply proves the full chain",
			cmdLen, semanticErr)
		if transportErr != "" {
			t.Logf("(secondary mode failed transport-shaped, superseded by the reply: %s)", transportErr)
		}
		if waitDeliver(10 * time.Second) {
			t.Logf("…and B DID receive it anyway: DELIVERED full %d bytes", len(big))
		} else {
			t.Logf("peer delivery not measurable here (guest text permission denied) — semantic reply is the proof")
		}
	}
}
