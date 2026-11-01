//go:build live

package tests

import (
	"errors"
	"os"
	"path/filepath"
	"testing"

	"uniclient/cores"
	"uniclient/utils"
)

func TestGitHubLiveAuthenticateAndFetch(t *testing.T) {
	token := envToken()
	if token == "" {
		t.Skip("GITHUB_LIVE_TOKEN not set — live test skipped")
	}

	dir := t.TempDir()
	vault, err := utils.CreateVault(filepath.Join(dir, "test.vault"), "live-test")
	if err != nil {
		t.Fatalf("CreateVault: %v", err)
	}
	defer vault.Close()
	store := utils.NewSessionStore(vault, "github-live")

	core := cores.NewGitHubCore(store)
	defer core.Logout()

	cfg := cores.AuthConfig{Extra: map[string]string{"token": token}}
	if err := core.Authenticate(cfg); err != nil {
		t.Fatalf("Authenticate against real GitHub API: %v", err)
	}

	self, err := core.GetProfile("")
	if err != nil {
		t.Fatalf("GetUser(self): %v", err)
	}
	t.Logf("authenticated as %s (%s)", self.Username, self.DisplayName)

	dialogs, err := core.GetDialogs(cores.PaginationOpts{Limit: 10})
	if err != nil {
		if errors.Is(err, cores.ErrPermission) {
			t.Skipf("GetDialogs not permitted for this token (notifications scope): %v", err)
		}
		t.Fatalf("GetDialogs: %v", err)
	}
	t.Logf("GetDialogs: %d dialogs", len(dialogs))
	for i, d := range dialogs {
		if i >= 5 {
			break
		}
		t.Logf("  - %s (%s)", d.Title, d.ID)
	}
}

func envToken() string { return os.Getenv("GITHUB_LIVE_TOKEN") }

func osGetenvDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
