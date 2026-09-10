package engine

import (
	"path/filepath"
	"testing"

	"uniclient/cores"
	"uniclient/utils"
)

// The XMPP login flow's optional XEP-0077 register step: after a failed
// normal sign-in the flow offers "create this account on the server?",
// maps the answer to the register flag, and forwards it into the auth
// config. Uses a real (unconnected) XMPPCore: its Authenticate fails on
// dial, which is exactly the failure path the register step follows.

func newXMPPFlowForTest(t *testing.T) *authFlow {
	t.Helper()
	dir := t.TempDir()
	vault, err := utils.CreateVault(filepath.Join(dir, "test.vault"), "test")
	if err != nil {
		t.Fatalf("CreateVault: %v", err)
	}
	t.Cleanup(func() { vault.Close() })
	store := utils.NewSessionStore(vault, "engine-auth-test")
	return &authFlow{
		collected: map[string]string{},
		core:      cores.NewXMPPCore(store),
	}
}

func TestBuildAuthConfigXMPPRegister(t *testing.T) {
	cfg := buildAuthConfig("xmpp", map[string]string{
		"jid": "alice@example.com", "password": "pw", "register": "true",
	})
	if cfg.Extra["register"] != "true" {
		t.Fatalf("register flag not forwarded: %v", cfg.Extra)
	}
	if cfg.Extra["jid"] != "alice@example.com" || cfg.Extra["password"] != "pw" {
		t.Fatalf("jid/password not forwarded: %v", cfg.Extra)
	}

	cfg = buildAuthConfig("xmpp", map[string]string{
		"jid": "alice@example.com", "password": "pw", "register": "false",
	})
	if cfg.Extra["register"] == "true" {
		t.Fatal("register must stay unset/false for plain logins")
	}
}

func TestParseYesNo(t *testing.T) {
	for _, y := range []string{"y", "Y", "yes", "YES", " 1", "true", "register", "CREATE"} {
		if got := parseYesNo(y); got != "true" {
			t.Fatalf("parseYesNo(%q) = %q, want true", y, got)
		}
	}
	for _, n := range []string{"", "n", "no", "0", "false", "maybe", "later"} {
		if got := parseYesNo(n); got != "false" {
			t.Fatalf("parseYesNo(%q) = %q, want false", n, got)
		}
	}
}

func TestAdvanceXMPPRegisterStep(t *testing.T) {
	flow := newXMPPFlowForTest(t)
	base := &AuthState{Platform: "xmpp"}

	// Step 1: JID → password prompt.
	st, err := advanceXMPP(flow, "uc-test@invalid.example", base)
	if err != nil {
		t.Fatalf("step1: %v", err)
	}
	if flow.collected["jid"] != "uc-test@invalid.example" {
		t.Fatalf("jid not collected: %v", flow.collected)
	}
	if st.FieldType != "password" || st.Label != "Password" {
		t.Fatalf("step1 state: %+v", st)
	}

	// Step 2: password → login attempt (fails: invalid host) → the
	// register offer must appear, not a terminal error.
	st, err = advanceXMPP(flow, "s3cret", base)
	if err != nil {
		t.Fatalf("step2 must not surface the dial error as terminal: %v", err)
	}
	if flow.collected["password"] != "s3cret" {
		t.Fatalf("password not collected: %v", flow.collected)
	}
	if st.State != AuthStateInput {
		t.Fatalf("step2 must stay an input state: %+v", st)
	}
	if want := "Create this account on the server? (y = register, empty = retry)"; st.Label != want {
		t.Fatalf("register offer label: %q", st.Label)
	}

	// Step 3: "y" → register=true, tryAuth runs with the flag (and
	// fails on the invalid host again — the state machine already did
	// its job).
	_, err = advanceXMPP(flow, "y", base)
	if err == nil {
		t.Fatal("expected the (dial) auth error to surface for an invalid host")
	}
	if flow.collected["register"] != "true" {
		t.Fatalf("register answer not collected: %v", flow.collected)
	}
}

func TestAdvanceXMPPStraightLogin(t *testing.T) {
	flow := newXMPPFlowForTest(t)
	base := &AuthState{Platform: "xmpp"}

	_, _ = advanceXMPP(flow, "uc2@invalid.example", base)
	st, err := advanceXMPP(flow, "pw2", base)
	if err != nil {
		t.Fatalf("step2: %v", err)
	}
	if st.Label != "Create this account on the server? (y = register, empty = retry)" {
		t.Fatalf("expected register offer: %+v", st)
	}
	// Retry without registering: empty answer → register=false, plain
	// login retried.
	_, err = advanceXMPP(flow, "", base)
	if err == nil {
		t.Fatal("expected dial error for invalid host on retry")
	}
	if flow.collected["register"] != "false" {
		t.Fatalf("empty answer must map to false: %v", flow.collected)
	}
}
