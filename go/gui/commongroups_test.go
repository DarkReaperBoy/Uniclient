package gui

// Groups in common (AyuGram parity slice 107): the DM profile panel gains
// the shared-groups section — engine.GetCommonChats, rows with member
// counts, tap opens the chat. Honest empty state (section hidden when
// none). Pure derivations locked here.

import (
	"testing"

	"uniclient/cores"
	"uniclient/engine"
)

func TestCommonGroupsGate(t *testing.T) {
	dm := engine.ChatInfo{Type: engine.ChatTypeDMVal, ChatID: "7"}
	group := engine.ChatInfo{Type: engine.ChatTypeGroupVal, ChatID: "7"}
	if !commonGroupsGate(dm) {
		t.Fatal("DM profiles must show the common-groups section")
	}
	if commonGroupsGate(group) {
		t.Fatal("group profiles must not show the common-groups section")
	}
}

func TestCommonGroupRows(t *testing.T) {
	ds := []cores.Dialog{
		{ID: "10", Title: "Study Group", MemberCount: 24},
		{ID: "11", MemberCount: 3},
		{ID: "12", Title: "Sole"},
	}
	rows := commonGroupRows(ds)
	if len(rows) != 3 {
		t.Fatalf("rows = %d", len(rows))
	}
	if rows[0].title != "Study Group" || rows[0].sub != "24 members" {
		t.Fatalf("row0 = %+v", rows[0])
	}
	if rows[1].title != "Group" {
		t.Fatalf("title fallback = %q, want Group", rows[1].title)
	}
	if rows[2].sub != "" {
		t.Fatalf("zero members → no sub line, got %q", rows[2].sub)
	}
	if rows[0].sub != "24 members" {
		t.Fatalf("sub = %q", rows[0].sub)
	}
}

func TestCommonGroupMemberLabel(t *testing.T) {
	if s := commonMemberLabel(1); s != "1 member" {
		t.Fatalf("one = %q", s)
	}
	if s := commonMemberLabel(5); s != "5 members" {
		t.Fatalf("many = %q", s)
	}
	if s := commonMemberLabel(0); s != "" {
		t.Fatalf("zero = %q, want empty", s)
	}
}
