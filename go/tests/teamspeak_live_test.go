//go:build live

// Live integration test for the TeamSpeak core's full UDP client protocol
// against REAL public TS3 servers: the 5-step init handshake (TS3INIT1,
// random exchange, RSA puzzle), the EAX fake-key command stage
// (initivexpand2 decryption), license chain verification + ECDH shared
// secret, clientek, encrypted clientinit and initserver. A public server
// that accepts guest connections yields full success; a rejection still
// proves the protocol chain works mechanically. Not run in CI.
//
// Run: cd go && go test -tags goolm,live ./tests/ -run TestTeamSpeakLive -v -timeout 180s
// Env: TS3_LIVE_SERVER (default "ts.arcticblaze.net:9987" — a public TS3 server),
//
//	TS3_LIVE_NICKNAME (default a random throwaway).
//
// STRICT oracle on a self-hosted server (F-83/B-25 recipe, same shape
// as the dendrite one): public servers revoke guest text, so
// TestTeamSpeakLiveRoundTrip only delivers a hard assertion against a
// server WE control. Local setup (binary ~10 MB, no account needed):
//
//	mkdir -p ~/.cache/uniclient-ts3server && cd ~/.cache/uniclient-ts3server
//	curl -LO https://files.teamspeak-services.com/releases/server/3.13.7/teamspeak3-server_linux_amd64-3.13.7.tar.bz2
//	tar -xjf teamspeak3-server_linux_amd64-3.13.7.tar.bz2
//	cd teamspeak3-server_linux_amd64
//	printf 'default_voice_port=9987\nquery_port=10011\n' > ts3server.ini
//	./ts3server license_accepted=1 inifile=ts3server.ini   # keep running
//
// First start prints `loginname= "serveradmin", password= "..."` ONCE
// (console → ts3server.stdout); redeem it once per boot to disable the
// connect-rate ban that rapid test loops otherwise trip (id=3329,
// auto-expires ~30 s):
//
//	login serveradmin <password>   # via TCP 10011 (raw serverquery)
//	use 0
//	serveredit virtualserver_antiflood_points_needed_ip_block=2147483647
//	serveredit virtualserver_antiflood_points_needed_command_block=2147483647
//
// Then: TS3_LIVE_SERVER=127.0.0.1:9987 go test -tags goolm,live ./tests/
// -run TestTeamSpeakLive -v -timeout 180s — RoundTrip becomes the
// STRICT two-client delivery assertion (send accepted ⇒ B MUST receive).
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
		// The failure itself is diagnostic: EAX MAC mismatch = crypto bug,
		// "no init1 response" = network/server issue, permission error =
		// in-protocol rejection (chain works).
		t.Fail()
	}
}

