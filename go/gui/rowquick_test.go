package gui

// Chat-row hover quick actions (slice 89, AyuGram parity row 68): the
// mute and read-state toggles that appear on row hover.

import (
	"testing"

	"gioui.org/widget"

	"uniclient/engine"
)

func TestRowQuickMuteAction(t *testing.T) {
	muted := engine.ChatInfo{AccountID: "a", ChatID: "c", IsMuted: true}
	act := rowQuickMuteAction(muted)
	if act.kind != "unmute" || act.label != "Unmute chat" || act.done != "Unmuted" || act.icon != iconSocialNotif {
		t.Errorf("muted row: %+v", act)
	}
	live := engine.ChatInfo{AccountID: "a", ChatID: "c"}
	act = rowQuickMuteAction(live)
	if act.kind != "mute" || act.label != "Mute chat" || act.done != "Muted" || act.icon != iconSocialNotifOff {
		t.Errorf("unmuted row: %+v", act)
	}
}

func TestRowQuickReadAction(t *testing.T) {
	cases := []struct {
		name string
		c    engine.ChatInfo
		kind string
		icon *widget.Icon
	}{
		{"unread count", engine.ChatInfo{UnreadCount: 3}, "read", iconActionCheckCircle},
		{"unread mark", engine.ChatInfo{UnreadMark: true}, "read", iconActionCheckCircle},
		{"read row", engine.ChatInfo{}, "unread", iconContentMarkUnread},
	}
	for _, c := range cases {
		act := rowQuickReadAction(c.c)
		if act.kind != c.kind {
			t.Errorf("%s: kind = %q, want %q", c.name, act.kind, c.kind)
		}
		if act.icon != c.icon {
			t.Errorf("%s: icon mismatch", c.name)
		}
	}
	if act := rowQuickReadAction(engine.ChatInfo{UnreadCount: 3}); act.done != "Marked as read" {
		t.Errorf("read toast: %q", act.done)
	}
	if act := rowQuickReadAction(engine.ChatInfo{}); act.label != "Mark as unread" {
		t.Errorf("unread label: %q", act.label)
	}
}

func TestRowQuickPair(t *testing.T) {
	rowQuickBtns = nil
	p := rowQuickPair(0)
	if p == nil || len(rowQuickBtns) != 2 {
		t.Fatalf("pair(0) grew %d buttons", len(rowQuickBtns))
	}
	p2 := rowQuickPair(2)
	if p2 == nil || len(rowQuickBtns) != 6 {
		t.Fatalf("pair(2) grew %d buttons, want 6", len(rowQuickBtns))
	}
	// Distinct pointers per row.
	if p == p2 || &p[0] == &p2[0] {
		t.Error("rows must get distinct button pairs")
	}
	// Idempotent re-fetch.
	if rowQuickPair(2) == nil {
		t.Error("re-fetch must work")
	}
	rowQuickBtns = nil
}
