package tests

import (
	"testing"

	. "uniclient/ui/app"
	"uniclient/ui/history"
	"uniclient/ui/text"
)

func composeMetrics() text.Metrics {
	return text.Metrics{Height: 32, Advance: func(rune) int { return 16 }}
}

func composeModel(t *testing.T, w, h int) Model {
	t.Helper()
	m, _ := Update(InitialModel(), Resized{Width: w, Height: h})
	m.ChatCompose = ChatComposeState{CanSend: true, Metrics: composeMetrics()}
	return m
}

func typeString(t *testing.T, m Model, s string) Model {
	t.Helper()
	for _, r := range s {
		m, _ = Update(m, ChatComposeTyped{Text: string(r)})
	}
	return m
}

func TestChatComposeTypedJourney(t *testing.T) {
	m := composeModel(t, 400, 600)
	m = typeString(t, m, "hello")
	if m.ChatCompose.Text != "hello" || m.ChatCompose.Cursor != 5 || m.ChatCompose.Anchor != 5 {
		t.Fatalf("typed hello = %q cursor %d anchor %d", m.ChatCompose.Text, m.ChatCompose.Cursor, m.ChatCompose.Anchor)
	}
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeLeft})
	if m.ChatCompose.Cursor != 4 {
		t.Fatalf("left = %d, want 4", m.ChatCompose.Cursor)
	}
	m = typeString(t, m, "XY")
	if m.ChatCompose.Text != "hellXYo" || m.ChatCompose.Cursor != 6 {
		t.Fatalf("insert at 4 = %q cursor %d", m.ChatCompose.Text, m.ChatCompose.Cursor)
	}
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeLeft})
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeLeft, Select: true})
	if m.ChatCompose.Cursor != 4 || m.ChatCompose.Anchor != 5 {
		t.Fatalf("shift-left = cursor %d anchor %d, want 4/5", m.ChatCompose.Cursor, m.ChatCompose.Anchor)
	}
	m = typeString(t, m, "Z")
	if m.ChatCompose.Text != "hellZYo" || m.ChatCompose.Cursor != 5 || m.ChatCompose.Anchor != 5 {
		t.Fatalf("selection replaced = %q cursor %d anchor %d", m.ChatCompose.Text, m.ChatCompose.Cursor, m.ChatCompose.Anchor)
	}
}

func TestChatComposeBackspaceDelete(t *testing.T) {
	m := composeModel(t, 400, 600)
	m = typeString(t, m, "hello")
	m, _ = Update(m, ChatComposeBackspace{})
	if m.ChatCompose.Text != "hell" || m.ChatCompose.Cursor != 4 {
		t.Fatalf("backspace = %q cursor %d", m.ChatCompose.Text, m.ChatCompose.Cursor)
	}
	m, _ = Update(m, ChatComposeDelete{})
	if m.ChatCompose.Text != "hell" {
		t.Fatalf("delete at end = %q, want no-op", m.ChatCompose.Text)
	}
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeDocHome})
	m, _ = Update(m, ChatComposeDelete{})
	if m.ChatCompose.Text != "ell" || m.ChatCompose.Cursor != 0 {
		t.Fatalf("delete fwd = %q cursor %d", m.ChatCompose.Text, m.ChatCompose.Cursor)
	}
	m = composeModel(t, 400, 600)
	m = typeString(t, m, "hello world")
	m, _ = Update(m, ChatComposeBackspace{Word: true})
	if m.ChatCompose.Text != "hello " || m.ChatCompose.Cursor != 6 {
		t.Fatalf("word backspace = %q cursor %d", m.ChatCompose.Text, m.ChatCompose.Cursor)
	}
	m, _ = Update(m, ChatComposeBackspace{Word: true})
	if m.ChatCompose.Text != "" || m.ChatCompose.Cursor != 0 {
		t.Fatalf("second word backspace = %q cursor %d", m.ChatCompose.Text, m.ChatCompose.Cursor)
	}
	m = composeModel(t, 400, 600)
	m = typeString(t, m, "foo bar baz")
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeDocHome})
	m, _ = Update(m, ChatComposeDelete{Word: true})
	if m.ChatCompose.Text != "bar baz" || m.ChatCompose.Cursor != 0 {
		t.Fatalf("word delete fwd = %q cursor %d", m.ChatCompose.Text, m.ChatCompose.Cursor)
	}
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeWordRight})
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeRight, Select: true})
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeRight, Select: true})
	m, _ = Update(m, ChatComposeBackspace{})
	if m.ChatCompose.Text != "bar z" || m.ChatCompose.Cursor != 4 {
		t.Fatalf("selection backspace = %q cursor %d", m.ChatCompose.Text, m.ChatCompose.Cursor)
	}
}

