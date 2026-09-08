package gui

import (
	"testing"

	"gioui.org/io/key"

	"uniclient/engine"
)

func escFrame() frame {
	return frame{
		chats: []engine.ChatInfo{
			{AccountID: "a", ChatID: "1", Title: "one"},
			{AccountID: "a", ChatID: "2", Title: "two"},
			{AccountID: "b", ChatID: "3", Title: "three"},
		},
	}
}

func TestEscTargetOrder(t *testing.T) {
	// Each layer closes before the ones below it.
	set := func(f frame, target string) frame {
		switch target {
		case "delDlg":
			f.delDlg = &delDlgState{}
		case "viewer":
			f.viewer = &viewerState{}
		case "drawer":
			f.drawerOpen = true
		case "settings":
			f.settingsOpen = true
		case "menu":
			f.menu = &menuTarget{}
		case "headerMenu":
			f.headerMenu = &headerMenuTarget{}
		case "chatMenu":
			f.chatMenu = &chatMenuTarget{}
		case "attach":
			f.attachMenuOpen = true
		case "emoji":
			f.emojiOpen = true
		case "selection":
			f.selOn = true
		case "inChatSearch":
			f.inSearch = true
		case "panel":
			f.panelOpen = true
		case "search":
			f.search = "query"
		}
		return f
	}

	layers := []string{"menu", "headerMenu", "chatMenu", "attach", "emoji", "selection", "inChatSearch", "panel", "search"}
	for _, top := range layers {
		f := escFrame()
		f = set(f, top)
		if got := escTarget(f); got != top {
			t.Errorf("only %s on: escTarget = %q, want %q", top, got, top)
		}
	}

	// Self-handled surfaces suppress the global layer entirely.
	f := escFrame()
	f = set(f, "menu")
	f = set(f, "drawer")
	if got := escTarget(f); got != "" {
		t.Errorf("drawer + menu: escTarget = %q, want empty (drawer consumes Esc)", got)
	}

	// Nothing open → no target.
	if got := escTarget(escFrame()); got != "" {
		t.Errorf("bare frame: escTarget = %q, want empty", got)
	}
}

func TestEscTargetDialogsIdle(t *testing.T) {
	dialogs := []func(frame) frame{
		func(f frame) frame { f.delDlg = &delDlgState{}; return f },
		func(f frame) frame { f.reportDlg = &reportDlgState{}; return f },
		func(f frame) frame { f.schedDlg = &schedDlgState{}; return f },
		func(f frame) frame { f.pollDlg = &pollDlgState{}; return f },
		func(f frame) frame { f.folderDlg = &folderDlgState{}; return f },
		func(f frame) frame { f.inviteDlg = &inviteDlgState{}; return f },
		func(f frame) frame { f.viewer = &viewerState{}; return f },
		func(f frame) frame { f.drawerOpen = true; return f },
		func(f frame) frame { f.contactsOpen = true; return f },
		func(f frame) frame { f.settingsOpen = true; return f },
	}
	for i, set := range dialogs {
		f := set(escFrame())
		f.search = "query" // would otherwise be the target
		if got := escTarget(f); got != "" {
			t.Errorf("dialog %d open: escTarget = %q, want empty", i, got)
		}
	}
}

func TestChatSwitchAction(t *testing.T) {
	cases := []struct {
		name key.Name
		ctrl bool
		want int
	}{
		{key.NameUpArrow, true, -1},
		{key.NameDownArrow, true, 1},
		{key.NamePageUp, true, -1},
		{key.NamePageDown, true, 1},
		{key.NameUpArrow, false, 0},
		{key.NameDownArrow, false, 0},
		{"A", true, 0},
		{key.NameLeftArrow, true, 0},
	}
	for _, c := range cases {
		if got := chatSwitchAction(c.name, c.ctrl); got != c.want {
			t.Errorf("chatSwitchAction(%q,%v) = %d, want %d", c.name, c.ctrl, got, c.want)
		}
	}
}

func TestNeighborChat(t *testing.T) {
	f := escFrame()
	chats := f.chats
	cur := &chatKey{AccountID: "a", ChatID: "1"}

	if c, ok := neighborChat(chats, cur, 1); !ok || c.ChatID != "2" {
		t.Errorf("next = %+v ok=%v, want chat 2", c, ok)
	}
	if c, ok := neighborChat(chats, cur, -1); !ok || c.ChatID != "3" {
		t.Errorf("prev wraps = %+v ok=%v, want chat 3", c, ok)
	}
	last := &chatKey{AccountID: "b", ChatID: "3"}
	if c, ok := neighborChat(chats, last, 1); !ok || c.ChatID != "1" {
		t.Errorf("wrap forward = %+v ok=%v, want chat 1", c, ok)
	}
	// No selection: forward opens the first chat, backward the last.
	if c, ok := neighborChat(chats, nil, 1); !ok || c.ChatID != "1" {
		t.Errorf("nil+1 = %+v ok=%v, want chat 1", c, ok)
	}
	if c, ok := neighborChat(chats, nil, -1); !ok || c.ChatID != "3" {
		t.Errorf("nil-1 = %+v ok=%v, want chat 3", c, ok)
	}
	// Selection not in list (e.g. filtered out) steps from the start.
	ghost := &chatKey{AccountID: "z", ChatID: "9"}
	if c, ok := neighborChat(chats, ghost, 1); !ok || c.ChatID != "1" {
		t.Errorf("ghost+1 = %+v ok=%v, want chat 1", c, ok)
	}
	if _, ok := neighborChat(chats, cur, 0); ok {
		t.Error("delta 0 must be a no-op")
	}
	if _, ok := neighborChat(nil, cur, 1); ok {
		t.Error("empty list must be a no-op")
	}
	if _, ok := neighborChat(chats[:1], &chatKey{AccountID: "a", ChatID: "1"}, 1); ok {
		t.Error("single-chat list has no neighbor")
	}
}
