package tests

import (
	"testing"

	. "uniclient/ui/app"
	"uniclient/ui/tokens"
)

func composeLineHeight() int {
	return 32
}

func composePoint(m Model, line, col int) (int, int) {
	g := m.ComposeGeometry()
	return g.Field.Left + col*16 + 1, g.Field.Top + line*composeLineHeight() + 1
}

func composePressAt(t *testing.T, m Model, line, col, now int, shift bool) Model {
	t.Helper()
	x, y := composePoint(m, line, col)
	m, _ = Update(m, ChatComposePressed{X: x, Y: y, Shift: shift, Now: now})
	return m
}

func composeDragAt(t *testing.T, m Model, line, col, now int) Model {
	t.Helper()
	x, y := composePoint(m, line, col)
	m, _ = Update(m, ChatComposeDragged{X: x, Y: y, Now: now})
	return m
}

func composeReleaseAt(t *testing.T, m Model, line, col, now int) Model {
	t.Helper()
	x, y := composePoint(m, line, col)
	m, _ = Update(m, ChatComposeReleased{X: x, Y: y, Now: now})
	return m
}

func TestChatComposePressPositionsCursor(t *testing.T) {
	m := composeModel(t, 400, 600)
	m = typeString(t, m, "hello world")
	m = composePressAt(t, m, 0, 3, 100, false)
	if m.ChatCompose.Cursor != 3 || m.ChatCompose.Anchor != 3 {
		t.Fatalf("press col3 = cursor %d anchor %d, want 3/3", m.ChatCompose.Cursor, m.ChatCompose.Anchor)
	}
	if !m.ChatCompose.Focused || !m.ChatCompose.CursorOn {
		t.Fatalf("press must focus and light the caret")
	}
	if !m.ChatCompose.MousePressed {
		t.Fatalf("press must set MousePressed")
	}
	if m.ChatPress.Row != -1 {
		t.Fatalf("field press leaked to the chat list (row %d)", m.ChatPress.Row)
	}
	m = composeReleaseAt(t, m, 0, 3, 150)
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeRight, Select: true})
	m = composePressAt(t, m, 0, 8, 200, false)
	if m.ChatCompose.Cursor != 8 || m.ChatCompose.Anchor != 8 {
		t.Fatalf("plain press clears selection: cursor %d anchor %d, want 8/8", m.ChatCompose.Cursor, m.ChatCompose.Anchor)
	}
	g := m.ComposeGeometry()
	m, _ = Update(m, ChatPressed{X: g.Field.Left + 1, Y: 10, Now: 300})
	if m.ChatCompose.Cursor != 8 {
		t.Fatalf("list press must not move the compose cursor (now %d)", m.ChatCompose.Cursor)
	}
}