func TestChatComposeCursorKeysHorizontal(t *testing.T) {
	m := composeModel(t, 400, 600)
	m = typeString(t, m, "foo bar")
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeDocHome})
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeLeft})
	if m.ChatCompose.Cursor != 0 {
		t.Fatalf("left at 0 = %d, want 0", m.ChatCompose.Cursor)
	}
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeRight})
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeWordRight})
	if m.ChatCompose.Cursor != 4 {
		t.Fatalf("word right from 1 = %d, want 4", m.ChatCompose.Cursor)
	}
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeWordRight})
	if m.ChatCompose.Cursor != 7 {
		t.Fatalf("word right = %d, want 7", m.ChatCompose.Cursor)
	}
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeWordRight})
	if m.ChatCompose.Cursor != 7 {
		t.Fatalf("word right at end = %d, want 7", m.ChatCompose.Cursor)
	}
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeWordLeft})
	if m.ChatCompose.Cursor != 4 {
		t.Fatalf("word left from 7 = %d, want 4", m.ChatCompose.Cursor)
	}
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeWordLeft})
	if m.ChatCompose.Cursor != 0 {
		t.Fatalf("word left from 4 = %d, want 0", m.ChatCompose.Cursor)
	}
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeRight, Select: true})
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeRight, Select: true})
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeRight, Select: true})
	if m.ChatCompose.Cursor != 3 || m.ChatCompose.Anchor != 0 {
		t.Fatalf("shift-right x3 = %d/%d, want 3/0", m.ChatCompose.Cursor, m.ChatCompose.Anchor)
	}
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeLeft})
	if m.ChatCompose.Cursor != 0 {
		t.Fatalf("left collapses selection = %d, want 0", m.ChatCompose.Cursor)
	}
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeRight, Select: true})
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeRight, Select: true})
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeRight})
	if m.ChatCompose.Cursor != 2 {
		t.Fatalf("right collapses selection forward = %d, want 2 (Qt MoveAnchor: collapse to max, no step)", m.ChatCompose.Cursor)
	}
	hard := composeModel(t, 400, 600)
	hard = typeString(t, hard, "aa\nbbb")
	hard, _ = Update(hard, ChatComposeCursorKey{Dir: ComposeEnd})
	hard, _ = Update(hard, ChatComposeCursorKey{Dir: ComposeLeft})
	hard, _ = Update(hard, ChatComposeCursorKey{Dir: ComposeLeft})
	if hard.ChatCompose.Cursor != 4 {
		t.Fatalf("left over newline = %d, want 4", hard.ChatCompose.Cursor)
	}
	hard, _ = Update(hard, ChatComposeCursorKey{Dir: ComposeHome})
	if hard.ChatCompose.Cursor != 3 {
		t.Fatalf("home on line 1 = %d, want 3", hard.ChatCompose.Cursor)
	}
	hard, _ = Update(hard, ChatComposeCursorKey{Dir: ComposeEnd})
	if hard.ChatCompose.Cursor != 6 {
		t.Fatalf("end = %d, want 6", hard.ChatCompose.Cursor)
	}
	hard, _ = Update(hard, ChatComposeCursorKey{Dir: ComposeDocHome})
	if hard.ChatCompose.Cursor != 0 {
		t.Fatalf("doc home = %d, want 0", hard.ChatCompose.Cursor)
	}
}

func TestChatComposeCursorVerticalGoalX(t *testing.T) {
	m := composeModel(t, 400, 600)
	m = typeString(t, m, "aaaa\nbbbbbbbb\ncccccccc")
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeDocEnd})
	if m.ChatCompose.Cursor != 22 {
		t.Fatalf("doc end = %d, want 22", m.ChatCompose.Cursor)
	}
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeUp})
	if m.ChatCompose.Cursor != 13 {
		t.Fatalf("up from end = %d, want 13 (goal x 128 -> col 8)", m.ChatCompose.Cursor)
	}
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeUp})
	if m.ChatCompose.Cursor != 4 {
		t.Fatalf("up to line 0 = %d, want 4 (nearest col 4)", m.ChatCompose.Cursor)
	}
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeDown})
	if m.ChatCompose.Cursor != 13 {
		t.Fatalf("down keeps goal = %d, want 13 (goal 128, not 9 from re-derived x 64)", m.ChatCompose.Cursor)
	}
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeUp})
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeUp})
	m = typeString(t, m, "Z")
	if m.ChatCompose.Text != "aaaaZ\nbbbbbbbb\ncccccccc" || m.ChatCompose.Cursor != 5 {
		t.Fatalf("typed at 4 = %q cursor %d", m.ChatCompose.Text, m.ChatCompose.Cursor)
	}
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeDown})
	if m.ChatCompose.Cursor != 11 {
		t.Fatalf("down after edit re-derives goal = %d, want 11 (x 80 -> col 5)", m.ChatCompose.Cursor)
	}
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeDown})
	if m.ChatCompose.Cursor != 20 {
		t.Fatalf("down persists goal = %d, want 20 (goal 80 -> col 5)", m.ChatCompose.Cursor)
	}
}

