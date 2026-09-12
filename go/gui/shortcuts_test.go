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

	// The privacy scope picker (slice 62) self-handles Esc too.
	pf := escFrame()
	pf.privacyDlg = &privacyDlgState{accountID: "a", key: "calls"}
	pf.menu = &menuTarget{}
	if got := escTarget(pf); got != "" {
		t.Errorf("privacyDlg + menu: escTarget = %q, want empty (dialog consumes Esc)", got)
	}

	// The auto-download rules editor (slice 63) self-handles Esc too.
	af := escFrame()
	af.autoDlDlg = &autodlDlgState{source: "group"}
	af.menu = &menuTarget{}
	if got := escTarget(af); got != "" {
		t.Errorf("autoDlDlg + menu: escTarget = %q, want empty (dialog consumes Esc)", got)
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
		if got := chatSwitchAction(c.name, c.ctrl, false); got != c.want {
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

// ── slice 166: the tdesktop jumplist family ───────────────────────────────

func TestChatSwitchActionAltArrows(t *testing.T) {
	// Alt+Up/Down switch chats too (tdesktop ChatNext/ChatPrevious).
	cases := []struct {
		name key.Name
		ctrl bool
		alt  bool
		want int
	}{
		{key.NameUpArrow, false, true, -1},
		{key.NameDownArrow, false, true, 1},
		{key.NameUpArrow, false, false, 0},
		{key.NameDownArrow, false, false, 0},
		{key.NamePageUp, false, true, 0}, // Alt+PgUp is not a tdesktop binding
		{key.NameLeftArrow, false, true, 0},
	}
	for _, c := range cases {
		if got := chatSwitchAction(c.name, c.ctrl, c.alt); got != c.want {
			t.Errorf("chatSwitchAction(%q,%v,%v) = %d, want %d", c.name, c.ctrl, c.alt, got, c.want)
		}
	}
}

func TestJumplistDigit(t *testing.T) {
	cases := []struct {
		name key.Name
		ctrl bool
		want int
	}{
		{"1", true, 1},
		{"8", true, 8},
		{"9", true, 9},  // ShowArchive
		{"0", true, 10}, // ChatSelf (Saved Messages)
		{"1", false, 0},
		{"9", false, 0},
		{"A", true, 0},
	}
	for _, c := range cases {
		if got := jumplistDigit(c.name, c.ctrl); got != c.want {
			t.Errorf("jumplistDigit(%q,%v) = %d, want %d", c.name, c.ctrl, got, c.want)
		}
	}
}

func TestPinnedJumpChat(t *testing.T) {
	// The visible list is pinned-first; ChatPinned1..8 jump into that
	// pinned prefix.
	chats := []engine.ChatInfo{
		{ChatID: "p1", IsPinned: true},
		{ChatID: "p2", IsPinned: true},
		{ChatID: "p3", IsPinned: true},
		{ChatID: "a", IsPinned: false},
		{ChatID: "b", IsPinned: false},
	}
	if c, ok := pinnedJumpChat(chats, 1); !ok || c.ChatID != "p1" {
		t.Errorf("pinned 1 = %v,%v", c.ChatID, ok)
	}
	if c, ok := pinnedJumpChat(chats, 3); !ok || c.ChatID != "p3" {
		t.Errorf("pinned 3 = %v,%v", c.ChatID, ok)
	}
	if _, ok := pinnedJumpChat(chats, 4); ok {
		t.Error("pinned 4 must not resolve (only 3 pinned)")
	}
	if _, ok := pinnedJumpChat(chats, 0); ok {
		t.Error("index 0 must not resolve")
	}
}

func TestChatEdgeAction(t *testing.T) {
	// Ctrl+Alt+Home/End = ChatFirst/ChatLast (1 = first, 2 = last).
	cases := []struct {
		name key.Name
		ctrl bool
		alt  bool
		want int
	}{
		{key.NameHome, true, true, 1},
		{key.NameEnd, true, true, 2},
		{key.NameHome, true, false, 0},
		{key.NameHome, false, true, 0},
		{key.NameEnd, true, false, 0},
	}
	for _, c := range cases {
		if got := chatEdgeAction(c.name, c.ctrl, c.alt); got != c.want {
			t.Errorf("chatEdgeAction(%q,%v,%v) = %d, want %d", c.name, c.ctrl, c.alt, got, c.want)
		}
	}
}

func TestJumplistSpecialKeys(t *testing.T) {
	// Ctrl+J = ShowContacts, Ctrl+R = ReadChat (plain bool predicates).
	if !showContactsKey("J", true) {
		t.Error("Ctrl+J must trigger contacts")
	}
	if showContactsKey("J", false) || showContactsKey("K", true) {
		t.Error("only Ctrl+J triggers contacts")
	}
	if !readChatKey("R", true) {
		t.Error("Ctrl+R must trigger read")
	}
	if readChatKey("R", false) || readChatKey("T", true) {
		t.Error("only Ctrl+R triggers read")
	}
}
