package gui

import (
	"testing"
)

// Reactions-notify settings (slice 61): the from-value coercion and the
// state struct's wiring contract.
func TestReactionsFromValue(t *testing.T) {
	if got := reactionsFromValue("contacts"); got != "contacts" {
		t.Errorf("contacts = %q", got)
	}
	if got := reactionsFromValue("everyone"); got != "everyone" {
		t.Errorf("everyone = %q", got)
	}
	if got := reactionsFromValue(nil); got != "everyone" {
		t.Errorf("nil = %q", got)
	}
	if got := reactionsFromValue(42); got != "everyone" {
		t.Errorf("number = %q", got)
	}
	if got := reactionsFromValue("Contacts"); got != "everyone" {
		t.Errorf("case-sensitive = %q", got)
	}
}

func TestNotifyAcctStateReactions(t *testing.T) {
	st := notifyAcctState{
		contact:   true,
		calls:     false,
		reactOn:   true,
		reactFrom: "contacts",
		pollsOn:   false,
		pollsFrom: "everyone",
	}
	if !st.reactOn || st.reactFrom != "contacts" || st.pollsOn || st.pollsFrom != "everyone" {
		t.Fatalf("state = %+v", st)
	}
	if !st.contact || st.calls {
		t.Fatalf("legacy fields broken: %+v", st)
	}
}
