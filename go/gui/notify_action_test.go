package gui

// notify_action_test.go — slice 141 (tests-first): the pure halves of
// the interactive-notification work — the freedesktop action list, the
// banner-click → pendingOpen hop, and the banner icon URI.

import (
	"testing"

	"uniclient/engine"
)

// TestNotifyDefaultActions: the banner action list is a well-formed
// freedesktop pair list whose first entry is the reserved "default"
// action (the whole-body click on every major server).
func TestNotifyDefaultActions(t *testing.T) {
	if len(notifyDefaultActions) != 2 {
		t.Fatalf("actions = %v, want one (key,label) pair", notifyDefaultActions)
	}
	if notifyDefaultActions[0] != "default" {
		t.Fatalf("first action key = %q, want %q (reserved body click)",
			notifyDefaultActions[0], "default")
	}
	if notifyDefaultActions[1] == "" {
		t.Fatal("action label must not be empty")
	}
}

// TestNotifyOpenAction: the click handler raises nothing (no window in
// the zero App) but schedules the chat open through the GUI loop's
// pendingOpen hop, carrying the title.
func TestNotifyOpenAction(t *testing.T) {
	a := &App{}
	k := chatKey{AccountID: "acc1", ChatID: "chat9"}
	fn := notifyOpenAction(a, k, "Alice")
	if fn == nil {
		t.Fatal("notifyOpenAction returned nil")
	}
	fn("default")

	a.mu.Lock()
	defer a.mu.Unlock()
	if a.pendingOpen == nil {
		t.Fatal("banner click did not schedule pendingOpen")
	}
	if a.pendingOpen.AccountID != "acc1" || a.pendingOpen.ChatID != "chat9" {
		t.Fatalf("pendingOpen = %+v, want acc1/chat9", a.pendingOpen)
	}
	if a.pendingTitle != "Alice" {
		t.Fatalf("pendingTitle = %q, want %q", a.pendingTitle, "Alice")
	}
}

// TestNotifyOpenActionRepeat: two clicks reschedule (last wins) without
// deadlock — banners can be clicked more than once on some servers.
func TestNotifyOpenActionRepeat(t *testing.T) {
	a := &App{}
	fn := notifyOpenAction(a, chatKey{AccountID: "a", ChatID: "1"}, "One")
	fn("default")
	fn("default")
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.pendingOpen == nil || a.pendingOpen.ChatID != "1" {
		t.Fatalf("pendingOpen = %+v", a.pendingOpen)
	}
}

// TestNotifyIconURI: the banner icon is the chat avatar as a file URI
// (the freedesktop app_icon contract), empty when there is no avatar.
func TestNotifyIconURI(t *testing.T) {
	cases := []struct {
		chat engine.ChatInfo
		want string
	}{
		{engine.ChatInfo{AvatarPath: ""}, ""},
		{engine.ChatInfo{AvatarPath: "/home/z/avatars/12.png"}, "file:///home/z/avatars/12.png"},
	}
	for _, c := range cases {
		if got := notifyIconURI(c.chat); got != c.want {
			t.Errorf("notifyIconURI(%q) = %q, want %q", c.chat.AvatarPath, got, c.want)
		}
	}
}
