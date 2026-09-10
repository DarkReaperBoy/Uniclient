package gui

// "Seen by" read receipts (slice 98, matrix row 97): pure helpers — row
// naming from the engine's detailed participant map, the privacy-note
// mapping, the context-menu gate, and escTarget self-handling.

import (
	"testing"

	"uniclient/engine"
)

func TestSeenByRowName(t *testing.T) {
	cases := []struct {
		name  string
		entry map[string]interface{}
		want  string
	}{
		{"named", map[string]interface{}{"name": "Alice"}, "Alice"},
		{"id fallback", map[string]interface{}{"user_id": int64(42)}, "user 42"},
		{"nothing", map[string]interface{}{}, "someone"},
	}
	for _, tc := range cases {
		if got := seenByRowName(tc.entry); got != tc.want {
			t.Errorf("%s: seenByRowName(%v) = %q, want %q", tc.name, tc.entry, got, tc.want)
		}
	}
}

func TestSeenByPrivacyNote(t *testing.T) {
	cases := []struct {
		err  string
		want string
	}{
		{"privacy:my_hidden", "Your privacy settings hide read participants."},
		{"privacy:his_hidden", "Their privacy settings hide read participants."},
		{"privacy:too_old", "This message is too old to list readers."},
		{"something else", ""},
		{"", ""},
	}
	for _, tc := range cases {
		if got := seenByPrivacyNote(tc.err); got != tc.want {
			t.Errorf("seenByPrivacyNote(%q) = %q, want %q", tc.err, got, tc.want)
		}
	}
}

func TestSeenByMenuGate(t *testing.T) {
	cases := []struct {
		name     string
		m        engine.CachedMessage
		chatType int
		want     bool
	}{
		{"own dm message", engine.CachedMessage{MsgID: "1", IsOutgoing: true}, engine.ChatTypeDMVal, true},
		{"own group message", engine.CachedMessage{MsgID: "2", IsOutgoing: true}, engine.ChatTypeGroupVal, true},
		{"own channel post — no receipts", engine.CachedMessage{MsgID: "3", IsOutgoing: true}, engine.ChatTypeChanVal, false},
		{"incoming message", engine.CachedMessage{MsgID: "4"}, engine.ChatTypeDMVal, false},
		{"service row", engine.CachedMessage{MsgID: "5", IsOutgoing: true, IsService: true}, engine.ChatTypeDMVal, false},
	}
	for _, tc := range cases {
		if got := seenByMenuGate(tc.m, tc.chatType); got != tc.want {
			t.Errorf("%s: seenByMenuGate = %v, want %v", tc.name, got, tc.want)
		}
	}
}

func TestEscTargetSeenByDlgSelfHandled(t *testing.T) {
	f := frame{seenDlg: &seenDlgState{}, menu: &menuTarget{}}
	if got := escTarget(f); got != "" {
		t.Errorf("seenDlg + menu: escTarget = %q, want empty (dialog consumes Esc)", got)
	}
}

func TestMenuActionsSeenByItem(t *testing.T) {
	m := engine.CachedMessage{AccountID: "a", ChatID: "c", MsgID: "m1", IsOutgoing: true}
	a := &App{}
	f := frame{
		menu:  &menuTarget{msg: m},
		chats: []engine.ChatInfo{{AccountID: "a", ChatID: "c", Type: engine.ChatTypeGroupVal}},
	}
	found := false
	for _, it := range a.menuActionsFor(f, m) {
		if it.label == "Seen by" {
			found = true
		}
	}
	if !found {
		t.Errorf("menuActionsFor: \"Seen by\" missing for an own group message")
	}
	// Channel post → no item (Telegram gives no read receipts there).
	f.chats = []engine.ChatInfo{{AccountID: "a", ChatID: "c", Type: engine.ChatTypeChanVal}}
	for _, it := range a.menuActionsFor(f, m) {
		if it.label == "Seen by" {
			t.Error("\"Seen by\" present for a channel post")
		}
	}
}
