package tests

import (
	"fmt"
	"path/filepath"
	"testing"
	. "uniclient/engine"

	"uniclient/cores"
	"uniclient/utils"
)

func newAuthEngine(t *testing.T) *Engine {
	t.Helper()
	dir := t.TempDir()
	vault, err := utils.CreateVault(filepath.Join(dir, "test.vault"), "test")
	if err != nil {
		t.Fatalf("CreateVault: %v", err)
	}
	t.Cleanup(func() { vault.Close() })
	SetCoreFactory(func(platform, accountID string) (cores.Core, error) {
		if platform != "xmpp" {
			return nil, fmt.Errorf("test factory: unsupported platform %q", platform)
		}
		return cores.NewXMPPCore(utils.NewSessionStore(vault, "engine-auth-test")), nil
	})
	t.Cleanup(func() { SetCoreFactory(nil) })
	return New(nil, nil, nil)
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

func TestXMPPAuthJourneyRegisterOffer(t *testing.T) {
	e := newAuthEngine(t)
	if err := e.AttachAccount("xmpp-reg", "xmpp", nil); err != nil {
		t.Fatalf("attach: %v", err)
	}

	st, err := e.StartAuth("xmpp-reg")
	if err != nil {
		t.Fatalf("start auth: %v", err)
	}
	if st.State != AuthStateInput || st.FieldType != "text" || st.Label != "JID (user@server)" {
		t.Fatalf("initial state: %+v", st)
	}

	st, err = e.SubmitAuthInput("xmpp-reg", "uc-test@invalid.example")
	if err != nil {
		t.Fatalf("jid step: %v", err)
	}
	if st.State != AuthStateInput || st.FieldType != "password" || st.Label != "Password" {
		t.Fatalf("password step: %+v", st)
	}

	st, err = e.SubmitAuthInput("xmpp-reg", "s3cret")
	if err != nil {
		t.Fatalf("password step: %v", err)
	}
	if st.State != AuthStateInput {
		t.Fatalf("dial failure must stay an input state: %+v", st)
	}
	if want := "Create this account on the server? (y = register, empty = retry)"; st.Label != want {
		t.Fatalf("register offer label: %q", st.Label)
	}

	st, err = e.SubmitAuthInput("xmpp-reg", "y")
	if err != nil {
		t.Fatalf("register step must return a state, not an error: %v", err)
	}
	if st.State != AuthStateError || !st.Recoverable {
		t.Fatalf("dial failure must surface as a recoverable error state: %+v", st)
	}
}

func TestXMPPAuthJourneyStraightLoginRetry(t *testing.T) {
	e := newAuthEngine(t)
	if err := e.AttachAccount("xmpp-login", "xmpp", nil); err != nil {
		t.Fatalf("attach: %v", err)
	}

	if _, err := e.StartAuth("xmpp-login"); err != nil {
		t.Fatalf("start auth: %v", err)
	}
	st, err := e.SubmitAuthInput("xmpp-login", "uc2@invalid.example")
	if err != nil {
		t.Fatalf("jid step: %v", err)
	}
	if st.FieldType != "password" {
		t.Fatalf("password step: %+v", st)
	}

	st, err = e.SubmitAuthInput("xmpp-login", "pw2")
	if err != nil {
		t.Fatalf("password step: %v", err)
	}
	if want := "Create this account on the server? (y = register, empty = retry)"; st.Label != want {
		t.Fatalf("register offer label: %q", st.Label)
	}

	st, err = e.SubmitAuthInput("xmpp-login", "")
	if err != nil {
		t.Fatalf("retry step must return a state, not an error: %v", err)
	}
	if st.State != AuthStateError || !st.Recoverable {
		t.Fatalf("empty retry must surface the dial failure as a recoverable error state: %+v", st)
	}
}
