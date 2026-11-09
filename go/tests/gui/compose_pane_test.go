package tests

import (
	"testing"

	. "uniclient/ui/app"
	"uniclient/ui/history"
	"uniclient/ui/text"
)

func TestChatComposePlaceholderFadesOnFirstType(t *testing.T) {
	m := composeModel(t, 400, 600)
	m.ChatCompose.Placeholder = "Message"
	m, _ = Update(m, ChatComposeTyped{Text: "h", Now: 1000})
	if !m.ChatCompose.PlaceholderShifted || !m.ChatCompose.PlaceholderAnim {
		t.Fatalf("anim not started: %+v", m.ChatCompose)
	}
	if m.ChatCompose.PlaceholderFrom != 0 || m.ChatCompose.PlaceholderTo != 1 || m.ChatCompose.PlaceholderStarted != 1000 {
		t.Fatalf("anim params = %f/%f/%d, want 0/1/1000", m.ChatCompose.PlaceholderFrom, m.ChatCompose.PlaceholderTo, m.ChatCompose.PlaceholderStarted)
	}
	if m.ChatCompose.PlaceholderDegree != 0 {
		t.Fatalf("degree before tick = %f, want 0", m.ChatCompose.PlaceholderDegree)
	}
	m, _ = Update(m, ChatTick{Now: 1050})
	if m.ChatCompose.PlaceholderDegree != 0.5 {
		t.Fatalf("degree at 50ms = %f, want 0.5 (linear)", m.ChatCompose.PlaceholderDegree)
	}
	pane := m.ComposePane()
	if pane.Placeholder.Opacity != 0.5 {
		t.Fatalf("opacity at 0.5 degree = %f, want 0.5", pane.Placeholder.Opacity)
	}
	if pane.Placeholder.X != 27 {
		t.Fatalf("placeholder x at 0.5 degree = %d, want 27 (2 + round(50*0.5))", pane.Placeholder.X)
	}
	m, _ = Update(m, ChatTick{Now: 1100})
	if m.ChatCompose.PlaceholderDegree != 1 || m.ChatCompose.PlaceholderAnim {
		t.Fatalf("degree at 100ms = %f anim %v, want 1/false", m.ChatCompose.PlaceholderDegree, m.ChatCompose.PlaceholderAnim)
	}
	if pane = m.ComposePane(); pane.Placeholder.Text != "" {
		t.Fatalf("hidden placeholder painted = %q", pane.Placeholder.Text)
	}
}

func TestChatComposePlaceholderShowsOnClear(t *testing.T) {
	m := composeModel(t, 400, 600)
	m.ChatCompose.Placeholder = "Message"
	m, _ = Update(m, ChatComposeTyped{Text: "hi", Now: 1000})
	m, _ = Update(m, ChatTick{Now: 1100})
	m, _ = Update(m, ChatComposeBackspace{Now: 2000})
	m, _ = Update(m, ChatComposeBackspace{Now: 2000})
	if m.ChatCompose.PlaceholderShifted || !m.ChatCompose.PlaceholderAnim {
		t.Fatalf("show anim not started: %+v", m.ChatCompose)
	}
	if m.ChatCompose.PlaceholderFrom != 1 || m.ChatCompose.PlaceholderTo != 0 || m.ChatCompose.PlaceholderStarted != 2000 {
		t.Fatalf("show params = %f/%f/%d, want 1/0/2000", m.ChatCompose.PlaceholderFrom, m.ChatCompose.PlaceholderTo, m.ChatCompose.PlaceholderStarted)
	}
	m, _ = Update(m, ChatTick{Now: 2050})
	if m.ChatCompose.PlaceholderDegree != 0.5 {
		t.Fatalf("show degree at 50ms = %f, want 0.5", m.ChatCompose.PlaceholderDegree)
	}
	m, _ = Update(m, ChatTick{Now: 2100})
	pane := m.ComposePane()
	if pane.Placeholder.Opacity != 1 || pane.Placeholder.X != 2 {
		t.Fatalf("shown placeholder = opacity %f x %d, want 1/2", pane.Placeholder.Opacity, pane.Placeholder.X)
	}
	if pane.Placeholder.Text != "Message" {
		t.Fatalf("placeholder text = %q", pane.Placeholder.Text)
	}
}

