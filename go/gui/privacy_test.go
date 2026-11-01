package gui

import (
	"testing"

	"uniclient/engine"
)

func TestPrivacyScopeLabel(t *testing.T) {
	cases := map[string]string{
		"everybody":     "Everybody",
		"contacts":      "My contacts",
		"close_friends": "Close friends",
		"nobody":        "Nobody",
		"":              "—",
		"weird":         "—",
	}
	for scope, want := range cases {
		if got := privacyScopeLabel(scope); got != want {
			t.Errorf("privacyScopeLabel(%q) = %q, want %q", scope, got, want)
		}
	}
}

func TestPrivacyKeyLabelsCoverEngineKeys(t *testing.T) {
	if len(privacyKeyLabels) != len(engine.PrivacyScopeKeys) {
		t.Fatalf("labels = %d, engine keys = %d", len(privacyKeyLabels), len(engine.PrivacyScopeKeys))
	}
	for i, r := range privacyKeyLabels {
		if r.key != engine.PrivacyScopeKeys[i] {
			t.Errorf("row %d = %q, engine key %q", i, r.key, engine.PrivacyScopeKeys[i])
		}
		if r.label == "" {
			t.Errorf("row %d has empty label", i)
		}
	}
}

func TestPrivacyScopeChoices(t *testing.T) {
	basic := privacyScopeChoices("phone_number")
	if len(basic) != 3 {
		t.Fatalf("phone_number choices = %v", basic)
	}
	if basic[len(basic)-1] != "nobody" {
		t.Fatalf("nobody not last: %v", basic)
	}
	cf := privacyScopeChoices("last_seen")
	if len(cf) != 4 || cf[2] != "close_friends" || cf[3] != "nobody" {
		t.Fatalf("last_seen choices = %v", cf)
	}
	if !engine.PrivacyScopeCloseFriends("voice_messages") {
		t.Fatal("voice_messages should offer close friends")
	}
	if engine.PrivacyScopeCloseFriends("p2p") {
		t.Fatal("p2p should not offer close friends")
	}
}

func TestPrivacyKeyTitle(t *testing.T) {
	if got := privacyKeyTitle("last_seen"); got != "Last seen & online" {
		t.Errorf("title = %q", got)
	}
	if got := privacyKeyTitle("unknown-key"); got != "unknown-key" {
		t.Errorf("fallback title = %q", got)
	}
}

func TestPrivacyDlgStateFields(t *testing.T) {
	st := &privacyDlgState{accountID: "a1", key: "calls"}
	if st.accountID != "a1" || st.key != "calls" {
		t.Fatalf("state = %+v", st)
	}
}