func TestChatComposeSelectAllReplaces(t *testing.T) {
	m := composeModel(t, 400, 600)
	m = typeString(t, m, "hello")
	m, _ = Update(m, ChatComposeSelectAll{})
	if m.ChatCompose.Cursor != 5 || m.ChatCompose.Anchor != 0 {
		t.Fatalf("select all = %d/%d, want 5/0", m.ChatCompose.Cursor, m.ChatCompose.Anchor)
	}
	m = typeString(t, m, "bye")
	if m.ChatCompose.Text != "bye" || m.ChatCompose.Cursor != 3 || m.ChatCompose.Anchor != 3 {
		t.Fatalf("typed over selection = %q %d/%d", m.ChatCompose.Text, m.ChatCompose.Cursor, m.ChatCompose.Anchor)
	}
	m, _ = Update(m, ChatComposeSelectAll{})
	m, _ = Update(m, ChatComposeBackspace{})
	if m.ChatCompose.Text != "" || m.ChatCompose.Cursor != 0 {
		t.Fatalf("backspace over selection = %q cursor %d", m.ChatCompose.Text, m.ChatCompose.Cursor)
	}
}

func TestChatComposeScrollRevealsCursor(t *testing.T) {
	m := composeModel(t, 400, 600)
	m = typeString(t, m, "a\nb\nc\nd\ne\nf\ng\nh\ni\nj")
	if m.ComposeFieldHeight() != 224 {
		t.Fatalf("field height = %d, want 224 (capped)", m.ComposeFieldHeight())
	}
	if m.ChatCompose.Scroll != 96 {
		t.Fatalf("scroll = %d, want 96 (cursor line 9 -> 288+32-224)", m.ChatCompose.Scroll)
	}
	for i := 0; i < 6; i++ {
		m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeUp})
	}
	if m.ChatCompose.Scroll != 96 {
		t.Fatalf("scroll after 6 ups = %d, want 96 (cursor still in view)", m.ChatCompose.Scroll)
	}
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeUp})
	if m.ChatCompose.Cursor != 5 || m.ChatCompose.Scroll != 64 {
		t.Fatalf("7th up = cursor %d scroll %d, want 5/64 (minimal reveal)", m.ChatCompose.Cursor, m.ChatCompose.Scroll)
	}
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeDocEnd})
	m = typeString(t, m, "\n\n\n\n\n")
	if m.ChatCompose.Scroll != 256 {
		t.Fatalf("scroll after 5 more lines = %d, want 256 (15 lines: 480-224)", m.ChatCompose.Scroll)
	}
}

func TestChatComposeFieldGrowsChatSticksToBottom(t *testing.T) {
	items := make([]history.Item, 20)
	heights := make([]int, 20)
	for i := range heights {
		heights[i] = 50
	}
	m := InitialModel()
	m.ChatCompose = ChatComposeState{CanSend: true, Metrics: composeMetrics()}
	m, _ = Update(m, Resized{Width: 400, Height: 600})
	m, _ = Update(m, ChatLoaded{Items: items})
	m, _ = Update(m, ChatMeasured{Heights: heights})
	m, _ = Update(m, ChatScrolled{DeltaY: 10000})
	if m.ChatScroll.Top != 454 || m.ChatScroll.Height != 546 {
		t.Fatalf("at bottom = top %d height %d, want 454/546 (1000-546)", m.ChatScroll.Top, m.ChatScroll.Height)
	}
	m = typeString(t, m, "a\nb\nc\nd\ne\nf\ng\nh\ni\nj")
	if m.ChatScroll.Height != 358 {
		t.Fatalf("viewport after grow = %d, want 358 (600-(224+18))", m.ChatScroll.Height)
	}
	if m.ChatScroll.Top != 642 {
		t.Fatalf("bottom pinned = %d, want 642 (1000-358)", m.ChatScroll.Top)
	}
	n := InitialModel()
	n.ChatCompose = ChatComposeState{CanSend: true, Metrics: composeMetrics()}
	n, _ = Update(n, Resized{Width: 400, Height: 600})
	n, _ = Update(n, ChatLoaded{Items: items})
	n, _ = Update(n, ChatMeasured{Heights: heights})
	n, _ = Update(n, ChatScrolled{DeltaY: 200})
	n = typeString(t, n, "a\nb\nc\nd\ne\nf\ng\nh\ni\nj")
	if n.ChatScroll.Top != 200 {
		t.Fatalf("not at bottom stays = %d, want 200", n.ChatScroll.Top)
	}
}

