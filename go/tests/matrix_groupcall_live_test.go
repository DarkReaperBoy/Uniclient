//go:build live

// Live proof for B-6 → F-62: MSC3401 Tier-1 full-mesh group calls
// against a REAL Matrix homeserver (self-hosted dendrite), two real
// accounts, real sync — not the in-process loopback harness of slice
// 298. The chain proven end to end: room + invite → both join the
// conf (adoption, not fork) → cross-synced m.call.member state →
// conf-tagged room-event offer/answer/candidates → ICE on the real
// network → SendVoiceFrame reaches the other core's OnVoiceFrame with
// sender attribution and byte-exact payload.
//
// Provision (once per host — dendrite is pure Go, no docker):
//
//	GOBIN=$HOME/go/bin go install github.com/matrix-org/dendrite/cmd/dendrite@v0.13.8
//	GOBIN=$HOME/go/bin go install github.com/matrix-org/dendrite/cmd/generate-config@v0.13.8
//	GOBIN=$HOME/go/bin go install github.com/matrix-org/dendrite/cmd/generate-keys@v0.13.8
//	D=$HOME/.cache/uniclient-dendrite
//	generate-config -ci -dir $D/ > $D/dendrite.yaml
//	generate-keys -private-key $D/matrix_key.pem
//	dendrite -config $D/dendrite.yaml -http-bind-address 127.0.0.1:8008 \
//	  -really-enable-open-registration &
//
// Run:
//
//	cd go && MATRIX_DENDRITE_URL=http://127.0.0.1:8008 \
//	  go test -tags goolm,live ./tests/ -run TestMatrixGroupCallLive \
//	  -v -timeout 180s
//
// Env-gated (MATRIX_DENDRITE_URL) like every other live rung: never in
// CI, never needs secrets in the repo.
package tests

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"uniclient/cores"
	"uniclient/utils"
)

// ensureMatrixUser registers user@server via the m.login.dummy flow;
// an existing user (M_USER_EXISTS) is fine — the core logs in itself.
func ensureMatrixUser(t *testing.T, hs, user, password string) {
	t.Helper()
	body := fmt.Sprintf(`{"username":%q,"password":%q,"auth":{"type":"m.login.dummy"}}`, user, password)
	resp, err := http.Post(hs+"/_matrix/client/v3/register", "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatalf("register %s: %v", user, err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode == http.StatusOK {
		return
	}
	if strings.Contains(string(raw), "M_USER_EXISTS") || strings.Contains(string(raw), "M_USER_IN_USE") {
		return // idempotent: user already registered from a previous run
	}
	t.Fatalf("register %s: HTTP %d: %s", user, resp.StatusCode, string(raw))
}

// poll polls until cond is true or the deadline passes.
func poll(t *testing.T, what string, timeout time.Duration, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(250 * time.Millisecond)
	}
	t.Fatalf("timed out after %s waiting for %s", timeout, what)
}

