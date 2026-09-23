package gui

import (
	"testing"
	"time"

	"uniclient/engine"
)

// Peer header status + badges (AyuGram parity slice 28).

func TestPresenceSubtitle(t *testing.T) {
	cases := []struct {
		p    *engine.CachedUser
		want string
		on   bool
	}{
		{nil, "", false},
		{&engine.CachedUser{IsOnline: true}, "online", true},
		{&engine.CachedUser{IsBot: true}, "bot", false},
		{&engine.CachedUser{LastSeenKind: "recently"}, "last seen recently", false},
		{&engine.CachedUser{LastSeenKind: "hidden"}, "last seen hidden", false},
		{&engine.CachedUser{IsBot: true, IsOnline: true}, "online", true},
	}
	for i, c := range cases {
		got, on := presenceSubtitle(c.p)
		if got != c.want || on != c.on {
			t.Errorf("case %d: presenceSubtitle = (%q,%v), want (%q,%v)", i, got, on, c.want, c.on)
		}
	}
}

func TestHeaderLastSeenExact(t *testing.T) {
	// Anchor to noon of TODAY so "90 minutes ago" can never cross
	// midnight: this suite must hold at every wall-clock time. It first
	// failed at 00:03 local when -90 min fell on the previous day and
	// production correctly rendered the date form — the test's
	// assumption was wrong, not the code (BUGS.md F-9).
	now := time.Now()
	noon := time.Date(now.Year(), now.Month(), now.Day(), 12, 0, 0, 0, now.Location())
	today := engine.CachedUser{LastSeenKind: "exact", LastSeen: noon.Add(-90 * time.Minute).UnixMilli()}
	got, _ := presenceSubtitle(&today)
	if got != "last seen at "+time.UnixMilli(today.LastSeen).Format("15:04") {
		t.Errorf("same-day exact = %q", got)
	}
	old := engine.CachedUser{LastSeenKind: "exact", LastSeen: noon.AddDate(0, 0, -3).UnixMilli()}
	got, _ = presenceSubtitle(&old)
	if got != "last seen on "+time.UnixMilli(old.LastSeen).Format("Jan 2") {
		t.Errorf("older exact = %q", got)
	}
}

func TestHeaderBadges(t *testing.T) {
	var c engine.ChatInfo
	if got := headerBadges(c); len(got) != 0 {
		t.Errorf("no flags = %v, want none", got)
	}
	c.IsVerified = true
	c.IsPremium = true
	got := headerBadges(c)
	if len(got) != 2 || got[0].label != "verified" || got[1].label != "premium" {
		t.Errorf("verified+premium = %v", got)
	}
	if got[0].col != badgeVerifiedCol || got[1].col != badgePremiumCol {
		t.Errorf("badge colors wrong: %v %v", got[0].col, got[1].col)
	}
	c.IsScam = true
	c.IsFake = true
	got = headerBadges(c)
	if len(got) != 3 || got[2].label != "scam" {
		t.Errorf("scam overrides fake: %v", got)
	}
	c.IsScam = false
	got = headerBadges(c)
	if len(got) != 3 || got[2].label != "fake" || got[2].col != badgeFakeCol {
		t.Errorf("fake badge: %v", got)
	}
	for _, b := range got {
		if b.icon == nil {
			t.Errorf("badge %q has no icon", b.label)
		}
	}
}

func TestSameCalendarDay(t *testing.T) {
	// Noon-anchored (not time.Now()): the -1h case must stay on the same
	// calendar day at every wall-clock time (BUGS.md F-9).
	now := time.Now()
	n := time.Date(now.Year(), now.Month(), now.Day(), 12, 0, 0, 0, now.Location())
	if !sameCalendarDay(n, n.Add(-time.Hour)) {
		t.Error("same day rejected")
	}
	if sameCalendarDay(n, n.AddDate(0, 0, 1)) {
		t.Error("next day accepted")
	}
}
