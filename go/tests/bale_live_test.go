//go:build live

package tests

import (
	"path/filepath"
	"strings"
	"testing"
	"time"

	"uniclient/cores"
	"uniclient/utils"
)

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
	err = core.Authenticate(cores.AuthConfig{Phone: "1"})
	took := time.Since(start)

	if err == nil {
		t.Fatalf("Authenticate unexpectedly succeeded with an invalid phone (took %s)", took)
	}

	msg := err.Error()
	t.Logf("Authenticate failed as expected after %s: %v", took.Round(time.Millisecond), err)

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

	structured := strings.Contains(msg, "gRPC error") ||
		strings.Contains(msg, "grpc-message") ||
		strings.Contains(msg, "StartPhoneAuth")
	if !structured {
		t.Fatalf("expected a structured gRPC error from StartPhoneAuth, got: %v", err)
	}
}