// TestMatrixGroupCallLive: two real accounts on a self-hosted
// dendrite; see the file header for provisioning.
func TestMatrixGroupCallLive(t *testing.T) {
	hs := os.Getenv("MATRIX_DENDRITE_URL")
	if hs == "" {
		t.Skip("MATRIX_DENDRITE_URL not set — live matrix group-call test skipped")
	}
	hs = strings.TrimRight(hs, "/")

	ensureMatrixUser(t, hs, "b6alice", "b6alicepass123")
	ensureMatrixUser(t, hs, "b6bob", "b6bobpass123")

	newCore := func(name string) *cores.MatrixCore {
		t.Helper()
		dir := t.TempDir()
		vault, err := utils.CreateVault(filepath.Join(dir, "test.vault"), "live-test")
		if err != nil {
			t.Fatalf("CreateVault: %v", err)
		}
		t.Cleanup(func() { vault.Close() })
		store := utils.NewSessionStore(vault, name)
		core := cores.NewMatrixCore(store)
		t.Cleanup(func() { _ = core.Logout() })
		return core
	}
	alice := newCore("m-live-alice")
	bob := newCore("m-live-bob")

	for _, c := range []struct {
		name string
		core *cores.MatrixCore
	}{
		{"alice", alice},
		{"bob", bob},
	} {
		user := "b6" + c.name
		err := c.core.Authenticate(cores.AuthConfig{
			Phone:      user,
			Password2F: user + "pass123",
			Extra:      map[string]string{"homeserver": hs},
		})
		if err != nil {
			t.Fatalf("Authenticate %s: %v", c.name, err)
		}
	}
	t.Log("both accounts authenticated; sync running")

	// Room: alice creates + invites bob.
	aliceID, bobID := "@b6alice:localhost", "@b6bob:localhost"
	if strings.Contains(hs, "//") {
		// server_name is `localhost` in the generated config regardless
		// of the URL's port — keep the IDs fixed to that.
	}
	_ = aliceID
	_ = bobID
	dlg, err := alice.CreateGroup("b6 live call", []string{"@b6bob:localhost"})
	if err != nil {
		t.Fatalf("CreateGroup: %v", err)
	}
	roomID := dlg.ID
	if roomID == "" {
		t.Fatal("CreateGroup returned empty room id")
	}
	t.Logf("room: %s", roomID)

	// Bob joins (invited).
	poll(t, "bob joins the room", 20*time.Second, func() bool {
		return bob.JoinRoom(roomID) == nil
	})
	t.Log("bob joined")

	// Both join the conf — bob must ADOPT alice's conf, not fork one.
	csA, err := alice.JoinGroupCall(roomID)
	if err != nil {
		t.Fatalf("alice JoinGroupCall: %v", err)
	}
	csB, err := bob.JoinGroupCall(roomID)
	if err != nil {
		t.Fatalf("bob JoinGroupCall: %v", err)
	}
	if csA.ID != csB.ID {
		t.Fatalf("conf fork: alice=%s bob=%s (adoption failed)", csA.ID, csB.ID)
	}
	if !csA.IsGroup || csA.State != cores.CallStateActive {
		t.Fatalf("session = %+v", csA)
	}
	t.Logf("shared conf: %s", csA.ID)

	// Membership cross-syncs: BOTH sides must see two live participants
	// (each side's m.call.member state event reached the other via
	// real sync) — this is what drives reconcileGroupMesh. The closure
	// logs per-side state every ~5s so a timeout is diagnosable from
	// the test output alone (slice 304: three consecutive opaque
	// 30s timeouts).
	var logged bool
	var lastDiag time.Time
	poll(t, "both sides see 2 live participants", 30*time.Second, func() bool {
		ok := true
		if !logged || time.Since(lastDiag) >= 5*time.Second {
			for name, c := range map[string]*cores.MatrixCore{"alice": alice, "bob": bob} {
				info, err := c.GetGroupCall(roomID)
				if err != nil {
					t.Logf("diag[%s]: GetGroupCall err=%v", name, err)
				} else if info == nil {
					t.Logf("diag[%s]: no active call (not joined?)", name)
				} else {
					t.Logf("diag[%s]: count=%q participants=%+v", name, info.Meta["participants_count"], info.Participants)
				}
			}
			lastDiag = time.Now()
			logged = true
		}
		for _, c := range []*cores.MatrixCore{alice, bob} {
			info, err := c.GetGroupCall(roomID)
			if err != nil || info == nil || info.Meta["participants_count"] != "2" {
				ok = false
			}
		}
		return ok
	})
	t.Log("membership cross-synced: 2 participants on both sides")

	// Audio over the real mesh: B receives A's frame, sender-attributed.
	received := make(chan struct {
		sender string
		opus   []byte
	}, 16)
	bob.OnVoiceFrame(func(sender string, opus []byte) {
		received <- struct {
			sender string
			opus   []byte
		}{sender, append([]byte{}, opus...)}
	})

	frame := []byte{0xf8, 0xff, 0xfe, 0x42, 0x99, 0x01}
	deadline := time.Now().Add(30 * time.Second)
	got := false
	for time.Now().Before(deadline) && !got {
		_ = alice.SendVoiceFrame(frame)
		select {
		case r := <-received:
			if r.sender == "@b6alice:localhost" && bytes.Equal(r.opus, frame) {
				got = true
			} else if r.sender != "@b6alice:localhost" {
				t.Errorf("sender attribution wrong: %q", r.sender)
			} else {
				t.Errorf("payload mismatch: %x vs %x", r.opus, frame)
			}
		case <-time.After(250 * time.Millisecond):
		}
	}
	if !got {
		t.Fatal("no audio crossed the real homeserver-negotiated mesh")
	}
	t.Logf("VOICE PROVEN across the real mesh: %q → %d bytes", "@b6alice:localhost", len(frame))
}

var _ = json.Marshal
