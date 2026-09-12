package gui

import (
	"testing"
	"time"

	"uniclient/engine"
)

// Slowmode + write-restriction a.wid.composer gating (AyuGram parity slice 69):
// the a.wid.composer swaps to a restricted bar / countdown. Pure derivations.

func TestSlowmodeRemain(t *testing.T) {
	now := time.Unix(1_000_000, 0)
	c := engine.ChatInfo{}
	if d := slowmodeRemain(c, now); d != 0 {
		t.Fatalf("no slowmode: remain = %v, want 0", d)
	}
	c.SlowmodeSeconds = 30
	if d := slowmodeRemain(c, now); d != 0 {
		t.Fatalf("no pending send date: remain = %v, want 0", d)
	}
	c.SlowmodeNextSendDate = now.Add(12 * time.Second).Unix()
	if d := slowmodeRemain(c, now); d != 12*time.Second {
		t.Fatalf("remain = %v, want 12s", d)
	}
	// In the past → no wait.
	c.SlowmodeNextSendDate = now.Add(-5 * time.Second).Unix()
	if d := slowmodeRemain(c, now); d != 0 {
		t.Fatalf("expired: remain = %v, want 0", d)
	}
}

func TestSlowmodeLabel(t *testing.T) {
	cases := []struct {
		d    time.Duration
		want string
	}{
		{0, ""},
		{1 * time.Second, "Slow mode: 1s"},
		{12 * time.Second, "Slow mode: 12s"},
		{95 * time.Second, "Slow mode: 1m 35s"},
		{3630 * time.Second, "Slow mode: 1h 0m"},
	}
	for _, c := range cases {
		if got := slowmodeLabel(c.d); got != c.want {
			t.Errorf("slowmodeLabel(%v) = %q, want %q", c.d, got, c.want)
		}
	}
}

func TestComposerRestricted(t *testing.T) {
	c := engine.ChatInfo{}
	if on, _ := composerRestricted(c); on {
		t.Fatal("plain chat must not be restricted")
	}
	c.WriteRestrictionText = "Sorry, this group is not accessible."
	on, label := composerRestricted(c)
	if !on || label != "Sorry, this group is not accessible." {
		t.Fatalf("restriction text must be surfaced verbatim, got on=%v %q", on, label)
	}
	// Type set without a text: generic label.
	c = engine.ChatInfo{WriteRestrictionType: 1}
	on, label = composerRestricted(c)
	if !on || label != composerRestrictedDefault {
		t.Fatalf("typed restriction needs the generic label, got on=%v %q", on, label)
	}
	// Not-joined channels use the JOIN bar (slice 19), never the generic
	// restriction: gate must not fire for them.
	c = engine.ChatInfo{NotJoined: true, WriteRestrictionType: 1}
	if on, _ := composerRestricted(c); on {
		t.Fatal("not-joined preview chats must use the JOIN bar, not the restriction bar")
	}
}