func TestChatComposePlaceholderAnimNoRestartOnSameState(t *testing.T) {
	m := composeModel(t, 400, 600)
	m.ChatCompose.Placeholder = "Message"
	m, _ = Update(m, ChatComposeTyped{Text: "h", Now: 1000})
	m, _ = Update(m, ChatTick{Now: 1050})
	m, _ = Update(m, ChatComposeTyped{Text: "i", Now: 1070})
	if !m.ChatCompose.PlaceholderAnim || m.ChatCompose.PlaceholderStarted != 1000 {
		t.Fatalf("same-state edit restarted anim: started %d", m.ChatCompose.PlaceholderStarted)
	}
	m, _ = Update(m, ChatComposeBackspace{Now: 1080})
	if !m.ChatCompose.PlaceholderAnim || m.ChatCompose.PlaceholderStarted != 1000 {
		t.Fatalf("backspace (still nonempty) restarted anim: started %d", m.ChatCompose.PlaceholderStarted)
	}
	m, _ = Update(m, ChatComposeBackspace{Now: 1080})
	m, _ = Update(m, ChatComposeBackspace{Now: 1080})
	if !m.ChatCompose.PlaceholderAnim || m.ChatCompose.PlaceholderStarted != 1080 || m.ChatCompose.PlaceholderFrom != 0.5 {
		t.Fatalf("clear restart params = started %d from %f, want 1080/0.5 (degree holds between ticks)", m.ChatCompose.PlaceholderStarted, m.ChatCompose.PlaceholderFrom)
	}
}

func TestChatComposePaneProjection(t *testing.T) {
	m := composeModel(t, 400, 600)
	m.ChatCompose.Placeholder = "Message"
	m, _ = Update(m, ChatComposeTyped{Text: "hi", Now: 1000})
	pane := m.ComposePane()
	if !pane.Shown {
		t.Fatal("pane not shown")
	}
	if pane.Geometry.Field.Left != 46 || pane.Geometry.Field.Width != 266 {
		t.Fatalf("pane field = %+v", pane.Geometry.Field)
	}
	if len(pane.Lines) != 1 || string(pane.Lines[0].Runes) != "hi" || pane.Lines[0].Width != 32 {
		t.Fatalf("pane lines = %+v", pane.Lines)
	}
	if pane.LineHeight != 32 || pane.Scroll != 0 {
		t.Fatalf("pane lineH %d scroll %d", pane.LineHeight, pane.Scroll)
	}
	if pane.Caret != (history.Geometry{Left: 32, Top: 0, Width: 1, Height: 32}) {
		t.Fatalf("pane caret = %+v", pane.Caret)
	}
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeLeft, Select: true})
	if pane = m.ComposePane(); len(pane.Selection) != 1 || pane.Selection[0] != (text.Span{Line: 0, From: 16, To: 32}) {
		t.Fatalf("pane selection = %+v", pane.Selection)
	}
	empty := composeModel(t, 400, 600)
	empty.ChatCompose.Placeholder = "Message"
	emptyPane := empty.ComposePane()
	if emptyPane.Placeholder.Text != "Message" || emptyPane.Placeholder.Baseline != 25.6 || emptyPane.Placeholder.X != 2 {
		t.Fatalf("empty pane placeholder = %+v, want baseline 25.6 (32*4/5)", emptyPane.Placeholder)
	}
	noPlaceholder := composeModel(t, 400, 600)
	if pane = noPlaceholder.ComposePane(); pane.Placeholder.Text != "" {
		t.Fatalf("no placeholder set = %q, want none", pane.Placeholder.Text)
	}
}

func TestChatComposePaneRidesView(t *testing.T) {
	m := composeModel(t, 400, 600)
	m, _ = Update(m, ChatComposeTyped{Text: "hi", Now: 1000})
	s := View(m)
	if !s.Chat.Compose.Shown || s.Chat.Compose.Geometry.Send.Left != 354 {
		t.Fatalf("view compose = %+v", s.Chat.Compose)
	}
	if s.Chat.Compose.Caret.Left != 32 {
		t.Fatalf("view caret = %+v", s.Chat.Compose.Caret)
	}
	hidden, _ := Update(InitialModel(), Resized{Width: 400, Height: 600})
	if s = View(hidden); s.Chat.Compose.Shown {
		t.Fatal("hidden compose rides view")
	}
}

func TestChatComposePaneScrollsAndCaps(t *testing.T) {
	m := composeModel(t, 400, 600)
	m = typeString(t, m, "a\nb\nc\nd\ne\nf\ng\nh\ni\nj")
	pane := m.ComposePane()
	if len(pane.Lines) != 10 || pane.Scroll != 96 {
		t.Fatalf("pane lines %d scroll %d, want 10/96", len(pane.Lines), pane.Scroll)
	}
	if pane.Caret.Top != 288 {
		t.Fatalf("pane caret top = %d, want 288 (line 9 absolute)", pane.Caret.Top)
	}
	if pane.Geometry.Field.Height != 224 {
		t.Fatalf("pane field height = %d, want 224", pane.Geometry.Field.Height)
	}
}