func TestChatComposeResizeRelayouts(t *testing.T) {
	items := make([]history.Item, 20)
	heights := make([]int, 20)
	for i := range heights {
		heights[i] = 50
	}
	m, _ := Update(InitialModel(), Resized{Width: 400, Height: 600})
	m.ChatCompose = ChatComposeState{CanSend: true, Metrics: composeMetrics()}
	m, _ = Update(m, ChatLoaded{Items: items})
	m, _ = Update(m, ChatMeasured{Heights: heights})
	m, _ = Update(m, ChatScrolled{DeltaY: 10000})
	m = typeString(t, m, "aaaaaaaaaaaaaaaa aaaaaaaaaaaaaaaa")
	if m.ComposeFieldHeight() != 64 {
		t.Fatalf("field height @400 = %d, want 64 (2 lines x 32)", m.ComposeFieldHeight())
	}
	if m.ChatScroll.Height != 518 {
		t.Fatalf("viewport @400 = %d, want 518", m.ChatScroll.Height)
	}
	m, _ = Update(m, Resized{Width: 200, Height: 600})
	if m.ComposeFieldHeight() != 224 {
		t.Fatalf("field height @200 = %d, want 224 (8 lines capped)", m.ComposeFieldHeight())
	}
	if m.ChatScroll.Height != 358 {
		t.Fatalf("viewport @200 = %d, want 358", m.ChatScroll.Height)
	}
	if m.ChatScroll.Top != 642 {
		t.Fatalf("bottom pinned across resize = %d, want 642", m.ChatScroll.Top)
	}
}

func TestChatComposeGeometryProjection(t *testing.T) {
	m := composeModel(t, 400, 600)
	m = typeString(t, m, "hi")
	geo := m.ComposeGeometry()
	if geo.Field != (history.Geometry{Left: 46, Top: 555, Width: 266, Height: 36}) {
		t.Fatalf("field = %+v", geo.Field)
	}
	if geo.Send != (history.Geometry{Left: 354, Top: 554, Width: 44, Height: 46}) {
		t.Fatalf("send = %+v", geo.Send)
	}
	if geo.Attach != (history.Geometry{Left: 2, Top: 554, Width: 44, Height: 46}) {
		t.Fatalf("attach = %+v", geo.Attach)
	}
	if geo.Emoji != (history.Geometry{Left: 310, Top: 554, Width: 44, Height: 46}) {
		t.Fatalf("emoji = %+v", geo.Emoji)
	}
}

func TestChatComposeHiddenWhenCannotSend(t *testing.T) {
	m, _ := Update(InitialModel(), Resized{Width: 400, Height: 600})
	m, _ = Update(m, ChatComposeTyped{Text: "hi"})
	if m.ChatCompose.Text != "" || m.ChatCompose.Cursor != 0 {
		t.Fatalf("typed into hidden field = %q %d", m.ChatCompose.Text, m.ChatCompose.Cursor)
	}
	m, _ = Update(m, ChatComposeBackspace{})
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeRight})
	m, _ = Update(m, ChatComposeSelectAll{})
	if m.ChatCompose.Cursor != 0 || m.ChatCompose.Anchor != 0 {
		t.Fatalf("hidden field cursor moved = %d/%d", m.ChatCompose.Cursor, m.ChatCompose.Anchor)
	}
	if m.ChatScroll.Height != 600 {
		t.Fatalf("viewport with hidden bar = %d, want 600", m.ChatScroll.Height)
	}
	if m.ComposeFieldHeight() != 28 {
		t.Fatalf("hidden field height = %d, want 28", m.ComposeFieldHeight())
	}
}
