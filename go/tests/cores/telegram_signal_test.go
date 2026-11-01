package tests

import (
	"os"
	"strings"
	"testing"
	. "uniclient/cores"
)

func TestFingerprintLabelHandlesEmptySetup(t *testing.T) {
	if got := FingerprintLabel(TgInitialSetup{}); got != "none" {
		t.Fatalf("empty setup label = %q, want %q", got, "none")
	}
	withEntry := TgInitialSetup{
		Fingerprints: []TgDTLSFingerprint{{Setup: "active", Hash: "sha-256", Fingerprint: "AA:BB"}},
	}
	if got := FingerprintLabel(withEntry); got != "active" {
		t.Fatalf("label = %q, want %q", got, "active")
	}
}

func TestFirstSSRCHandlesEmptyContents(t *testing.T) {
	if got := FirstSSRC(nil); got != "" {
		t.Fatalf("empty contents ssrc = %q, want empty", got)
	}
	if got := FirstSSRC([]TgMediaContent{{SSRC: "4242"}}); got != "4242" {
		t.Fatalf("ssrc = %q, want %q", got, "4242")
	}
}

func TestUnmarshalCallSignalSurfacesTypeMismatch(t *testing.T) {
	var setup TgInitialSetup
	payload := []byte(`{"@type":"InitialSetup","fingerprints":"not-an-array"}`)
	err := UnmarshalCallSignal(payload, &setup)
	if err == nil {
		t.Fatal("type-mismatched payload parsed as success — zero struct would reach the handlers")
	}
	if !strings.Contains(err.Error(), "call signal parse") {
		t.Fatalf("unexpected error: %v", err)
	}
	var good TgInitialSetup
	if err := UnmarshalCallSignal([]byte(`{"ufrag":"u1","fingerprints":[{"setup":"active"}]}`), &good); err != nil {
		t.Fatalf("valid payload: %v", err)
	}
	if good.Ufrag != "u1" || len(good.Fingerprints) != 1 {
		t.Fatalf("parsed %#v", good)
	}
}

func TestBareCallSignalUnmarshalsGone(t *testing.T) {
	srcB, err := os.ReadFile("../../cores/telegram.go")
	if err != nil {
		t.Fatal(err)
	}
	src := string(srcB)
	for _, line := range strings.Split(src, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "//") {
			continue
		}
		if strings.Contains(line, "json.Unmarshal(decrypted,") || strings.Contains(line, "json.Unmarshal(plaintext,") {
			t.Errorf("bare signal parse (error dropped): %s", trimmed)
		}
	}
}
