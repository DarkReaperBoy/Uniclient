package tests

import (
	"testing"
	. "uniclient/cores"

	"github.com/gotd/td/tg"
)

func TestPrivacyKeyFor(t *testing.T) {
	for _, key := range []string{
		"last_seen", "phone_number", "profile_photo", "calls", "p2p",
		"forwards", "group_invites", "voice_messages", "about", "birthday",
	} {
		if got := PrivacyKeyFor(key); got == nil {
			t.Errorf("PrivacyKeyFor(%q) = nil, want a key", key)
		}
	}
	if got := PrivacyKeyFor("nope"); got != nil {
		t.Errorf("PrivacyKeyFor(%q) = %v, want nil", "nope", got)
	}
}

func TestPrivacyScopeFromRules(t *testing.T) {
	cases := []struct {
		name  string
		rules []tg.PrivacyRuleClass
		want  string
	}{
		{"everybody", []tg.PrivacyRuleClass{&tg.PrivacyValueAllowAll{}}, "everybody"},
		{"contacts", []tg.PrivacyRuleClass{&tg.PrivacyValueAllowContacts{}, &tg.PrivacyValueDisallowAll{}}, "contacts"},
		{"close friends", []tg.PrivacyRuleClass{&tg.PrivacyValueAllowCloseFriends{}, &tg.PrivacyValueDisallowAll{}}, "close_friends"},
		{"nobody", []tg.PrivacyRuleClass{&tg.PrivacyValueDisallowAll{}}, "nobody"},
		{"nobody w/ user exceptions", []tg.PrivacyRuleClass{
			&tg.PrivacyValueAllowUsers{Users: []int64{1, 2}},
			&tg.PrivacyValueDisallowAll{},
		}, "nobody"},
		{"empty", nil, "nobody"},
		{"contacts w/ exceptions", []tg.PrivacyRuleClass{
			&tg.PrivacyValueAllowUsers{Users: []int64{9}},
			&tg.PrivacyValueAllowContacts{},
			&tg.PrivacyValueDisallowAll{},
		}, "contacts"},
		{"allow-all wins", []tg.PrivacyRuleClass{
			&tg.PrivacyValueAllowContacts{},
			&tg.PrivacyValueAllowAll{},
		}, "everybody"},
	}
	for _, tc := range cases {
		if got := PrivacyScopeFromRules(tc.rules); got != tc.want {
			t.Errorf("%s: scope = %q, want %q", tc.name, got, tc.want)
		}
	}
}

func TestPrivacyRulesForScope(t *testing.T) {
	for _, scope := range []string{"everybody", "contacts", "close_friends", "nobody"} {
		rules := PrivacyRulesForScope(scope)
		if len(rules) == 0 {
			t.Fatalf("scope %q: no rules", scope)
		}
		for _, r := range rules {
			if _, ok := r.(tg.InputPrivacyRuleClass); !ok {
				t.Errorf("scope %q: rule %T is not an InputPrivacyRuleClass", scope, r)
			}
		}
		var out []tg.PrivacyRuleClass
		for _, r := range rules {
			switch v := r.(type) {
			case *tg.InputPrivacyValueAllowAll:
				out = append(out, &tg.PrivacyValueAllowAll{})
			case *tg.InputPrivacyValueAllowContacts:
				out = append(out, &tg.PrivacyValueAllowContacts{})
			case *tg.InputPrivacyValueAllowCloseFriends:
				out = append(out, &tg.PrivacyValueAllowCloseFriends{})
			case *tg.InputPrivacyValueDisallowAll:
				out = append(out, &tg.PrivacyValueDisallowAll{})
			default:
				t.Fatalf("scope %q: unexpected rule %T", scope, v)
			}
		}
		if got := PrivacyScopeFromRules(out); got != scope {
			t.Errorf("round-trip %q = %q", scope, got)
		}
	}
}
