package gui

import (
	"errors"
	"testing"

	"uniclient/cores"
)

func TestTwoFAMainActions(t *testing.T) {
	got := twofaMainActions(cores.CloudPasswordState{HasPassword: false})
	if len(got) != 1 || got[0] != twofaActSet {
		t.Errorf("unset: %v", got)
	}

	got = twofaMainActions(cores.CloudPasswordState{HasPassword: true})
	want := []string{twofaActChange, twofaActDisable, twofaActSetEmail}
	if len(got) != len(want) {
		t.Fatalf("set-norecovery: %v", got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("set-norecovery[%d] = %q, want %q", i, got[i], want[i])
		}
	}

	got = twofaMainActions(cores.CloudPasswordState{HasPassword: true, HasRecovery: true})
	if got[2] != twofaActChangeEmail {
		t.Errorf("set-recovery: %v", got)
	}

	got = twofaMainActions(cores.CloudPasswordState{
		HasPassword:             true,
		EmailUnconfirmedPattern: "ma*****@gmail.com",
	})
	if got[2] != twofaActConfirmEmail {
		t.Errorf("unconfirmed: %v", got)
	}
}

func TestTwoFAValidateNew(t *testing.T) {
	cases := []struct {
		name           string
		hasCur         bool
		cur, n1, n2    string
		wantErr        bool
		wantErrCurrent bool
	}{
		{"set fresh", false, "", "pass123", "pass123", false, false},
		{"change with current", true, "old", "newpass", "newpass", false, false},
		{"missing current", true, "", "newpass", "newpass", true, true},
		{"empty new", false, "", "", "", true, false},
		{"mismatch", false, "", "one", "two", true, false},
		{"short new", false, "", "a", "a", true, false},
		{"cur ignored when unset", false, "ignored", "pass123", "pass123", false, false},
	}
	for _, tc := range cases {
		err := twofaValidateNew(tc.hasCur, tc.cur, tc.n1, tc.n2)
		if tc.wantErr && err == nil {
			t.Errorf("%s: expected error", tc.name)
		}
		if !tc.wantErr && err != nil {
			t.Errorf("%s: unexpected error %v", tc.name, err)
		}
		if tc.wantErrCurrent && !errors.Is(err, errTwoFACurrentRequired) {
			t.Errorf("%s: want errTwoFACurrentRequired, got %v", tc.name, err)
		}
	}
}

func TestTwoFAEmailFlow(t *testing.T) {
	d := &twofaDlgState{step: twofaStepEmail}
	if !twofaGoToEmailCode(d) || d.step != twofaStepEmailCode {
		t.Errorf("email submit should advance to the code step")
	}
}

func TestTwoFAStateSummary(t *testing.T) {
	s := twofaStateSummary(cores.CloudPasswordState{})
	if s != "Off" {
		t.Errorf("empty state summary = %q, want Off", s)
	}
	s = twofaStateSummary(cores.CloudPasswordState{HasPassword: true, Hint: "pet"})
	if s != "On · hint: pet" {
		t.Errorf("hint summary = %q", s)
	}
	s = twofaStateSummary(cores.CloudPasswordState{HasPassword: true, HasRecovery: true})
	if s != "On · recovery email set" {
		t.Errorf("recovery summary = %q", s)
	}
}

func TestContentPaneDialogSurfaceTwoFA(t *testing.T) {
	f := frame{twofaDlg: &twofaDlgState{accountID: "a"}, settingsOpen: true}
	if got := contentDialogSurface(f); got != "twofa" {
		t.Errorf("twofa + settings: = %q, want twofa", got)
	}
	f = frame{twofaDlg: &twofaDlgState{accountID: "a"}, lockDlg: &lockDlgState{}}
	if got := contentDialogSurface(f); got != "lock" {
		t.Errorf("twofa + lock: = %q, want lock (security gate wins)", got)
	}
}

func TestTwoFARowValue(t *testing.T) {
	if got := twofaRowValue(cores.CloudPasswordState{}); got != "Off" {
		t.Errorf("off row value = %q", got)
	}
	if got := twofaRowValue(cores.CloudPasswordState{HasPassword: true}); got != "On" {
		t.Errorf("on row value = %q", got)
	}
}

func TestTwoFALooksLikeEmail(t *testing.T) {
	for _, good := range []string{"a@b.co", "user.name+tag@example.org"} {
		if !twofaLooksLikeEmail(good) {
			t.Errorf("%q should pass", good)
		}
	}
	for _, bad := range []string{"", "nodomain@", "@nodomain", "a@b", "a b@c.io", "a@b@c.io"} {
		if twofaLooksLikeEmail(bad) {
			t.Errorf("%q should fail", bad)
		}
	}
}
