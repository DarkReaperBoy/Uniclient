//go:build live

// Live integration test for the Bale core's pre-auth chain against the REAL
// production servers (next-ws.bale.ai). Previous sessions saw the endpoints
// geo-blocked; as of 2026-09-12 they are reachable from this VM.
//
// Independent research (primary source: the production web client bundle at
// web.bale.ai, index.4402958e45.js, verified this session):
//   - grpc base URL: https://next-ws.bale.ai ; ws: wss://next-ws.bale.ai/ws/
//     (exactly the pair the core uses)
//   - bale.auth.v1.Auth/StartPhoneAuth request layout on the wire:
//     1=phoneNumber int64, 2=appId int32, 3=apiKey string, 4=deviceHash
//     bytes, 5=deviceTitle string, 9=sendCodeType int32, 10=options packed
//     int32 — matches the core's field map (ASCII deviceHash string and
//     {"0":1} options encode to identical wire bytes)
//   - bale.auth.v1.Auth/ValidateCode layout: 1=transactionHash, 2=code,
//     3=isJwt BoolValue ({"1":1} ≡ {value:true} on the wire), 4=futureAuth-
//     Tokens rep string, 5=language int32 — also matches
//   - the production app credentials {id:4, apiKey:C28D46DC...} used by the
//     core exist verbatim in the production bundle
//
// The test drives the core's own Authenticate path with a deliberately
// INVALID phone number (1). The server must answer with a structured gRPC
// error — proving protobuf encode → gRPC-Web framing → HTTP transport →
// response decode → error mapping all work. A transport error is a FAILURE.
//
// Run: cd go && go test -tags goolm,live ./tests/ -run TestBaleLive -v -timeout 120s
package tests

import (
	"path/filepath"
	"strings"
	"testing"
	"time"

	"uniclient/cores"
	"uniclient/utils"
)

// TestBaleLiveStartPhoneAuthInvalid pins the unary gRPC-Web pre-auth chain.
func TestBaleLiveStartPhoneAuthInvalid(t *testing.T) {
	dir := t.TempDir()
	vault, err := utils.CreateVault(filepath.Join(dir, "test.vault"), "live-test")
	if err != nil {
		t.Fatalf("CreateVault: %v", err)
	}
	defer vault.Close()
	store := utils.NewSessionStore(vault, "bale-live")

	core := cores.NewBaleCore(store)
	defer core.Logout()

	start := time.Now()
	// Phone "1" is deliberately invalid: the server must reject it without
	// dispatching any SMS.
	err = core.Authenticate(cores.AuthConfig{Phone: "1"})
	took := time.Since(start)

	if err == nil {
		t.Fatalf("Authenticate unexpectedly succeeded with an invalid phone (took %s)", took)
	}

	msg := err.Error()
	t.Logf("Authenticate failed as expected after %s: %v", took.Round(time.Millisecond), err)

	// Transport-layer failures mean the chain is broken.
	for _, broken := range []string{
		"timeout connecting to Bale",
		"dial tcp",
		"connection refused",
		"no such host",
		"EOF",
		"StartPhoneAuth: network",
	} {
		if strings.Contains(msg, broken) {
			t.Fatalf("pre-auth chain broken at transport layer (%q): %v", broken, err)
		}
	}

	// A structured gRPC answer proves the protobuf round-trip works.
	structured := strings.Contains(msg, "gRPC error") ||
		strings.Contains(msg, "grpc-message") ||
		strings.Contains(msg, "StartPhoneAuth")
	if !structured {
		t.Fatalf("expected a structured gRPC error from StartPhoneAuth, got: %v", err)
	}
}
