package tests

import (
	"encoding/base64"
	"fmt"
	"strings"
	"testing"
	"time"
	. "uniclient/cores"

	"uniclient/utils"
)

func TestReadSASLElementCapsHostileStream(t *testing.T) {
	srv, addr := startMiniXMPPServer(t, "alice", "wonderland")
	srv.floodSASL = true

	core := NewXMPPCore(utils.NewSessionStore(newTestVaultXMPP(t), "xmpp-sasl-flood"))
	defer core.Logout()

	cfg := AuthConfig{
		Extra: map[string]string{
			"server":   addr,
			"jid":      "alice@localhost",
			"password": "wonderland",
			"tls":      "none",
		},
	}
	start := time.Now()
	err := core.Authenticate(cfg)
	if err == nil {
		t.Fatal("endless SASL element accepted")
	}
	want := fmt.Sprintf("exceeds %d bytes", SaslElementMax)
	if !strings.Contains(err.Error(), want) {
		t.Fatalf("err = %v, want %q", err, want)
	}
	if elapsed := time.Since(start); elapsed > 10*time.Second {
		t.Fatalf("SASL cap took %v — the flood was absorbed instead of capped", elapsed)
	}
}

func scramChallenge(t *testing.T, clientNonce, saltPlain, iterations string) string {
	t.Helper()
	return "r=" + clientNonce + "srv,s=" +
		base64.StdEncoding.EncodeToString([]byte(saltPlain)) + ",i=" + iterations
}
func TestParseScramServerFirstValid(t *testing.T) {
	snonce, salt, iters, err := ParseScramServerFirst(
		scramChallenge(t, "cn123", "saltysalt", "4096"), "cn123")
	if err != nil {
		t.Fatalf("valid challenge: %v", err)
	}
	if snonce != "cn123srv" {
		t.Fatalf("server nonce = %q", snonce)
	}
	if string(salt) != "saltysalt" {
		t.Fatalf("salt = %q", salt)
	}
	if iters != 4096 {
		t.Fatalf("iterations = %d", iters)
	}
}

func TestParseScramServerFirstRejectsHugeIterations(t *testing.T) {
	_, _, _, err := ParseScramServerFirst(
		scramChallenge(t, "cn", "salt", "2000000000"), "cn")
	if err == nil || !strings.Contains(err.Error(), "iterations out of range") {
		t.Fatalf("huge iterations: err = %v, want iterations out of range", err)
	}
	for _, bad := range []string{"0", "-5"} {
		if _, _, _, err := ParseScramServerFirst(scramChallenge(t, "cn", "salt", bad), "cn"); err == nil {
			t.Fatalf("iterations=%s accepted", bad)
		}
	}
}

func TestParseScramServerFirstRejectsOversizedSalt(t *testing.T) {
	big := strings.Repeat("S", 4096)
	_, _, _, err := ParseScramServerFirst(scramChallenge(t, "cn", big, "4096"), "cn")
	if err == nil || !strings.Contains(err.Error(), "salt too large") {
		t.Fatalf("oversized salt: err = %v, want salt too large", err)
	}
}

func TestParseScramServerFirstRejectsNonceMismatch(t *testing.T) {
	_, _, _, err := ParseScramServerFirst(scramChallenge(t, "OTHER", "salt", "4096"), "cn")
	if err == nil || !strings.Contains(err.Error(), "doesn't start with client nonce") {
		t.Fatalf("nonce mismatch: err = %v", err)
	}
	_, _, _, err = ParseScramServerFirst("r=cnsrv,s=!!notb64!!,i=4096", "cn")
	if err == nil || !strings.Contains(err.Error(), "bad salt") {
		t.Fatalf("bad salt b64: err = %v", err)
	}
	_, _, _, err = ParseScramServerFirst("r=cnsrv,s=c2FsdA==,i=abc", "cn")
	if err == nil || !strings.Contains(err.Error(), "bad iterations") {
		t.Fatalf("bad iterations: err = %v", err)
	}
}
