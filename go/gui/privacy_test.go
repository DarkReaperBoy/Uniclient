package gui

import (
	"testing"

	"uniclient/engine"
)

// privacyScopeLabel renders the four scopes (slice 62); unknown = dash.
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

// Every displayed row key must be a real engine key, and the row order must
// match the engine's key list order (slice 62).
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

// The picker's choices: three options without close friends, four with,
// nobody always last (slice 62).
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

// privacyKeyTitle resolves row labels for toasts (slice 62).
func TestPrivacyKeyTitle(t *testing.T) {
	if got := privacyKeyTitle("last_seen"); got != "Last seen & online" {
		t.Errorf("title = %q", got)
	}
	if got := privacyKeyTitle("unknown-key"); got != "unknown-key" {
		t.Errorf("fallback title = %q", got)
	}
}

// The dialog state carries the account + key it edits (slice 62).
func TestPrivacyDlgStateFields(t *testing.T) {
	st := &privacyDlgState{accountID: "a1", key: "calls"}
	if st.accountID != "a1" || st.key != "calls" {
		t.Fatalf("state = %+v", st)
	}
}
