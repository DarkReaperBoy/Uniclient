package gui

// Member context menu (AyuGram parity slice 106): the profile panel's
// member rows gain AyuGram's admin menu — promote/demote, restrict, ban/
// unban, remove — gated on the chat's IsAdmin/IsCreator flags and the
// member's role (owners are untouchable, self has no actions). Every
// action dispatches a real engine member-admin call. Pure derivation
// locked here.

import (
	"testing"

	"uniclient/engine"
)

func memberActions(labels []chatMenuAction) []string {
	var out []string
	for _, a := range labels {
		out = append(out, a.action)
	}
	return out
}

func TestMemberMenuGate(t *testing.T) {
	chat := engine.ChatInfo{ChatID: "g1", Type: engine.ChatTypeGroupVal}
	member := engine.MemberInfo{UserID: "7", Role: "member"}

	// Non-admin viewer: no menu at all.
	if items := memberMenuItems(member, chat, ""); items != nil {
		t.Fatalf("non-admin chat must offer no member actions: %v", items)
	}
	// Admin: full set for a plain member.
	chat.IsAdmin = true
	items := memberMenuItems(member, chat, "")
	got := memberActions(items)
	want := []string{"promote", "restrict", "ban", "remove"}
	if len(got) != len(want) {
		t.Fatalf("member actions = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("member actions = %v, want %v", got, want)
		}
	}
	// Creator sees the same admin powers.
	chat.IsAdmin = false
	chat.IsCreator = true
	if items := memberMenuItems(member, chat, ""); len(memberActions(items)) != 4 {
		t.Fatalf("creator actions = %v", memberActions(items))
	}
}

func TestMemberMenuRoles(t *testing.T) {
	chat := engine.ChatInfo{ChatID: "g1", IsAdmin: true}

	// Admin member: demote instead of promote.
	admin := engine.MemberInfo{UserID: "7", Role: "admin"}
	got := memberActions(memberMenuItems(admin, chat, ""))
	if got[0] != "demote" {
		t.Fatalf("admin first action = %q, want demote", got[0])
	}

	// Banned member: only unban.
	banned := engine.MemberInfo{UserID: "7", Role: "banned"}
	got = memberActions(memberMenuItems(banned, chat, ""))
	if len(got) != 1 || got[0] != "unban" {
		t.Fatalf("banned actions = %v, want [unban]", got)
	}

	// Restricted: ban + remove (already restricted; unrestrict is a
	// rights-reset the engine's RestrictMemberWithRights covers — the
	// simple menu keeps restrict/ban/remove).
	restricted := engine.MemberInfo{UserID: "7", Role: "restricted"}
	got = memberActions(memberMenuItems(restricted, chat, ""))
	for _, a := range got {
		if a == "promote" || a == "demote" || a == "unban" {
			t.Fatalf("restricted actions = %v", got)
		}
	}
}

func TestMemberMenuUntouchable(t *testing.T) {
	chat := engine.ChatInfo{ChatID: "g1", IsAdmin: true}

	// The chat owner can never be demoted/banned/removed by the menu.
	owner := engine.MemberInfo{UserID: "7", Role: "owner"}
	if items := memberMenuItems(owner, chat, ""); items != nil {
		t.Fatalf("owner actions must be empty: %v", memberActions(items))
	}
	// Self has no self-service actions.
	self := engine.MemberInfo{UserID: "7", Role: "member"}
	if items := memberMenuItems(self, chat, "7"); items != nil {
		t.Fatalf("self actions must be empty: %v", memberActions(items))
	}
}

func TestMemberMenuLabels(t *testing.T) {
	chat := engine.ChatInfo{ChatID: "g1", IsAdmin: true}
	member := engine.MemberInfo{UserID: "7", Role: "member"}
	for _, it := range memberMenuItems(member, chat, "") {
		if it.label == "" {
			t.Fatalf("action %q has no label", it.action)
		}
	}
}
