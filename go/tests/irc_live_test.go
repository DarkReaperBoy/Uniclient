//go:build live

// Live integration test for the IRC core against a REAL IRC network.
// Not run in CI and gitignored (go/tests/): depends on external network
// conditions and server policies (some networks block cloud IPs).
//
// Run: cd go && go test -tags goolm,live ./tests/ -run TestIRCLive -v -timeout 120s
// Env: IRC_LIVE_SERVER (default "irc.libera.chat:6697"), IRC_LIVE_NICK (default random)
package tests

import (
	"fmt"
	"math/rand"
	"testing"
	"time"

	"uniclient/cores"
	"uniclient/utils"
)

func TestIRCLiveConnect(t *testing.T) {
	server := osGetenvDefault("IRC_LIVE_SERVER", "irc.libera.chat:6697")
	nick := osGetenvDefault("IRC_LIVE_NICK", fmt.Sprintf("uc-test-%d", rand.Intn(100000)))

	dir := t.TempDir()
	vault, err := utils.CreateVault(dir+"/test.vault", "live-test")
	if err != nil {
		t.Fatalf("CreateVault: %v", err)
	}
	defer vault.Close()
	store := utils.NewSessionStore(vault, "irc-live")

	core := cores.NewIRCCore(store)
	defer core.Logout()

	cfg := cores.AuthConfig{
		Extra: map[string]string{
			"server": server,
			"nick":   nick,
			"tls":    "true",
		},
	}
	if err := core.Authenticate(cfg); err != nil {
		t.Fatalf("Authenticate against %s: %v", server, err)
	}
	t.Logf("connected to %s as %s", server, nick)

	// The 001 (welcome) must have arrived during Authenticate (the core
	// waits for registration); give the MOTD a moment to land too.
	time.Sleep(3 * time.Second)
	if motd := core.GetMOTD(); len(motd) > 0 {
		t.Logf("MOTD: %d lines (first: %.80s)", len(motd), motd[0])
	} else {
		t.Log("MOTD empty yet — requesting it explicitly")
		core.RequestMOTD()
		deadline := time.Now().Add(15 * time.Second)
		for time.Now().Before(deadline) {
			time.Sleep(500 * time.Millisecond)
			if len(core.GetMOTD()) > 0 {
				break
			}
		}
		if motd := core.GetMOTD(); len(motd) > 0 {
			t.Logf("MOTD after request: %d lines (first: %.80s)", len(motd), motd[0])
		} else {
			t.Fatal("no MOTD received within 15s — connection is not delivering numerics")
		}
	}

	if err := core.Logout(); err != nil {
		t.Fatalf("Logout: %v", err)
	}
	t.Log("IRC live round-trip PASSED")
}
