package tests

import (
	"path/filepath"
	"testing"
	. "uniclient/engine"

	"uniclient/cores"
	"uniclient/utils"
)

func newXMPPFlowForTest(t *testing.T) *AuthFlow {
	t.Helper()
	dir := t.TempDir()
	vault, err := utils.CreateVault(filepath.Join(dir, "test.vault"), "test")
	if err != nil {
		t.Fatalf("CreateVault: %v", err)
	}
	t.Cleanup(func() { vault.Close() })
	store := utils.NewSessionStore(vault, "engine-auth-test")
	return ForTestNewAuthFlow(cores.NewXMPPCore(store))
}

func TestBuildAuthConfigXMPPRegister(t *testing.T) {
	cfg := BuildAuthConfig("xmpp", map[string]string{
		"jid": "alice@example.com", "password": "pw", "register": "true",
	})
	if cfg.Extra["register"] != "true" {
		t.Fatalf("register flag not forwarded: %v", cfg.Extra)
	}
	if cfg.Extra["jid"] != "alice@example.com" || cfg.Extra["password"] != "pw" {
		t.Fatalf("jid/password not forwarded: %v", cfg.Extra)
	}

	cfg = BuildAuthConfig("xmpp", map[string]string{
		"jid": "alice@example.com", "password": "pw", "register": "false",
	})
	if cfg.Extra["register"] == "true" {
		t.Fatal("register must stay unset/false for plain logins")
	}
}

func TestParseYesNo(t *testing.T) {
	for _, y := range []string{"y", "Y", "yes", "YES", " 1", "true", "register", "CREATE"} {
		if got := ParseYesNo(y); got != "true" {
			t.Fatalf("parseYesNo(%q) = %q, want true", y, got)
		}
	}
	for _, n := range []string{"", "n", "no", "0", "false", "maybe", "later"} {
		if got := ParseYesNo(n); got != "false" {
			t.Fatalf("parseYesNo(%q) = %q, want false", n, got)
		}
	}
}

func TestAdvanceXMPPRegisterStep(t *testing.T) {
	flow := newXMPPFlowForTest(t)
	base := &AuthState{Platform: "xmpp"}

	st, err := AdvanceXMPP(flow, "uc-test@invalid.example", base)
	if err != nil {
		t.Fatalf("step1: %v", err)
	}
	if flow.ForTestCollected()["jid"] != "uc-test@invalid.example" {
		t.Fatalf("jid not collected: %v", flow.ForTestCollected())
	}
	if st.FieldType != "password" || st.Label != "Password" {
		t.Fatalf("step1 state: %+v", st)
	}

	st, err = AdvanceXMPP(flow, "s3cret", base)
	if err != nil {
		t.Fatalf("step2 must not surface the dial error as terminal: %v", err)
	}
	if flow.ForTestCollected()["password"] != "s3cret" {
		t.Fatalf("password not collected: %v", flow.ForTestCollected())
	}
	if st.State != AuthStateInput {
		t.Fatalf("step2 must stay an input state: %+v", st)
	}
	if want := "Create this account on the server? (y = register, empty = retry)"; st.Label != want {
		t.Fatalf("register offer label: %q", st.Label)
	}

	_, err = AdvanceXMPP(flow, "y", base)
	if err == nil {
		t.Fatal("expected the (dial) auth error to surface for an invalid host")
	}
	if flow.ForTestCollected()["register"] != "true" {
		t.Fatalf("register answer not collected: %v", flow.ForTestCollected())
	}
}

func TestAdvanceXMPPStraightLogin(t *testing.T) {
	flow := newXMPPFlowForTest(t)
	base := &AuthState{Platform: "xmpp"}

	_, _ = AdvanceXMPP(flow, "uc2@invalid.example", base)
	st, err := AdvanceXMPP(flow, "pw2", base)
	if err != nil {
		t.Fatalf("step2: %v", err)
	}
	if st.Label != "Create this account on the server? (y = register, empty = retry)" {
		t.Fatalf("expected register offer: %+v", st)
	}
	_, err = AdvanceXMPP(flow, "", base)
	if err == nil {
		t.Fatal("expected dial error for invalid host on retry")
	}
	if flow.ForTestCollected()["register"] != "false" {
		t.Fatalf("empty answer must map to false: %v", flow.ForTestCollected())
	}
}
