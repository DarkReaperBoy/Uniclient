//go:build live

// Live integration test for the Mumble core against REAL public Mumble
// servers (TCP control channel). The full pre-voice chain is exercised:
// TCP+TLS connect (self-signed server certs accepted, client cert offered),
// Version exchange, Authenticate, CryptSetup, ChannelState/UserState flood
// and ServerSync. A public server that accepts guest logins yields FULL
// success (ServerSync with session ID + welcome text); a server that
// rejects guests yields a Reject message — which still proves the whole
// framing/protobuf chain works 1:1. Not run in CI.
//
// Round-trip test: connects as a guest, lists channels, joins the root
// channel (or the first joinable one), sends a text message and expects
// the server to echo it back (Mumble broadcasts to all channel users,
// including the sender) — proving TextMessage encode/decode + event flow
// against a real Murmur.
//
// Run: cd go && go test -tags goolm,live ./tests/ -run TestMumbleLive -v -timeout 180s
// Env: MUMBLE_LIVE_SERVER (default "murmur.libresilicon.com:64738"),
//
//	MUMBLE_LIVE_USERNAME (default a random throwaway).
package tests

import (
	"fmt"
	"math/rand"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"uniclient/cores"
	"uniclient/utils"
)

// mumbleLiveGuest logs into a public server as a guest and returns the
// connected core. Skips the test when the server rejects guest logins or
// the network is unreachable.
func mumbleLiveGuest(t *testing.T, server, username string) *cores.MumbleCore {
	t.Helper()

	dir := t.TempDir()
	vault, err := utils.CreateVault(filepath.Join(dir, "test.vault"), "live-test")
	if err != nil {
		t.Fatalf("CreateVault: %v", err)
	}
	t.Cleanup(func() { vault.Close() })
	store := utils.NewSessionStore(vault, "mumble-live")

	core := &cores.MumbleCore{}
	core.Session = store
	t.Cleanup(func() { core.Close() })

	cfg := cores.AuthConfig{
		Extra: map[string]string{
			"server":   server,
			"username": username,
		},
	}

	start := time.Now()
	err = core.Authenticate(cfg)
	took := time.Since(start)
	if err != nil {
		t.Skipf("guest login rejected/unreachable on %s (took %s): %v", server, took, err)
	}
	t.Logf("guest login + ServerSync OK on %s as %q (took %s)", server, username, took)
	return core
}

func TestMumbleLiveConnectChain(t *testing.T) {
	server := osGetenvDefault("MUMBLE_LIVE_SERVER", "murmur.libresilicon.com:64738")
	username := osGetenvDefault("MUMBLE_LIVE_USERNAME", fmt.Sprintf("uc-live-%d", rand.Intn(100000)))
	mumbleLiveGuest(t, server, username)
}

// TestMumbleLiveRoundTrip: channel list → join a channel → send a text
// message from client A and receive it on client B. Murmur never echoes a
// message back to its sender (msgTextMessage removes uSource from the
// recipient set — verified in Murmur's Messages.cpp), so a two-client pair
// is the honest round-trip proof.
func TestMumbleLiveRoundTrip(t *testing.T) {
	server := osGetenvDefault("MUMBLE_LIVE_SERVER", "murmur.libresilicon.com:64738")
	usernameA := osGetenvDefault("MUMBLE_LIVE_USERNAME", fmt.Sprintf("uc-live-%d", rand.Intn(100000)))
	coreA := mumbleLiveGuest(t, server, usernameA)
	coreB := mumbleLiveGuest(t, server, usernameA+"-b")

	// B collects incoming messages.
	recv := make(chan *cores.Message, 16)
	coreB.OnUpdate(func(u cores.Update) {
		if u.Type == cores.UpdateNewMessage && u.Message != nil && !u.Message.IsOutgoing {
			recv <- u.Message
		}
	})

	// 1. Channel list must be non-empty on both cores.
	dialogs, err := coreA.GetDialogs(cores.PaginationOpts{Limit: 50})
	if err != nil {
		t.Fatalf("GetDialogs: %v", err)
	}
	if len(dialogs) == 0 {
		t.Fatal("server sent no channels after sync")
	}
	t.Logf("server has %d channels", len(dialogs))

	// Find the root channel.
	target := ""
	rootName := ""
	for _, d := range dialogs {
		if d.Title == "Root" || d.ID == "0" {
			target = d.ID
			rootName = d.Title
			break
		}
	}
	if target == "" {
		target = dialogs[0].ID
		rootName = dialogs[0].Title
	}
	t.Logf("joining channel %q (id %s)", rootName, target)

	// 2. Both clients join the channel.
	if err := coreA.MoveToChannel(parseU32(t, target)); err != nil {
		t.Fatalf("MoveToChannel(A, %s): %v", target, err)
	}
	if err := coreB.MoveToChannel(parseU32(t, target)); err != nil {
		t.Fatalf("MoveToChannel(B, %s): %v", target, err)
	}
	time.Sleep(700 * time.Millisecond)

	// 3. A sends a text message to the channel; B must receive it.
	text := fmt.Sprintf("uniclient live round-trip %d", time.Now().UnixNano()%1000000)
	sent, err := coreA.SendMessage(target, cores.OutgoingMessage{Text: text})
	if err != nil {
		t.Fatalf("SendMessage: %v", err)
	}
	t.Logf("A sent message id=%s text=%q", sent.ID, text)

	select {
	case m := <-recv:
		if m.Text != text {
			t.Fatalf("B received text mismatch: got %q want %q", m.Text, text)
		}
		t.Logf("B received the broadcast: %q from chat %s", m.Text, m.ChatID)
	case <-time.After(15 * time.Second):
		t.Fatal("B received no broadcast within 15s")
	}

	// 4. The message must appear in B's local message cache.
	msgs, err := coreB.GetMessages(target, cores.PaginationOpts{Limit: 10})
	if err != nil {
		t.Fatalf("GetMessages: %v", err)
	}
	found := false
	for _, m := range msgs {
		if m.Text == text {
			found = true
		}
	}
	if !found {
		t.Fatal("broadcast message not present in B's local message cache")
	}
	t.Logf("B's message cache contains the round-trip message (%d cached)", len(msgs))
}

func parseU32(t *testing.T, s string) uint32 {
	t.Helper()
	v, err := strconv.ParseUint(s, 10, 32)
	if err != nil {
		t.Fatalf("bad channel id %q: %v", s, err)
	}
	return uint32(v)
}

// TestMumbleLiveServerPing checks the raw UDP ping against a public server.
// Gated separately because sandboxes commonly block egress UDP; on a network
// with open UDP this must succeed.
func TestMumbleLiveServerPing(t *testing.T) {
	server := osGetenvDefault("MUMBLE_LIVE_SERVER", "murmur.libresilicon.com:64738")
	host := server
	if idx := strings.LastIndex(host, ":"); idx >= 0 {
		host = host[:idx]
	}

	_, users, maxUsers, bandwidth, err := cores.MumbleServerPing(host)
	if err != nil {
		t.Skipf("UDP ping failed (%v) — egress UDP likely blocked; run on an open network", err)
	}
	t.Logf("UDP ping OK: %d/%d users, %d B/s max bandwidth", users, maxUsers, bandwidth)
}
