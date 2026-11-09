package tests

import (
	"testing"

	"gioui.org/io/key"

	. "uniclient/ui/app"
)

func composeKey(name key.Name, mods key.Modifiers) Msg {
	return ComposeKeyMsg(key.Event{Name: name, Modifiers: mods, State: key.Press}, 1000)
}

func TestComposeKeyMsgMapsControlKeys(t *testing.T) {
	cases := []struct {
		name key.Name
		mods key.Modifiers
		want Msg
	}{
		{key.NameLeftArrow, 0, ChatComposeCursorKey{Dir: ComposeLeft}},
		{key.NameLeftArrow, key.ModShift, ChatComposeCursorKey{Dir: ComposeLeft, Select: true}},
		{key.NameLeftArrow, key.ModCtrl, ChatComposeCursorKey{Dir: ComposeWordLeft}},
		{key.NameLeftArrow, key.ModCtrl | key.ModShift, ChatComposeCursorKey{Dir: ComposeWordLeft, Select: true}},
		{key.NameRightArrow, 0, ChatComposeCursorKey{Dir: ComposeRight}},
		{key.NameRightArrow, key.ModShift, ChatComposeCursorKey{Dir: ComposeRight, Select: true}},
		{key.NameRightArrow, key.ModCtrl, ChatComposeCursorKey{Dir: ComposeWordRight}},
		{key.NameHome, 0, ChatComposeCursorKey{Dir: ComposeHome}},
		{key.NameHome, key.ModShift, ChatComposeCursorKey{Dir: ComposeHome, Select: true}},
		{key.NameHome, key.ModCtrl, ChatComposeCursorKey{Dir: ComposeDocHome}},
		{key.NameEnd, 0, ChatComposeCursorKey{Dir: ComposeEnd}},
		{key.NameEnd, key.ModShift, ChatComposeCursorKey{Dir: ComposeEnd, Select: true}},
		{key.NameEnd, key.ModCtrl, ChatComposeCursorKey{Dir: ComposeDocEnd}},
		{key.NameDeleteBackward, 0, ChatComposeBackspace{Now: 1000}},
		{key.NameDeleteBackward, key.ModCtrl, ChatComposeBackspace{Word: true, Now: 1000}},
		{key.NameDeleteForward, 0, ChatComposeDelete{Now: 1000}},
		{key.NameDeleteForward, key.ModCtrl, ChatComposeDelete{Word: true, Now: 1000}},
		{"A", key.ModCtrl, ChatComposeSelectAll{}},
		{key.NameReturn, key.ModShift, ChatComposeTyped{Text: "\n", Now: 1000}},
		{key.NameReturn, key.ModCtrl, ChatComposeTyped{Text: "\n", Now: 1000}},
		{key.NameEnter, key.ModShift, ChatComposeTyped{Text: "\n", Now: 1000}},
	}
	for _, c := range cases {
		if got := composeKey(c.name, c.mods); got != c.want {
			t.Fatalf("ComposeKeyMsg(%q, %v) = %#v, want %#v", c.name, c.mods, got, c.want)
		}
	}
}

func TestComposeKeyMsgIgnoresNonFieldKeys(t *testing.T) {
	cases := []struct {
		name key.Name
		mods key.Modifiers
	}{
		{key.NameUpArrow, 0},
		{key.NameDownArrow, 0},
		{key.NameUpArrow, key.ModShift},
		{key.NamePageUp, 0},
		{key.NamePageDown, 0},
		{key.NameReturn, 0},
		{key.NameEnter, 0},
		{key.NameEscape, 0},
		{key.NameTab, 0},
		{"a", 0},
		{"A", 0},
		{"A", key.ModShift},
		{"1", 0},
		{key.NameF5, 0},
		{key.NameShift, 0},
		{key.NameCtrl, 0},
		{key.NameLeftArrow, key.ModAlt},
		{key.NameHome, key.ModSuper},
		{key.NameReturn, key.ModAlt},
	}
	for _, c := range cases {
		if got := composeKey(c.name, c.mods); got != nil {
			t.Fatalf("ComposeKeyMsg(%q, %v) = %#v, want nil", c.name, c.mods, got)
		}
	}
	if ComposeKeyMsg(key.Event{Name: key.NameLeftArrow, State: key.Release}, 1000) != nil {
		t.Fatal("key release must not map to a msg")
	}
}

func TestComposeEditMsg(t *testing.T) {
	if got := ComposeEditMsg(key.EditEvent{Text: "a"}, 1000); got != (ChatComposeTyped{Text: "a", Now: 1000}) {
		t.Fatalf("plain edit = %#v, want typed a", got)
	}
	if got := ComposeEditMsg(key.EditEvent{Text: "äner"}, 1000); got != (ChatComposeTyped{Text: "äner", Now: 1000}) {
		t.Fatalf("unicode edit = %#v, want typed äner", got)
	}
	if got := ComposeEditMsg(key.EditEvent{Range: key.Range{Start: 0, End: 2}, Text: "x"}, 1000); got != nil {
		t.Fatalf("ranged IME edit = %#v, want nil until the IME front", got)
	}
	if got := ComposeEditMsg(key.EditEvent{}, 1000); got != nil {
		t.Fatalf("empty edit = %#v, want nil", got)
	}
}

func TestChatComposeFocusLostJourney(t *testing.T) {
	m := composeModel(t, 400, 600)
	m = typeString(t, m, "hi")
	m = composePressAt(t, m, 0, 1, 100, false)
	if !m.ChatCompose.Focused || !m.ChatCompose.CursorOn {
		t.Fatal("setup: field press must focus and light the caret")
	}
	m, _ = Update(m, ChatComposeFocusLost{})
	if m.ChatCompose.Focused || m.ChatCompose.CursorOn {
		t.Fatal("focus lost must drop Focused and the caret light")
	}
	if m.ChatCompose.Text != "hi" || m.ChatCompose.Cursor != 1 {
		t.Fatalf("focus lost keeps text/cursor: %q cursor %d", m.ChatCompose.Text, m.ChatCompose.Cursor)
	}
	m, _ = Update(m, ChatComposeTyped{Text: "!", Now: 200})
	if m.ChatCompose.Text != "h!i" {
		t.Fatalf("typing still works unfocused: %q", m.ChatCompose.Text)
	}
	m = composePressAt(t, m, 0, 2, 300, false)
	if !m.ChatCompose.Focused || !m.ChatCompose.CursorOn {
		t.Fatal("re-press refocuses and relights the caret")
	}
}
