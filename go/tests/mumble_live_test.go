//go:build live

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

func TestMumbleLiveRoundTrip(t *testing.T) {
	server := osGetenvDefault("MUMBLE_LIVE_SERVER", "murmur.libresilicon.com:64738")
	usernameA := osGetenvDefault("MUMBLE_LIVE_USERNAME", fmt.Sprintf("uc-live-%d", rand.Intn(100000)))
	coreA := mumbleLiveGuest(t, server, usernameA)
	coreB := mumbleLiveGuest(t, server, usernameA+"-b")

	recv := make(chan *cores.Message, 16)
	coreB.OnUpdate(func(u cores.Update) {
		if u.Type == cores.UpdateNewMessage && u.Message != nil && !u.Message.IsOutgoing {
			recv <- u.Message
		}
	})

	dialogs, err := coreA.GetDialogs(cores.PaginationOpts{Limit: 50})
	if err != nil {
		t.Fatalf("GetDialogs: %v", err)
	}
	if len(dialogs) == 0 {
		t.Fatal("server sent no channels after sync")
	}
	t.Logf("server has %d channels", len(dialogs))

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

	if err := coreA.MoveToChannel(parseU32(t, target)); err != nil {
		t.Fatalf("MoveToChannel(A, %s): %v", target, err)
	}
	if err := coreB.MoveToChannel(parseU32(t, target)); err != nil {
		t.Fatalf("MoveToChannel(B, %s): %v", target, err)
	}
	time.Sleep(700 * time.Millisecond)

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