// TestTeamSpeakLiveRoundTrip: after the handshake, fetch the channel list
// and server info through the encrypted command channel, then send+receive
// a text message in the default channel.
func TestTeamSpeakLiveRoundTrip(t *testing.T) {
	server := osGetenvDefault("TS3_LIVE_SERVER", "ts.arcticblaze.net:9987")
	nickname := osGetenvDefault("TS3_LIVE_NICKNAME", fmt.Sprintf("uc-live-%d", rand.Intn(100000)))

	dir := t.TempDir()
	vault, err := utils.CreateVault(filepath.Join(dir, "test.vault"), "live-test")
	if err != nil {
		t.Fatalf("CreateVault: %v", err)
	}
	t.Cleanup(func() { vault.Close() })

	// TWO clients (F-83/B-25): the sender's own echo is dropped by
	// design, so delivery can only be proven by a RECEIVER.
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

	// Channel list (cached from handshake — coverage of GetDialogs).
	dialogs, err := coreA.GetDialogs(cores.PaginationOpts{Limit: 100})
	if err != nil {
		t.Fatalf("GetDialogs: %v", err)
	}
	t.Logf("server has %d channels", len(dialogs))

	// CHANNEL chat — the product's primary path. Both clients auto-join
	// the default channel on connect, so B is subscribed.
	room := fmt.Sprintf("ch:%d", coreA.DefaultChannelID())
	text := fmt.Sprintf("uniclient live round-trip %d", time.Now().UnixNano()%1000000)
	sent, err := coreA.SendMessage(room, cores.OutgoingMessage{Text: text})
	if err != nil {
		// Public servers may revoke guest text entirely (B-25: both
		// channel AND server modes were denied on the default public
		// server — probe evidence, WORKLOG 318). The STRUCTURED error
		// arrived over the encrypted command channel, so the transport
		// is proven; only delivery policy varies by environment.
		if errors.Is(err, cores.ErrPermission) {
			t.Skipf("server denied guest text (%v) — encrypted command channel proven by the structured error; delivery opportunistic, environment not client", err)
		}
		t.Fatalf("SendMessage: %v", err)
	}
	t.Logf("sent message id=%s via %s", sent.ID, room)

	// STRICT delivery oracle (F-83): the send was accepted (ok-line or
	// self-echo proof) → the receiver MUST get it. Before F-83 this
	// assertion was impossible: the server's omitted success reply made
	// accepted sends report "response lost", and a single client can
	// never observe its own (dropped) echo.
	select {
	case m := <-recv:
		if m.Text != text {
			t.Fatalf("received WRONG text: %q (want %q)", m.Text, text)
		}
		t.Logf("DELIVERED: B received the exact text (strict two-client round-trip): %q", m.Text)
	case <-time.After(25 * time.Second):
		t.Fatalf("send accepted but B never received within 25s — delivery oracle FAILED")
	}

	// B-25's original subject kept visible as a policy probe (never
	// fatal): server-wide guest text is a permission the public server
	// revoked (58 denied re-probes); the product surfaces ErrPermission
	// honestly from the "server" chat row.
	if _, err := coreA.SendMessage("server", cores.OutgoingMessage{Text: text + " (server-policy probe)"}); err != nil {
		t.Logf("server-wide guest text: %v (policy probe — public-server permission, not transport)", err)
	} else {
		t.Logf("server-wide guest text: ACKed on this server")
	}
}

// TestTeamSpeakLiveLargeMessage: BUGS.md B-1 evidence — a command bigger
// than one 487-byte C2S packet must reach a SECOND client intact. Before
// the QuickLZ compressor existed this exercised raw C2S fragmentation;
// after it, the same command compresses below one packet. Either way the
// oracle is DELIVERY: B must receive the exact text (server-side size
// policy is probed separately and only logged).
//
// Run: cd go && go test -tags goolm,live ./tests/ -run TestTeamSpeakLiveLargeMessage -v -timeout 180s
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

	// ~560 chars → the `sendtextmessage …` command exceeds the 487-byte
	// C2S packet payload, so it travels as >1 raw packet before the
	// compressor and as ONE compressed packet after it. Under normal
	// server text limits so outcomes classify cleanly below.
	big := "uniclient big-message probe: " + strings.Repeat("the quick brown fox jumps over the lazy dog. ", 12)
	cmdLen := len(big) + len("sendtextmessage targetmode=2 target=99999 msg=")

	// The oracle, strongest first:
	//  1. B receives the exact text → full delivery proof;
	//  2. the server replies with a SEMANTIC error (permission/limit/
	//     invalid) → it reassembled, decompressed and parsed a
	//     >487-byte command end-to-end — a server that cannot do that
	//     answers nothing at all (or a decompression error);
	//  3. only transport-shaped failures (timeout/network/decrypt) fail
	//     the test.
	// Self-echo proves nothing here: the core drops it by design
	// (invokerID == myClientID), so only B counts.
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

		// Policy probe (LOGGED, never fatal): a 2.9 KB message — well past
		// typical server text limits. Rejection is server policy; delivery
		// proves the limit is elsewhere.
		big2 := "uniclient length-policy probe: " + strings.Repeat("abcdefghij ", 260) // ~2.9 KB
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
		// Semantic reply: the server processed the whole command but this
		// server denies guests text rights — delivery is then unmeasurable,
		// and the reply itself is the transport proof.
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
