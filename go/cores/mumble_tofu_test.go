package cores

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"uniclient/utils"
)

// B-57 → F-57: mumble TLS was the only core with an unconditional
// InsecureSkipVerify (slice-285 probe proved the skip is load-bearing:
// even the default live server fails x509 verification). The fix keeps
// the skip at the dial layer (self-signed stays working) and verifies
// AFTER the handshake: PKI first, then trust-on-first-use pins stored
// in the account's SessionStore; a mismatched pin refuses the
// connection (MITM or server rotation — reset via
// UNICLIENT_MUMBLE_RESET_PIN=1).
//
// Seam-RED (recorded in WORKLOG 286): with only this file present the
// build fails — undefined: mumbleServerTOFU, mumbleSessionData.ServerPins.

// TestMumbleServerTOFUDecision tables the accept/store logic.
func TestMumbleServerTOFUDecision(t *testing.T) {
	ok := error(nil)
	bad := x509.CertificateInvalidError{} // any non-nil verify error

	cases := []struct {
		name      string
		verifyErr error
		fp        string
		stored    string
		hasPin    bool
		reset     bool
		accept    bool
		store     bool
		msgPart   string // "" = no message expected
	}{
		{"pki-valid short-circuits", ok, "fpA", "", false, false, true, false, ""},
		{"first use pins", bad, "fpA", "", false, false, true, true, "first use"},
		{"pin match accepts", bad, "fpA", "fpA", true, false, true, false, ""},
		{"mismatch refuses", bad, "fpB", "fpA", true, false, false, false, "changed"},
		{"mismatch reports both hashes", bad, "fpB", "fpA", true, false, false, false, "fpA"},
		{"mismatch mentions reset", bad, "fpB", "fpA", true, false, false, false, "UNICLIENT_MUMBLE_RESET_PIN"},
		{"reset overwrites pin", bad, "fpB", "fpA", true, true, true, true, "reset"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			accept, store, msg := mumbleServerTOFU(tc.verifyErr, tc.fp, tc.stored, tc.hasPin, tc.reset)
			if accept != tc.accept {
				t.Errorf("accept = %v, want %v", accept, tc.accept)
			}
			if store != tc.store {
				t.Errorf("store = %v, want %v", store, tc.store)
			}
			if tc.msgPart != "" && !strings.Contains(msg, tc.msgPart) {
				t.Errorf("msg = %q, want substring %q", msg, tc.msgPart)
			}
			if tc.msgPart == "" && tc.accept && msg != "" {
				t.Errorf("unexpected message on clean accept: %q", msg)
			}
		})
	}
}

// TestServerPinSurvivesCertSave is the clobber guard: saveSession used
// to rebuild mumbleSessionData from scratch (CertPEM/KeyPEM only), so
// any pin written first would be WIPED by the next client-cert save.
// Behavioral RED: fails until saveSession merges prev.ServerPins.
func TestServerPinSurvivesCertSave(t *testing.T) {
	dir := t.TempDir()
	store := utils.NewSessionStore(newTestVaultSimple(t, dir), "dc-mumble")
	core := &MumbleCore{Session: store}

	// Write a pin first (before any client-cert save).
	if err := core.storeServerPin("host.example:64738", "fp-pin-1"); err != nil {
		t.Fatalf("storeServerPin: %v", err)
	}

	// Now the cert save (requires a syntactically valid EC key pair).
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("genkey: %v", err)
	}
	keyDER, err := x509.MarshalECPrivateKey(key)
	if err != nil {
		t.Fatalf("marshal key: %v", err)
	}
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER})
	// Real self-signed DER — tls.X509KeyPair parses the certificate.
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "mumble-tofu-test"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
	}
	certDER, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatalf("create cert: %v", err)
	}
	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: certDER})
	pair, err := tls.X509KeyPair(certPEM, keyPEM)
	if err != nil {
		t.Fatalf("x509keypair: %v", err)
	}
	core.tlsCert = pair
	if err := core.saveSession(); err != nil {
		t.Fatalf("saveSession: %v", err)
	}

	// Fresh load: BOTH the pin and the cert must be there.
	var sess mumbleSessionData
	if err := store.Load(&sess); err != nil {
		t.Fatalf("load: %v", err)
	}
	if sess.ServerPins["host.example:64738"] != "fp-pin-1" {
		t.Fatalf("pin wiped by cert save: ServerPins=%v", sess.ServerPins)
	}
	if sess.CertPEM == "" {
		t.Fatal("cert missing after saveSession")
	}
}

// TestConnectVerifiesServerCertBeforeHandshake: wiring source-scan —
// the TOFU decision must run in connect() between the TLS dial and the
// first protocol message (rejecting BEFORE any mumble bytes are sent).
func TestConnectVerifiesServerCertBeforeHandshake(t *testing.T) {
	src, err := os.ReadFile("mumble.go")
	if err != nil {
		t.Fatalf("read source: %v", err)
	}
	s := string(src)
	dial := strings.Index(s, "tls.DialWithDialer(dialer, \"tcp\", hostPort, tlsCfg)")
	if dial < 0 {
		t.Fatal("dial marker missing")
	}
	// Search for the CALL after the dial — the first occurrence in the
	// whole file is the function DEFINITION (first version of this scan
	// matched it and false-failed, slice-286 self-caught).
	checkRel := strings.Index(s[dial:], "mumbleServerTOFU(")
	if checkRel < 0 {
		t.Fatal("TOFU call missing after dial")
	}
	check := dial + checkRel
	sendRel := strings.Index(s[check:], "tcpSend(mumbleMsgVersion, ver.marshal())")
	if sendRel < 0 {
		t.Fatal("first-send marker missing after TOFU call")
	}
	send := check + sendRel
	t.Logf("dial=%d check=%d send=%d", dial, check, send)
}

// newTestVaultSimple: a throwaway vault-backed session store.
func newTestVaultSimple(t *testing.T, dir string) *utils.Vault {
	t.Helper()
	v, err := utils.CreateVault(filepath.Join(dir, "v.vault"), "pw")
	if err != nil {
		t.Fatalf("CreateVault: %v", err)
	}
	t.Cleanup(func() { v.Close() })
	return v
}
