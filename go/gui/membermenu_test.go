package gui

import (
	"testing"

	"uniclient/engine"
)

func memberActions(labels []chatMenuAction) []string {
	var out []string
	for _, a := range labels {
		out = append(out, a.id)
	}
	return out
}

func TestMemberMenuGate(t *testing.T) {
	chat := engine.ChatInfo{ChatID: "g1", Type: engine.ChatTypeGroupVal}
	member := engine.MemberInfo{UserID: "7", Role: "member"}

	if items := memberMenuItems(member, chat, "", false); items != nil {
		t.Fatalf("non-admin chat must offer no member actions: %v", items)
	}
	chat.IsAdmin = true
	items := memberMenuItems(member, chat, "", false)
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
	chat.IsAdmin = false
	chat.IsCreator = true
	if items := memberMenuItems(member, chat, "", false); len(memberActions(items)) != 4 {
		t.Fatalf("creator actions = %v", memberActions(items))
	}
}

func TestMemberMenuRoles(t *testing.T) {
	chat := engine.ChatInfo{ChatID: "g1", IsAdmin: true}

	admin := engine.MemberInfo{UserID: "7", Role: "admin"}
	got := memberActions(memberMenuItems(admin, chat, "", false))
	if got[0] != "demote" {
		t.Fatalf("admin first action = %q, want demote", got[0])
	}

	banned := engine.MemberInfo{UserID: "7", Role: "banned"}
	got = memberActions(memberMenuItems(banned, chat, "", false))
	if len(got) != 1 || got[0] != "unban" {
		t.Fatalf("banned actions = %v, want [unban]", got)
	}

	restricted := engine.MemberInfo{UserID: "7", Role: "restricted"}
	got = memberActions(memberMenuItems(restricted, chat, "", false))
	for _, a := range got {
		if a == "promote" || a == "demote" || a == "unban" {
			t.Fatalf("restricted actions = %v", got)
		}
	}
}

func TestMemberMenuUntouchable(t *testing.T) {
	chat := engine.ChatInfo{ChatID: "g1", IsAdmin: true}

	owner := engine.MemberInfo{UserID: "7", Role: "owner"}
	if items := memberMenuItems(owner, chat, "", false); items != nil {
		t.Fatalf("owner actions must be empty: %v", memberActions(items))
	}
	self := engine.MemberInfo{UserID: "7", Role: "member"}
	if items := memberMenuItems(self, chat, "7", false); items != nil {
		t.Fatalf("self actions must be empty: %v", memberActions(items))
	}
}

func TestMemberMenuLabels(t *testing.T) {
	chat := engine.ChatInfo{ChatID: "g1", IsAdmin: true}
	member := engine.MemberInfo{UserID: "7", Role: "member"}
	for _, it := range memberMenuItems(member, chat, "", false) {
		if it.label == "" {
			t.Fatalf("action %q has no label", it.id)
		}
	}
}
