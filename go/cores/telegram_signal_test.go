package cores

import (
	"os"
	"strings"
	"testing"
)

// F-79 (slice 315): remote call-signaling payloads were parsed with the
// error DROPPED (9 sites across both signal clusters) — a corrupt
// payload fed ZERO-VALUES into the handlers (MediaState zeroing remote
// mute/rotation; empty structs handed to setup handlers) — and the
// signal PRINTFS indexed `setup.Fingerprints[0]` / `answerNC.
// Contents[0]` directly: a remote InitialSetup/NegotiateChannels with
// an EMPTY (or type-mismatched) fingerprints/contents array crashed the
// whole client with index-out-of-range. `answerNC` even echoes the
// REMOTE offer's contents, so an empty remote array panicked our
// answer path.
//
// Seam-RED (WORKLOG 315): undefined: unmarshalCallSignal /
// fingerprintLabel / firstSSRC.

func TestFingerprintLabelHandlesEmptySetup(t *testing.T) {
	// The panic regression test: reverting to setup.Fingerprints[0]
	// fails this test with index-out-of-range.
	if got := fingerprintLabel(tgInitialSetup{}); got != "none" {
		t.Fatalf("empty setup label = %q, want %q", got, "none")
	}
	withEntry := tgInitialSetup{
		Fingerprints: []tgDTLSFingerprint{{Setup: "active", Hash: "sha-256", Fingerprint: "AA:BB"}},
	}
	if got := fingerprintLabel(withEntry); got != "active" {
		t.Fatalf("label = %q, want %q", got, "active")
	}
}

func TestFirstSSRCHandlesEmptyContents(t *testing.T) {
	// Same panic regression class (7875: remote offer with no contents).
	if got := firstSSRC(nil); got != "" {
		t.Fatalf("empty contents ssrc = %q, want empty", got)
	}
	if got := firstSSRC([]tgMediaContent{{SSRC: "4242"}}); got != "4242" {
		t.Fatalf("ssrc = %q, want %q", got, "4242")
	}
}

func TestUnmarshalCallSignalSurfacesTypeMismatch(t *testing.T) {
	var setup tgInitialSetup
	// Valid JSON, wrong field TYPES — the exact payload shape that used
	// to be silently dropped into a zero struct.
	payload := []byte(`{"@type":"InitialSetup","fingerprints":"not-an-array"}`)
	err := unmarshalCallSignal(payload, &setup)
	if err == nil {
		t.Fatal("type-mismatched payload parsed as success — zero struct would reach the handlers")
	}
	if !strings.Contains(err.Error(), "call signal parse") {
		t.Fatalf("unexpected error: %v", err)
	}
	var good tgInitialSetup
	if err := unmarshalCallSignal([]byte(`{"ufrag":"u1","fingerprints":[{"setup":"active"}]}`), &good); err != nil {
		t.Fatalf("valid payload: %v", err)
	}
	if good.Ufrag != "u1" || len(good.Fingerprints) != 1 {
		t.Fatalf("parsed %#v", good)
	}
}

// TestBareCallSignalUnmarshalsGone: source-scan pin — every typed
// signal parse goes through unmarshalCallSignal (error surfaced, the
// caller skips handling); comments skipped, test files skipped.
func TestBareCallSignalUnmarshalsGone(t *testing.T) {
	srcB, err := os.ReadFile("telegram.go")
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
