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

func TestFilterMembers(t *testing.T) {
	members := []engine.MemberInfo{
		{UserID: "1", DisplayName: "Alice", Username: "alice"},
		{UserID: "2", DisplayName: "Bob", Username: "bobby"},
		{UserID: "33", DisplayName: "Carol"},
	}
	if got := filterMembers(members, ""); len(got) != 3 {
		t.Errorf("empty query = %d, want 3", len(got))
	}
	if got := filterMembers(members, "bob"); len(got) != 1 || got[0].UserID != "2" {
		t.Errorf("username match = %+v", got)
	}
	if got := filterMembers(members, "ALICE"); len(got) != 1 {
		t.Errorf("case-insensitive = %+v", got)
	}
	if got := filterMembers(members, "3"); len(got) != 1 || got[0].UserID != "33" {
		t.Errorf("id match = %+v", got)
	}
	if got := filterMembers(members, "  "); len(got) != 3 {
		t.Errorf("whitespace query = %d, want 3", len(got))
	}
	if got := filterMembers(members, "zzz"); len(got) != 0 {
		t.Errorf("no match = %+v", got)
	}
}
