package gui

// Shadow ban GUI (slice 91, matrix row 240): row naming, header-menu
// presence, escTarget self-handling, and the context-menu gate (which
// messages offer the shadow-ban action and when).

import (
	"testing"

	"uniclient/engine"
)

func TestShadowBanRowName(t *testing.T) {
	cases := []struct {
		b    engine.ShadowBan
		want string
	}{
		{engine.ShadowBan{SenderName: "Alice"}, "Alice"},
		{engine.ShadowBan{SenderID: "u42"}, "user u42"},
		{engine.ShadowBan{}, "someone"},
	}
	for _, tc := range cases {
		if got := shadowBanRowName(tc.b); got != tc.want {
			t.Errorf("shadowBanRowName(%+v) = %q, want %q", tc.b, got, tc.want)
		}
	}
}

func TestHeaderMenuHasShadowBans(t *testing.T) {
	// Every chat type exposes the per-chat ban manager.
	for _, c := range []engine.ChatInfo{
		{AccountID: "a", ChatID: "u1", Type: engine.ChatTypeDMVal},
		{AccountID: "a", ChatID: "g1", Type: engine.ChatTypeGroupVal},
		{AccountID: "a", ChatID: "c1", Type: engine.ChatTypeChanVal},
	} {
		if !containsAction(headerMenuItems(c, false, false), "shadowbans") {
			t.Errorf("chat type %d: shadow-ban manager missing", c.Type)
		}
	}
}

func TestEscTargetShadowDlgSelfHandled(t *testing.T) {
	f := frame{shadowDlg: &shadowDlgState{}, menu: &menuTarget{}}
	if got := escTarget(f); got != "" {
		t.Errorf("shadowDlg + menu: escTarget = %q, want empty (dialog consumes Esc)", got)
	}
}

func TestShadowBanMenuGate(t *testing.T) {
	cases := []struct {
		name  string
		m     engine.CachedMessage
		known bool
		want  bool
	}{
		{"plain incoming", engine.CachedMessage{MsgID: "m1", SenderID: "u1"}, true, true},
		{"state unknown hides item", engine.CachedMessage{MsgID: "m1", SenderID: "u1"}, false, false},
		{"no sender", engine.CachedMessage{MsgID: "m2"}, true, false},
		{"own outgoing", engine.CachedMessage{MsgID: "m3", SenderID: "me", IsOutgoing: true}, true, false},
		{"service row", engine.CachedMessage{MsgID: "m4", SenderID: "u1", IsService: true}, true, false},
	}
	for _, tc := range cases {
		if got := shadowBanMenuGate(tc.m, tc.known); got != tc.want {
			t.Errorf("%s: gate = %v, want %v", tc.name, got, tc.want)
		}
	}
}
