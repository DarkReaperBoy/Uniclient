//go:build live

package tests

// Temporary diagnostic (B-58 classification): do the remaining no-data
// commands SUCCEED silently (→ need proof wiring) or reply? Guest perms
// are pre-granted on the local server; failures print failed_permid
// (from the wire) for the next grant round.

import (
	"fmt"
	"math/rand"
	"path/filepath"
	"testing"

	"uniclient/cores"
	"uniclient/utils"
)

func TestTS3AdminSilentClassification(t *testing.T) {
	server := osGetenvDefault("TS3_LIVE_SERVER", "127.0.0.1:9987")
	dir := t.TempDir()
	vault, err := utils.CreateVault(filepath.Join(dir, "t.vault"), "live-test")
	if err != nil {
		t.Fatalf("vault: %v", err)
	}
	t.Cleanup(func() { vault.Close() })
	core := cores.NewTeamSpeakCore(utils.NewSessionStore(vault, "probe-admin"))
	defer core.Close()
	if err := core.Authenticate(cores.AuthConfig{Extra: map[string]string{
		"server_address": server,
		"nickname":       fmt.Sprintf("uc-adm-%d", rand.Intn(100000)),
	}}); err != nil {
		t.Skipf("handshake: %v", err)
	}

	suffix := fmt.Sprint(rand.Intn(100000))
	// 1. channelcreate — data row (grace) vs silent?
	rows, err := core.RawExec("channelcreate channel_name=szprobe" + suffix + " channel_flag_permanent=1")
	t.Logf("CLASSIFY channelcreate → err=%v rows=%v", err, rows)
	cid := ""
	for _, r := range rows {
		if v, ok := r["cid"]; ok {
			cid = v
		}
	}
	if cid == "" {
		// Fall back to the broadcast-filled cache (notifychannelcreated).
		for _, d := range func() []cores.Dialog {
			ds, _ := core.GetDialogs(cores.PaginationOpts{Limit: 100})
			return ds
		}() {
			if len(d.Title) >= 8 && d.Title[len(d.Title)-6:] == suffix {
				var c int
				if _, e := fmt.Sscanf(d.ID, "ch:%d", &c); e == nil {
					cid = fmt.Sprint(c)
				}
			}
		}
	}
	if cid != "" {
		if _, e := core.RawExec("channeledit cid=" + cid + " channel_name=szrenamed" + suffix); e != nil {
			t.Logf("CLASSIFY channeledit → err=%v", e)
		} else {
			t.Logf("CLASSIFY channeledit → OK (nil)")
		}
		if _, e := core.RawExec("channeladdperm cid=" + cid + " permid=11793 permvalue=1"); e != nil {
			t.Logf("CLASSIFY channeladdperm → err=%v", e)
		} else {
			t.Logf("CLASSIFY channeladdperm → OK (nil)")
			if _, e := core.RawExec("channeldelperm cid=" + cid + " permid=11793"); e != nil {
				t.Logf("CLASSIFY channeldelperm → err=%v", e)
			} else {
				t.Logf("CLASSIFY channeldelperm → OK (nil)")
			}
		}
		if _, e := core.RawExec("channeldelete cid=" + cid + " force=1"); e != nil {
			t.Logf("CLASSIFY channeldelete → err=%v", e)
		} else {
			t.Logf("CLASSIFY channeldelete → OK (nil)")
		}
	} else {
		t.Logf("CLASSIFY channelcreate → no cid; skipping edit/delete chain")
	}

	// 2. subscribe family (already known silent — pinned)
	if _, e := core.RawExec("channelsubscribeall"); e != nil {
		t.Logf("CLASSIFY channelsubscribeall → err=%v", e)
	} else {
		t.Logf("CLASSIFY channelsubscribeall → OK (nil)")
	}

	// 3. clientedit on SELF (needs own clid from whoami)
	prof, perr := core.GetProfile("")
	if perr == nil && prof != nil && prof.ID != "" {
		if _, e := core.RawExec("clientedit clid=" + prof.ID + " client_description=probe"); e != nil {
			t.Logf("CLASSIFY clientedit(self) → err=%v", e)
		} else {
			t.Logf("CLASSIFY clientedit(self) → OK (nil)")
		}
	} else {
		t.Logf("CLASSIFY clientedit(self) → own profile unavailable: %v", perr)
	}
}