func TestChatComposePressDragRelease(t *testing.T) {
	m := composeModel(t, 400, 600)
	m = typeString(t, m, "hello world")
	m = composePressAt(t, m, 0, 2, 100, false)
	m = composeDragAt(t, m, 0, 6, 120)
	if m.ChatCompose.Anchor != 2 || m.ChatCompose.Cursor != 6 {
		t.Fatalf("drag = anchor %d cursor %d, want 2/6", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
	if !m.ChatCompose.MousePressed {
		t.Fatalf("drag keeps MousePressed")
	}
	m = composeDragAt(t, m, 0, 1, 140)
	if m.ChatCompose.Anchor != 2 || m.ChatCompose.Cursor != 1 {
		t.Fatalf("drag back = anchor %d cursor %d, want 2/1", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
	m = composeReleaseAt(t, m, 0, 1, 160)
	if m.ChatCompose.MousePressed {
		t.Fatalf("release clears MousePressed")
	}
	if m.ChatCompose.Anchor != 2 || m.ChatCompose.Cursor != 1 {
		t.Fatalf("release settles the selection, got %d/%d", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
	m = composeDragAt(t, m, 0, 8, 180)
	if m.ChatCompose.Cursor != 1 {
		t.Fatalf("drag after release is a no-op (cursor %d)", m.ChatCompose.Cursor)
	}
}

func TestChatComposeShiftPressExtends(t *testing.T) {
	m := composeModel(t, 400, 600)
	m = typeString(t, m, "hello world")
	m = composePressAt(t, m, 0, 2, 100, false)
	m = composeReleaseAt(t, m, 0, 2, 120)
	m = composePressAt(t, m, 0, 9, 200, true)
	if m.ChatCompose.Anchor != 2 || m.ChatCompose.Cursor != 9 {
		t.Fatalf("shift+press = anchor %d cursor %d, want 2/9", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
	m = composePressAt(t, m, 0, 0, 300, true)
	if m.ChatCompose.Anchor != 2 || m.ChatCompose.Cursor != 0 {
		t.Fatalf("shift+press back = anchor %d cursor %d, want 2/0", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
}

func TestChatComposeDoubleClickSelectsWord(t *testing.T) {
	m := composeModel(t, 400, 600)
	m = typeString(t, m, "hello world")
	m = composePressAt(t, m, 0, 1, 100, false)
	m = composePressAt(t, m, 0, 1, 200, false)
	if m.ChatCompose.Anchor != 0 || m.ChatCompose.Cursor != 5 {
		t.Fatalf("double-click = anchor %d cursor %d, want 0/5", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
	if m.ChatCompose.MousePressed {
		t.Fatalf("double-click does not set MousePressed")
	}
	if m.ChatCompose.TrippleClickDeadline != 200+tokens.MouseDoubleClickIntervalMs {
		t.Fatalf("triple window = %d, want %d", m.ChatCompose.TrippleClickDeadline, 200+tokens.MouseDoubleClickIntervalMs)
	}
	m = composeDragAt(t, m, 0, 8, 260)
	if m.ChatCompose.Anchor != 0 || m.ChatCompose.Cursor != 6 {
		t.Fatalf("word-wise drag = anchor %d cursor %d, want 0/6", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
	m = composeDragAt(t, m, 0, 3, 300)
	if m.ChatCompose.Anchor != 0 || m.ChatCompose.Cursor != 5 {
		t.Fatalf("drag inside the word restores it: %d/%d, want 0/5", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
	m = composeReleaseAt(t, m, 0, 3, 320)
}

func TestChatComposeDoubleClickOnSpaceSelectsPrecedingWord(t *testing.T) {
	m := composeModel(t, 400, 600)
	m = typeString(t, m, "hello world")
	m = composePressAt(t, m, 0, 5, 100, false)
	m = composePressAt(t, m, 0, 5, 200, false)
	if m.ChatCompose.Anchor != 0 || m.ChatCompose.Cursor != 5 {
		t.Fatalf("space double-click = anchor %d cursor %d, want 0/5", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
	m = composeReleaseAt(t, m, 0, 5, 220)
	m = composePressAt(t, m, 0, 9, 300, false)
	if m.ChatCompose.Anchor != 9 || m.ChatCompose.Cursor != 9 {
		t.Fatalf("plain press clears the word selection: %d/%d, want 9/9", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
	m = composeDragAt(t, m, 0, 2, 340)
	if m.ChatCompose.Anchor != 9 || m.ChatCompose.Cursor != 2 {
		t.Fatalf("post-clear drag is a straight extend: %d/%d, want 9/2", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
}

func TestChatComposeTripleClickSelectsLine(t *testing.T) {
	m := composeModel(t, 400, 600)
	m = typeString(t, m, "ab\ncd")
	m = composePressAt(t, m, 0, 1, 100, false)
	m = composePressAt(t, m, 0, 1, 200, false)
	m = composePressAt(t, m, 0, 1, 300, false)
	if m.ChatCompose.Anchor != 0 || m.ChatCompose.Cursor != 3 {
		t.Fatalf("triple-click = anchor %d cursor %d, want 0/3 (line + newline)", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
	if m.ChatCompose.TrippleClickDeadline != 0 {
		t.Fatalf("triple-click stops the timer (deadline %d)", m.ChatCompose.TrippleClickDeadline)
	}
	m = composeDragAt(t, m, 1, 1, 360)
	if m.ChatCompose.Anchor != 0 || m.ChatCompose.Cursor != 5 {
		t.Fatalf("blockwise drag down = anchor %d cursor %d, want 0/5", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
	m = composeReleaseAt(t, m, 1, 1, 380)
	m = composePressAt(t, m, 0, 1, 900, false)
	m = composePressAt(t, m, 0, 1, 1000, false)
	m = composePressAt(t, m, 0, 1, 1100, false)
	if m.ChatCompose.Anchor != 0 || m.ChatCompose.Cursor != 3 {
		t.Fatalf("re-armed triple = %d/%d, want 0/3", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
	m = composeDragAt(t, m, 1, 0, 1160)
	if m.ChatCompose.Anchor != 0 || m.ChatCompose.Cursor != 3 {
		t.Fatalf("drag onto the block boundary restores the block: %d/%d, want 0/3", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
	m = composeReleaseAt(t, m, 1, 0, 1180)
	up := composeModel(t, 400, 600)
	up = typeString(t, up, "x\nab\ncd")
	up = composePressAt(t, up, 1, 1, 100, false)
	up = composePressAt(t, up, 1, 1, 200, false)
	up = composePressAt(t, up, 1, 1, 300, false)
	if up.ChatCompose.Anchor != 2 || up.ChatCompose.Cursor != 5 {
		t.Fatalf("mid triple = %d/%d, want 2/5", up.ChatCompose.Anchor, up.ChatCompose.Cursor)
	}
	up = composeDragAt(t, up, 0, 0, 360)
	if up.ChatCompose.Anchor != 5 || up.ChatCompose.Cursor != 0 {
		t.Fatalf("blockwise drag up = anchor %d cursor %d, want 5/0", up.ChatCompose.Anchor, up.ChatCompose.Cursor)
	}
}

func TestChatComposeTripleClickLastLine(t *testing.T) {
	m := composeModel(t, 400, 600)
	m = typeString(t, m, "ab\ncd")
	m = composePressAt(t, m, 1, 1, 100, false)
	m = composePressAt(t, m, 1, 1, 200, false)
	if m.ChatCompose.Anchor != 3 || m.ChatCompose.Cursor != 5 {
		t.Fatalf("double on last line = %d/%d, want 3/5", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
	m = composePressAt(t, m, 1, 1, 300, false)
	if m.ChatCompose.Anchor != 3 || m.ChatCompose.Cursor != 5 {
		t.Fatalf("triple on last line = %d/%d, want 3/5 (no newline to swallow)", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
}

func TestChatComposeClickChainGates(t *testing.T) {
	m := composeModel(t, 400, 600)
	m = typeString(t, m, "hello world")
	m = composePressAt(t, m, 0, 1, 100, false)
	m = composePressAt(t, m, 0, 1, 600, false)
	if m.ChatCompose.Anchor != 1 || m.ChatCompose.Cursor != 1 {
		t.Fatalf("slow second press is plain: %d/%d, want 1/1", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
	m = composePressAt(t, m, 0, 6, 700, false)
	m = composePressAt(t, m, 0, 1, 800, false)
	if m.ChatCompose.Anchor != 1 || m.ChatCompose.Cursor != 1 {
		t.Fatalf("far second press is plain: %d/%d, want 1/1", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
	m = composePressAt(t, m, 0, 1, 1300, false)
	m = composePressAt(t, m, 0, 1, 1400, false)
	if m.ChatCompose.TrippleClickDeadline != 1400+tokens.MouseDoubleClickIntervalMs {
		t.Fatalf("double rearms the triple window (got %d)", m.ChatCompose.TrippleClickDeadline)
	}
	m = composePressAt(t, m, 0, 1, 2400, false)
	if m.ChatCompose.Anchor != 1 || m.ChatCompose.Cursor != 1 {
		t.Fatalf("expired triple window falls back to plain: %d/%d, want 1/1", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
	g := m.ComposeGeometry()
	m = composePressAt(t, m, 0, 1, 2550, false)
	m, _ = Update(m, ChatPressed{X: g.Field.Left + 1, Y: 10, Now: 2560})
	m = composePressAt(t, m, 0, 1, 2600, false)
	if m.ChatCompose.Anchor == 0 && m.ChatCompose.Cursor == 5 {
		t.Fatalf("a list press between clicks must break the double chain")
	}
}

func TestChatComposeWordDragGaps(t *testing.T) {
	m := composeModel(t, 400, 600)
	m = typeString(t, m, "hello  world")
	m = composePressAt(t, m, 0, 1, 100, false)
	m = composePressAt(t, m, 0, 1, 200, false)
	if m.ChatCompose.Anchor != 0 || m.ChatCompose.Cursor != 5 {
		t.Fatalf("double = %d/%d, want 0/5", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
	m = composeDragAt(t, m, 0, 6, 260)
	if m.ChatCompose.Anchor != 0 || m.ChatCompose.Cursor != 5 {
		t.Fatalf("drag into the gap extends nothing: %d/%d, want 0/5", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
	m = composeDragAt(t, m, 0, 8, 300)
	if m.ChatCompose.Anchor != 0 || m.ChatCompose.Cursor != 7 {
		t.Fatalf("drag onto the next word = %d/%d, want 0/7", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
}

func TestChatComposeEmptyLineDoubleClick(t *testing.T) {
	m := composeModel(t, 400, 600)
	m = typeString(t, m, "a\n\nb")
	m = composePressAt(t, m, 1, 0, 100, false)
	m = composePressAt(t, m, 1, 0, 200, false)
	if m.ChatCompose.Anchor != 2 || m.ChatCompose.Cursor != 2 {
		t.Fatalf("empty-line double = %d/%d, want 2/2 (no word)", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
	if m.ChatCompose.TrippleClickDeadline != 200+tokens.MouseDoubleClickIntervalMs {
		t.Fatalf("empty-line double still arms the triple window (got %d)", m.ChatCompose.TrippleClickDeadline)
	}
	m = composePressAt(t, m, 1, 0, 300, false)
	if m.ChatCompose.Anchor != 2 || m.ChatCompose.Cursor != 3 {
		t.Fatalf("empty-line triple = %d/%d, want 2/3 (the bare newline)", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
}

func TestChatComposeBlink(t *testing.T) {
	m := composeModel(t, 400, 600)
	m = typeString(t, m, "hello")
	if m.ChatCompose.Focused || m.ComposePane().CaretOn {
		t.Fatalf("unfocused field shows no caret")
	}
	m = composePressAt(t, m, 0, 1, 100, false)
	if !m.ComposePane().CaretOn {
		t.Fatalf("press lights the caret")
	}
	m, _ = Update(m, ChatTick{Now: 599})
	if !m.ChatCompose.CursorOn {
		t.Fatalf("caret holds before the half-flash")
	}
	m, _ = Update(m, ChatTick{Now: 600})
	if m.ChatCompose.CursorOn {
		t.Fatalf("caret blinks off at flashTime/2")
	}
	m, _ = Update(m, ChatTick{Now: 1100})
	if !m.ChatCompose.CursorOn {
		t.Fatalf("caret blinks back on")
	}
	m = composePressAt(t, m, 0, 1, 1200, false)
	m = composePressAt(t, m, 0, 1, 1250, false)
	if m.ChatCompose.Anchor == m.ChatCompose.Cursor {
		t.Fatalf("double-click selected a word")
	}
	if !m.ChatCompose.CursorOn {
		t.Fatalf("caret keeps its blink phase when the selection is made")
	}
	m, _ = Update(m, ChatTick{Now: 1600})
	m, _ = Update(m, ChatTick{Now: 2100})
	if m.ChatCompose.CursorOn || m.ComposePane().CaretOn {
		t.Fatalf("caret stays hidden while selected (blink-when-selected is off)")
	}
	m = composeReleaseAt(t, m, 0, 1, 2150)
	m = composePressAt(t, m, 0, 3, 2300, false)
	m, _ = Update(m, ChatTick{Now: 2600})
	if !m.ChatCompose.CursorOn {
		t.Fatalf("caret resumes blinking once the selection is gone")
	}
	m, _ = Update(m, ChatTick{Now: 3100})
	if m.ChatCompose.CursorOn {
		t.Fatalf("caret keeps alternating after the resume")
	}
}

func TestChatComposeTouchPressRoutesToField(t *testing.T) {
	m := composeModel(t, 400, 600)
	m = typeString(t, m, "hello world")
	x, y := composePoint(m, 0, 4)
	m, _ = Update(m, ChatPressed{X: x, Y: y, Touch: true, Now: 100})
	if m.ChatCompose.Cursor != 4 {
		t.Fatalf("touch press positions the cursor (got %d)", m.ChatCompose.Cursor)
	}
	if m.ChatTouch.Active {
		t.Fatalf("field touch press must not start list scrolling")
	}
	m = composeDragAt(t, m, 0, 8, 150)
	if m.ChatCompose.Anchor != 4 || m.ChatCompose.Cursor != 8 {
		t.Fatalf("touch drag extends: %d/%d, want 4/8", m.ChatCompose.Anchor, m.ChatCompose.Cursor)
	}
	m = composeReleaseAt(t, m, 0, 8, 180)
	if m.ChatCompose.MousePressed {
		t.Fatalf("touch release settles")
	}
}
