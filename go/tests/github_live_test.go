//go:build live

// Live integration test for the GitHub core against the REAL GitHub API.
// Not run in CI and gitignored (go/tests/): needs a real PAT.
//
// Run: cd go && go test -tags goolm,live ./tests/ -run TestGitHubLive -v
// Env: GITHUB_LIVE_TOKEN (required)
package tests

import (
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

	// Auth already verified the token via the /user endpoint; fetch self
	// through the public Core surface too.
	self, err := core.GetProfile("")
	if err != nil {
		t.Fatalf("GetUser(self): %v", err)
	}
	t.Logf("authenticated as %s (%s)", self.Username, self.DisplayName)

	dialogs, err := core.GetDialogs(cores.PaginationOpts{Limit: 10})
	if err != nil {
		t.Logf("GetDialogs: %v (token may lack notifications scope — informational)", err)
	} else {
		t.Logf("GetDialogs: %d dialogs", len(dialogs))
		for i, d := range dialogs {
			if i >= 5 {
				break
			}
			t.Logf("  - %s (%s)", d.Title, d.ID)
		}
	}
}

// envToken reads the live-test token from the environment.
func envToken() string { return os.Getenv("GITHUB_LIVE_TOKEN") }

// osGetenv reads a variable from the environment.
func osGetenv(key string) string { return os.Getenv(key) }

// osGetenvDefault reads a variable or falls back to a default.
func osGetenvDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
