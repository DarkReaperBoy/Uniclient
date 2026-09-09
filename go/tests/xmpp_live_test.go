//go:build live

// Live integration test for the XMPP core's connection chain against a
// REAL public XMPP server (conversations.im by default): TCP connect,
// stream negotiation, STARTTLS, and the SASL SCRAM handshake with throwaway
// credentials. The expected outcome is an AUTH FAILURE from the server —
// which proves the entire pre-auth chain works mechanically (stream
// framing, TLS upgrade, SASL mechanics, stream restart). Not run in CI.
//
// Run: cd go && go test -tags goolm,live ./tests/ -run TestXMPPLive -v -timeout 120s
// Env: XMPP_LIVE_SERVER (default "conversations.im:5222"), XMPP_LIVE_JID
// (default a random throwaway), XMPP_LIVE_PASSWORD (default "wrong-pass-xyz").
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
		// Should not happen with throwaway credentials — but if the server
		// ever created the account, treat it as full success.
		t.Logf("unexpected FULL auth success as %s (took %s)", jid, took)
		return
	}

	// The failure must be an AUTH failure — anything else (dial error,
	// TLS error, XML error) means the chain is broken before SASL.
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
