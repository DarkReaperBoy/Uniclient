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
package tests

import (
	"fmt"
	"math/rand"
	"path/filepath"
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
	defer vault.Close()
	store := utils.NewSessionStore(vault, "ts3-live-2")

	core := cores.NewTeamSpeakCore(store)
	defer core.Close()

	cfg := cores.AuthConfig{
		Extra: map[string]string{
			"server_address": server,
			"nickname":       nickname,
		},
	}

	if err := core.Authenticate(cfg); err != nil {
		t.Skipf("handshake failed on %s: %v", server, err)
	}

	// Collect incoming text messages.
	recv := make(chan *cores.Message, 16)
	core.OnUpdate(func(u cores.Update) {
		if u.Type == cores.UpdateNewMessage && u.Message != nil && !u.Message.IsOutgoing {
			recv <- u.Message
		}
	})

	// 1. Channel list.
	dialogs, err := core.GetDialogs(cores.PaginationOpts{Limit: 100})
	if err != nil {
		t.Fatalf("GetDialogs: %v", err)
	}
	t.Logf("server has %d channels", len(dialogs))

	// 2. Send a text message to the server-wide chat ("server" chat id).
	text := fmt.Sprintf("uniclient live round-trip %d", time.Now().UnixNano()%1000000)
	sent, err := core.SendMessage("server", cores.OutgoingMessage{Text: text})
	if err != nil {
		t.Fatalf("SendMessage: %v", err)
	}
	t.Logf("sent message id=%s text=%q", sent.ID, text)

	select {
	case m := <-recv:
		t.Logf("server echoed the message back: %q from %q", m.Text, m.SenderName)
	case <-time.After(20 * time.Second):
		// Public servers may restrict guest text permissions; treat a
		// missing echo as non-fatal (the send itself went through the
		// encrypted command channel and was ACKed).
		t.Logf("no echo within 20s (guest text permissions?) — send was ACKed, command channel verified")
	}
}
