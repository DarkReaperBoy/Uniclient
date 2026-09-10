package engine

import (
	"testing"
)

// ValidPrivacyScope accepts exactly the four known scopes (slice 62).
func TestValidPrivacyScope(t *testing.T) {
	for _, scope := range []string{"everybody", "contacts", "close_friends", "nobody"} {
		if !ValidPrivacyScope(scope) {
			t.Errorf("ValidPrivacyScope(%q) = false", scope)
		}
	}
	for _, scope := range []string{"", "all", "Contacts", "friends", "null"} {
		if ValidPrivacyScope(scope) {
			t.Errorf("ValidPrivacyScope(%q) = true", scope)
		}
	}
}

// PrivacyScopeKeys is the ordered, unique settings vocabulary (slice 62).
func TestPrivacyScopeKeys(t *testing.T) {
	seen := make(map[string]bool)
	for _, key := range PrivacyScopeKeys {
		if key == "" {
			t.Fatal("empty privacy key")
		}
		if seen[key] {
			t.Fatalf("duplicate privacy key %q", key)
		}
		seen[key] = true
	}
	if len(PrivacyScopeKeys) < 9 {
		t.Fatalf("PrivacyScopeKeys = %v", PrivacyScopeKeys)
	}
}
