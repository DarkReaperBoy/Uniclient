package gui

import (
	"testing"

	"uniclient/engine"
)

func TestDeleteDialogTitleAndHint(t *testing.T) {
	if got := deleteDialogTitle(1); got != "Delete message?" {
		t.Errorf("single title = %q", got)
	}
	if got := deleteDialogTitle(3); got != "Delete 3 messages?" {
		t.Errorf("bulk title = %q", got)
	}
	if got := deleteDialogHint(true); got != "This can't be undone." {
		t.Errorf("revoke hint = %q", got)
	}
	if got := deleteDialogHint(false); got == "This can't be undone." {
		t.Errorf("no-revoke hint should differ")
	}
}

func TestCanRevokeForAll(t *testing.T) {
	chat := engine.ChatInfo{}
	in := engine.CachedMessage{IsOutgoing: false}
	out := engine.CachedMessage{IsOutgoing: true}
	if canRevokeForAll([]engine.CachedMessage{in}, chat) {
		t.Fatal("incoming only, no admin: no revoke")
	}
	if !canRevokeForAll([]engine.CachedMessage{out}, chat) {
		t.Fatal("outgoing: revoke")
	}
	if !canRevokeForAll([]engine.CachedMessage{in}, engine.ChatInfo{IsAdmin: true}) {
		t.Fatal("admin: revoke")
	}
	if !canRevokeForAll([]engine.CachedMessage{in}, engine.ChatInfo{IsCreator: true}) {
		t.Fatal("creator: revoke")
	}
	if !canRevokeForAll([]engine.CachedMessage{in, out}, chat) {
		t.Fatal("mixed with one outgoing: revoke")
	}
}

func TestCanReportAndMsgIDInt(t *testing.T) {
	if !canReport(engine.CachedMessage{IsOutgoing: false, IsService: false}) {
		t.Fatal("incoming non-service: reportable")
	}
	if canReport(engine.CachedMessage{IsOutgoing: true, IsService: false}) {
		t.Fatal("own message: not reportable")
	}
	if canReport(engine.CachedMessage{IsOutgoing: false, IsService: true}) {
		t.Fatal("service message: not reportable")
	}
	if got := msgIDInt("1234"); got != 1234 {
		t.Errorf("msgIDInt(1234) = %d", got)
	}
	if got := msgIDInt("abc"); got != 0 {
		t.Errorf("msgIDInt(abc) = %d, want 0", got)
	}
}

func TestChatOf(t *testing.T) {
	f := frame{chats: []engine.ChatInfo{
		{AccountID: "a", ChatID: "1", Title: "One"},
	}}
	m := engine.CachedMessage{AccountID: "a", ChatID: "1"}
	if got := chatOf(f, m); got.Title != "One" {
		t.Errorf("chatOf = %q, want One", got.Title)
	}
	m.ChatID = "9"
	if got := chatOf(f, m); got.Title != "" {
		t.Errorf("unknown chat should be zero value, got %q", got.Title)
	}
}
