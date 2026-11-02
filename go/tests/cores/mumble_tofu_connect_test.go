package tests

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"net"
	"strings"
	"testing"
	"time"
	. "uniclient/cores"

	"uniclient/utils"
)

type tofuReadResult struct {
	n   int
	err error
}

func newTestTLSCert(t *testing.T) tls.Certificate {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("genkey: %v", err)
	}
	keyDER, err := x509.MarshalECPrivateKey(key)
	if err != nil {
		t.Fatalf("marshal key: %v", err)
	}
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER})
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "mumble-tofu-probe"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
		DNSNames:     nil,
		IPAddresses:  []net.IP{net.ParseIP("127.0.0.1")},
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
	return pair
}

func startTofuProbe(t *testing.T, cert tls.Certificate) (addr string, firstRead chan tofuReadResult) {
	t.Helper()
	ln, err := tls.Listen("tcp", "127.0.0.1:0", &tls.Config{Certificates: []tls.Certificate{cert}})
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	t.Cleanup(func() { ln.Close() })
	firstRead = make(chan tofuReadResult, 1)
	go func() {
		conn, err := ln.Accept()
		if err != nil {
			firstRead <- tofuReadResult{-1, err}
			return
		}
		defer conn.Close()
		tc := conn.(*tls.Conn)
		if err := tc.Handshake(); err != nil {
			firstRead <- tofuReadResult{-1, err}
			return
		}
		buf := make([]byte, 64)
		_ = tc.SetReadDeadline(time.Now().Add(5 * time.Second))
		n, err := tc.Read(buf)
		firstRead <- tofuReadResult{n, err}
		time.Sleep(300 * time.Millisecond)
	}()
	return ln.Addr().String(), firstRead
}

func fpOf(t *testing.T, cert tls.Certificate) string {
	t.Helper()
	leaf, err := x509.ParseCertificate(cert.Certificate[0])
	if err != nil {
		t.Fatalf("parse cert: %v", err)
	}
	return MumblePeerCertHash(leaf)
}

func TestConnectRefusesPinnedMismatchBeforeSending(t *testing.T) {
	cert := newTestTLSCert(t)
	addr, firstRead := startTofuProbe(t, cert)

	core := &MumbleCore{}
	if err := core.StoreServerPin(addr, "pre-seeded-wrong-fp"); err != nil {
		t.Fatalf("StoreServerPin: %v", err)
	}
	err := core.Authenticate(AuthConfig{Mode: AuthModeUser, Extra: map[string]string{"server": addr, "username": "alice"}})
	if err == nil || !strings.Contains(err.Error(), "changed since first use") {
		t.Fatalf("connect err = %v, want certificate-changed refusal", err)
	}
	if !strings.Contains(err.Error(), "UNICLIENT_MUMBLE_RESET_PIN") {
		t.Fatalf("refusal must document the reset path, got: %v", err)
	}
	select {
	case r := <-firstRead:
		if r.n > 0 {
			t.Fatalf("client sent %d mumble bytes BEFORE refusing", r.n)
		}
	case <-time.After(6 * time.Second):
		t.Fatal("probe never saw a client connection")
	}
}

func TestConnectProceedsOnMatchingPin(t *testing.T) {
	cert := newTestTLSCert(t)
	addr, firstRead := startTofuProbe(t, cert)

	core := &MumbleCore{}
	if err := core.StoreServerPin(addr, fpOf(t, cert)); err != nil {
		t.Fatalf("StoreServerPin: %v", err)
	}
	done := make(chan error, 1)
	go func() {
		done <- core.Authenticate(AuthConfig{Mode: AuthModeUser, Extra: map[string]string{"server": addr, "username": "alice"}})
	}()

	select {
	case r := <-firstRead:
		if r.n <= 0 {
			t.Fatalf("matching pin should PROCEED: probe read n=%d err=%v", r.n, r.err)
		}
	case <-time.After(6 * time.Second):
		t.Fatal("probe never saw the client's Version bytes")
	}
	if err := core.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}
	select {
	case <-done:
	case <-time.After(6 * time.Second):
		t.Fatal("connect did not return after close")
	}
}

func TestConnectResetEnvRepins(t *testing.T) {
	t.Setenv("UNICLIENT_MUMBLE_RESET_PIN", "1")
	cert := newTestTLSCert(t)
	addr, firstRead := startTofuProbe(t, cert)

	store := utils.NewSessionStore(newTestVaultSimple(t, t.TempDir()), "dc-mumble")
	core := &MumbleCore{Session: store}
	if err := core.StoreServerPin(addr, "pre-seeded-wrong-fp"); err != nil {
		t.Fatalf("StoreServerPin: %v", err)
	}
	done := make(chan error, 1)
	go func() {
		done <- core.Authenticate(AuthConfig{Mode: AuthModeUser, Extra: map[string]string{"server": addr, "username": "alice"}})
	}()

	select {
	case r := <-firstRead:
		if r.n <= 0 {
			t.Fatalf("reset env should PROCEED: probe read n=%d err=%v", r.n, r.err)
		}
	case <-time.After(6 * time.Second):
		t.Fatal("probe never saw the client's Version bytes")
	}
	if err := core.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}
	select {
	case <-done:
	case <-time.After(6 * time.Second):
		t.Fatal("connect did not return after close")
	}
	var sess MumbleSessionData
	if err := store.Load(&sess); err != nil {
		t.Fatalf("load: %v", err)
	}
	if got := sess.ServerPins[addr]; got != fpOf(t, cert) {
		t.Fatalf("pin not re-pinned after reset: got %q, want %q", got, fpOf(t, cert))
	}
	if sess.CertPEM == "" {
		t.Fatal("generated client cert missing from session after close")
	}
}
