package gui

import (
	"testing"

	"uniclient/engine"
)

// Right info panel (AyuGram parity §7): profile / members / shared-media
// surface. Tests lock the section gating and role badge mapping.

func TestPanelSectionsFor(t *testing.T) {
	cases := []struct {
		typ     int
		profile bool
		members bool
	}{
		{engine.ChatTypeDMVal, true, false},
		{engine.ChatTypeGroupVal, false, true},
		{engine.ChatTypeTopicVal, false, true},
		{engine.ChatTypeChanVal, false, true},
	}
	for _, c := range cases {
		p, m := panelSectionsFor(c.typ)
		if p != c.profile || m != c.members {
			t.Errorf("panelSectionsFor(%d) = %v,%v want %v,%v", c.typ, p, m, c.profile, c.members)
		}
	}
}

func TestRoleBadge(t *testing.T) {
	cases := []struct {
		role  string
		label string
	}{
		{"owner", "owner"},
		{"admin", "admin"},
		{"member", ""},
		{"restricted", "restricted"},
		{"banned", "banned"},
		{"", ""},
	}
	for _, c := range cases {
		if got := roleBadgeLabel(c.role); got != c.label {
			t.Errorf("roleBadgeLabel(%q) = %q, want %q", c.role, got, c.label)
		}
	}
	// Badged roles must map to a distinct color; unbaged roles to zero.
	if roleBadgeColor("owner") == (colorNRGBA{}) {
		t.Error("roleBadgeColor(owner) is zero")
	}
	if roleBadgeColor("member") != (colorNRGBA{}) {
		t.Error("roleBadgeColor(member) should be zero")
	}
}

func TestLastSeenLabel(t *testing.T) {
	cases := []struct {
		kind string
		want string
	}{
		{"online", "online"},
		{"recently", "last seen recently"},
		{"within_week", "last seen within a week"},
		{"within_month", "last seen within a month"},
		{"long_ago", "last seen a long time ago"},
		{"exact", "last seen"},
		{"", "offline"},
	}
	for _, c := range cases {
		if got := lastSeenLabel(c.kind); got != c.want {
			t.Errorf("lastSeenLabel(%q) = %q, want %q", c.kind, got, c.want)
		}
	}
}
