package gui

// accountswitch_test.go — slice 147 (tests-first): Ctrl+Tab account
// cycling — the scope-cycle math and the shortcut mapping.

import (
	"testing"

	"gioui.org/io/key"

	"uniclient/engine"
)

func testAccounts() []engine.AccountInfo {
	return []engine.AccountInfo{
		{ID: "tg_a1", Platform: "telegram"},
		{ID: "xm_b2", Platform: "xmpp"},
		{ID: "irc_c3", Platform: "irc"},
	}
}

// TestAccountScopeCycle: the scope cycles through "all chats" and every
// account ID in list order, wrapping both directions.
func TestAccountScopeCycle(t *testing.T) {
	accs := testAccounts()

	cases := []struct {
		cur   string
		delta int
		want  string
	}{
		{"", 1, "tg_a1"},        // all → first account
		{"tg_a1", 1, "xm_b2"},   // forward
		{"irc_c3", 1, ""},       // last wraps to all
		{"", -1, "irc_c3"},      // backward from all wraps to last
		{"xm_b2", -1, "tg_a1"},  // backward
		{"tg_a1", -1, ""},       // backward to all
		{"unknown", 1, "tg_a1"}, // unknown scope → first account
		{"", 0, ""},             // no step
		{"tg_a1", 3, ""},        // multi-step wraps (a1→b2→c3→all)
		{"tg_a1", -3, "xm_b2"},  // -3 ≡ +1 (mod 4)
	}
	for _, c := range cases {
		if got := accountScopeCycle(accs, c.cur, c.delta); got != c.want {
			t.Errorf("accountScopeCycle(cur=%q, %d) = %q, want %q", c.cur, c.delta, got, c.want)
		}
	}
}

// TestAccountScopeCycleEmpty: no accounts → the scope never changes.
func TestAccountScopeCycleEmpty(t *testing.T) {
	if got := accountScopeCycle(nil, "whatever", 1); got != "whatever" {
		t.Fatalf("no accounts: got %q, want unchanged", got)
	}
}

// TestAccountSwitchStep: the key press → step mapping (Ctrl+Tab next,
// Ctrl+Shift+Tab previous, bare Tab none).
func TestAccountSwitchStep(t *testing.T) {
	cases := []struct {
		name  key.Name
		ctrl  bool
		shift bool
		want  int
	}{
		{key.NameTab, true, false, 1},
		{key.NameTab, true, true, -1},
		{key.NameTab, false, false, 0},
		{"A", true, false, 0},
	}
	for _, c := range cases {
		if got := accountSwitchStep(c.name, c.ctrl, c.shift); got != c.want {
			t.Errorf("accountSwitchStep(%v, ctrl=%v, shift=%v) = %d, want %d", c.name, c.ctrl, c.shift, got, c.want)
		}
	}
}
