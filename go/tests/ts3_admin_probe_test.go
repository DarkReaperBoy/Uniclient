//go:build live

package tests

import (
	"bufio"
	"fmt"
	"io"
	"math/rand"
	"net"
	"path/filepath"
	"strings"
	"testing"
	"time"

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
	rows, err := core.RawExec("channelcreate channel_name=szprobe" + suffix + " channel_flag_permanent=1")
	t.Logf("CLASSIFY channelcreate → err=%v rows=%v", err, rows)
	cid := ""
	for _, r := range rows {
		if v, ok := r["cid"]; ok {
			cid = v
		}
	}
	if cid == "" {
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

	if _, e := core.RawExec("channelsubscribeall"); e != nil {
		t.Logf("CLASSIFY channelsubscribeall → err=%v", e)
	} else {
		t.Logf("CLASSIFY channelsubscribeall → OK (nil)")
	}

	if _, e := core.RawExec("bandel banid=1"); e != nil {
		t.Logf("CLASSIFY bandel → err=%v", e)
	} else {
		t.Logf("CLASSIFY bandel → OK (nil)")
	}

	if banid := osGetenvDefault("TS3_PROBE_BANID", ""); banid != "" {
		if _, e := core.RawExec("bandel banid=" + banid); e != nil {
			t.Logf("CLASSIFY bandel(real) → err=%v", e)
		} else {
			t.Logf("CLASSIFY bandel(real) → OK (nil)")
		}
	} else {
		t.Logf("CLASSIFY bandel(real) → skipped (no TS3_PROBE_BANID)")
	}

	if wrows, werr := core.RawExec("whoami"); werr == nil && len(wrows) > 0 {
		t.Logf("CLASSIFY whoami rows: %v", wrows)
		dbid := wrows[0]["client_database_id"]
		if dbid == "" {
			for k, v := range wrows[0] {
				if strings.Contains(k, "database") || k == "clid" || strings.Contains(k, "dbid") {
					t.Logf("CLASSIFY whoami candidate %s=%s", k, v)
				}
			}
		}
		if _, e := core.RawExec("servergroupaddclient sgid=8 cldbid=" + dbid); e != nil {
			t.Logf("CLASSIFY servergroupaddclient(own dbid=%s) → err=%v", dbid, e)
		} else {
			t.Logf("CLASSIFY servergroupaddclient(own dbid=%s) → OK (nil)", dbid)
		}
	} else {
		t.Logf("CLASSIFY servergroupaddclient → whoami failed: %v", werr)
	}

	if sqpw := osGetenvDefault("TS3_SQ_PASSWORD", ""); sqpw != "" {
		if wrows, e := core.RawExec("whoami"); e == nil && len(wrows) > 0 {
			dbid := ""
			if rows, e2 := core.RawExec("clientinfo clid=" + wrows[0]["client_id"]); e2 == nil && len(rows) > 0 {
				dbid = rows[0]["client_database_id"]
			}
			if dbid != "" && dbid != "0" {
				if e := sqGrantServerAdmin(sqpw, dbid); e != nil {
					t.Logf("CLASSIFY sq grant failed: %v", e)
				} else {
					t.Logf("CLASSIFY sq grant OK (dbid=%s → sgid=3)", dbid)
				}
			} else {
				t.Logf("CLASSIFY sq grant skipped (dbid=%q)", dbid)
			}
		}
	}

	if sg := osGetenvDefault("TS3_PROBE_SGID", ""); sg != "" {
		if wrows, e := core.RawExec("whoami"); e == nil && len(wrows) > 0 {
			clid := wrows[0]["client_id"]
			dbid := ""
			if rows, e2 := core.RawExec("clientinfo clid=" + clid); e2 == nil && len(rows) > 0 {
				dbid = rows[0]["client_database_id"]
			}
			t.Logf("CLASSIFY setadmin chain: clid=%s dbid=%s sgid=%s", clid, dbid, sg)
			if _, e := core.RawExec("servergroupaddclient sgid=" + sg + " cldbid=" + clid); e != nil {
				t.Logf("CLASSIFY sgadd(cldbid=clid) → err=%v", e)
			} else {
				t.Logf("CLASSIFY sgadd(cldbid=clid) → OK (nil)")
			}
			if dbid != "" {
				if _, e := core.RawExec("servergroupaddclient sgid=" + sg + " cldbid=" + dbid); e != nil {
					t.Logf("CLASSIFY sgadd(cldbid=dbid) → err=%v", e)
				} else {
					t.Logf("CLASSIFY sgadd(cldbid=dbid) → OK (nil)")
				}
				if rows, e := core.RawExec("servergroupclientlist sgid=" + sg); e != nil {
					t.Logf("CLASSIFY sgcl(after add) → err=%v", e)
				} else {
					t.Logf("CLASSIFY sgcl(after add) rows=%v", rows)
				}
				if _, e := core.RawExec("servergroupdelclient sgid=" + sg + " cldbid=" + dbid); e != nil {
					t.Logf("CLASSIFY sgdel(dbid) → err=%v", e)
				} else {
					t.Logf("CLASSIFY sgdel(dbid) → OK (nil)")
				}
				if rows, e := core.RawExec("servergroupclientlist sgid=" + sg); e != nil {
					t.Logf("CLASSIFY sgcl(after del) → err=%v", e)
				} else {
					t.Logf("CLASSIFY sgcl(after del) rows=%v", rows)
				}
			}
		}
	}

	if rows, e := core.RawExec("banlist"); e != nil {
		t.Logf("CLASSIFY banlist → err=%v", e)
	} else {
		t.Logf("CLASSIFY banlist rows=%v", rows)
	}
	if rows, e := core.RawExec("servergroupclientlist sgid=4"); e != nil {
		t.Logf("CLASSIFY servergroupclientlist → err=%v", e)
	} else {
		t.Logf("CLASSIFY servergroupclientlist rows=%v", rows)
	}
	if wrows, e := core.RawExec("whoami"); e == nil && len(wrows) > 0 {
		clid := wrows[0]["client_id"]
		if rows, e2 := core.RawExec("clientinfo clid=" + clid); e2 != nil {
			t.Logf("CLASSIFY clientinfo → err=%v", e2)
		} else {
			t.Logf("CLASSIFY clientinfo(clid=%s) rows=%v", clid, rows)
		}
	}

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

func sqGrantServerAdmin(password, cldbid string) error {
	conn, err := net.DialTimeout("tcp", "127.0.0.1:10011", 5*time.Second)
	if err != nil {
		return err
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(8 * time.Second))
	reader := bufio.NewReader(io.MultiReader(conn))
	readline := func() (string, error) {
		line, err := reader.ReadString('\n')
		return strings.ReplaceAll(strings.ReplaceAll(line, "\r", ""), "\x00", ""), err
	}
	if _, err := readline(); err != nil {
		return err
	}
	if _, err := readline(); err != nil {
		return err
	}
	for _, c := range []string{
		"login serveradmin " + password,
		"use 0",
		"serverlist",
		"use 0",
		"servergroupaddclient sgid=3 cldbid=" + cldbid,
	} {
		if _, err := io.WriteString(conn, c+"\n"); err != nil {
			return err
		}
		for {
			line, err := readline()
			if err != nil {
				return err
			}
			if strings.HasPrefix(line, "error id=") {
				if !strings.HasPrefix(line, "error id=0 ") {
					return fmt.Errorf("%s: %s", c, strings.TrimSpace(line))
				}
				break
			}
		}
	}
	_, _ = io.WriteString(conn, "quit\n")
	return nil
}
