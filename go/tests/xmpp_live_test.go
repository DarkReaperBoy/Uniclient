//go:build live

package tests

import (
	"fmt"
	"math/rand"
	"net"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"uniclient/cores"
	"uniclient/utils"
)

func TestXMPPLiveConnectChain(t *testing.T) {
	server := osGetenvDefault("XMPP_LIVE_SERVER", "conversations.im:5222")
	jid := osGetenvDefault("XMPP_LIVE_JID", fmt.Sprintf("uc-live-%d", rand.Intn(100000)))
	password := osGetenvDefault("XMPP_LIVE_PASSWORD", "wrong-pass-xyz")

	dir := t.TempDir()
	vault, err := utils.CreateVault(filepath.Join(dir, "test.vault"), "live-test")
	if err != nil {
		t.Fatalf("CreateVault: %v", err)
	}
	defer vault.Close()
	store := utils.NewSessionStore(vault, "xmpp-live")

	core := cores.NewXMPPCore(store)
	defer core.Logout()

	cfg := cores.AuthConfig{
		Extra: map[string]string{
			"server":   server,
			"jid":      jid + "@conversations.im",
			"password": password,
			"tls":      "starttls",
		},
	}

	start := time.Now()
	err = core.Authenticate(cfg)
	took := time.Since(start)

	if err == nil {
		t.Logf("unexpected FULL auth success as %s (took %s)", jid, took)
		return
	}

	if !isAuthKind(err) {
		t.Fatalf("connection chain broken before SASL (took %s): %v", took, err)
	}
	t.Logf("pre-auth chain verified in %s: server rejected throwaway credentials via SASL as expected", took)
}

func isAuthKind(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	return containsAny(msg, "auth", "not-authorized", " SASL", "authentication")
}

func containsAny(s string, subs ...string) bool {
	for _, sub := range subs {
		if len(s) >= len(sub) && (s == sub || len(s) > 0 && containsFold(s, sub)) {
			return true
		}
	}
	return false
}

func containsFold(s, sub string) bool {
	ls := len(s)
	lsub := len(sub)
	for i := 0; i+lsub <= ls; i++ {
		if equalFoldStr(s[i:i+lsub], sub) {
			return true
		}
	}
	return false
}

func equalFoldStr(a, b string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := 0; i < len(a); i++ {
		ca, cb := a[i], b[i]
		if 'A' <= ca && ca <= 'Z' {
			ca += 'a' - 'A'
		}
		if 'A' <= cb && cb <= 'Z' {
			cb += 'a' - 'A'
		}
		if ca != cb {
			return false
		}
	}
	return true
}

func TestXMPPLiveRegisterAndMessage(t *testing.T) {
	server := osGetenvDefault("XMPP_LIVE_SERVER", "conversations.im:5222")
	domain := server
	if h, _, err := net.SplitHostPort(server); err == nil {
		domain = h
	}
	username := fmt.Sprintf("uc-live-%d", rand.Intn(1000000))
	password := fmt.Sprintf("Uc!%d#x", rand.Intn(100000000))
	jid := username + "@" + domain

	dir := t.TempDir()
	vault, err := utils.CreateVault(filepath.Join(dir, "test.vault"), "live-test")
	if err != nil {
		t.Fatalf("CreateVault: %v", err)
	}
	defer vault.Close()
	store := utils.NewSessionStore(vault, "xmpp-reg-live")

	core := cores.NewXMPPCore(store)
	defer core.Logout()

	recv := make(chan string, 16)
	core.OnUpdate(func(u cores.Update) {
		if u.Type == cores.UpdateNewMessage && u.Message != nil && u.Message.Text != "" {
			recv <- u.Message.Text
		}
	})

	start := time.Now()
	err = core.Authenticate(cores.AuthConfig{
		Extra: map[string]string{
			"server":   server,
			"jid":      jid,
			"password": password,
			"tls":      "starttls",
			"register": "true",
		},
	})
	if err != nil {
		if strings.Contains(err.Error(), "ibr:") {
			t.Skipf("server declined in-band registration (%v) — policy, not a client bug; pre-auth chain still proven by TestXMPPLiveConnectChain", err)
		}
		t.Fatalf("register+auth failed (took %s): %v", time.Since(start), err)
	}
	t.Logf("registered + authenticated as %s in %s (SASL with brand-new credentials)", jid, time.Since(start))

	body := fmt.Sprintf("uniclient e2e %d", rand.Intn(1000000))
	if _, err := core.SendMessage(jid, cores.OutgoingMessage{Text: body}); err != nil {
		t.Fatalf("SendMessage: %v", err)
	}

	select {
	case got := <-recv:
		if got != body {
			t.Fatalf("round-trip text mismatch: got %q want %q", got, body)
		}
		t.Logf("MESSAGE ROUND-TRIP OK: server routed our self-addressed message back verbatim")
	case <-time.After(15 * time.Second):
		t.Skip("self-message not delivered within 15s (public-server routing); registration + SASL verified")
	}

	if err := core.UnregisterAccount(); err == nil {
		t.Log("throwaway account unregistered (XEP-0077 remove)")
	} else {
		t.Logf("cleanup: unregister not supported/failed (%v) — throwaway account left on %s", err, domain)
	}
}
