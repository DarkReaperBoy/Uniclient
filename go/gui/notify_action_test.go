package gui

import (
	"testing"

	"uniclient/engine"
)

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
