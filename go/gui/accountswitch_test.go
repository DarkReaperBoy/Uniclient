package gui

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

func TestAccountScopeCycle(t *testing.T) {
	accs := testAccounts()

	cases := []struct {
		cur   string
		delta int
		want  string
	}{
		{"", 1, "tg_a1"},
		{"tg_a1", 1, "xm_b2"},
		{"irc_c3", 1, ""},
		{"", -1, "irc_c3"},
		{"xm_b2", -1, "tg_a1"},
		{"tg_a1", -1, ""},
		{"unknown", 1, "tg_a1"},
		{"", 0, ""},
		{"tg_a1", 3, ""},
		{"tg_a1", -3, "xm_b2"},
	}
	for _, c := range cases {
		if got := accountScopeCycle(accs, c.cur, c.delta); got != c.want {
			t.Errorf("accountScopeCycle(cur=%q, %d) = %q, want %q", c.cur, c.delta, got, c.want)
		}
	}
}

func TestAccountScopeCycleEmpty(t *testing.T) {
	if got := accountScopeCycle(nil, "whatever", 1); got != "whatever" {
		t.Fatalf("no accounts: got %q, want unchanged", got)
	}
}

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
