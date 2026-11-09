package app

import (
	"uniclient/ui/history"
	"uniclient/ui/text"
	"uniclient/ui/tokens"
)

type ChatComposeState struct {
	CanSend  bool
	Text     string
	Cursor   int
	Anchor   int
	Scroll   int
	GoalX    int
	HasGoalX bool
	Metrics  text.Metrics

	Placeholder        string
	PlaceholderShifted bool
	PlaceholderDegree  float64
	PlaceholderFrom    float64
	PlaceholderTo      float64
	PlaceholderStarted int
	PlaceholderAnim    bool
}

type ChatComposeDir uint8

const (
	ComposeLeft ChatComposeDir = iota
	ComposeRight
	ComposeUp
	ComposeDown
	ComposeHome
	ComposeEnd
	ComposeDocHome
	ComposeDocEnd
	ComposeWordLeft
	ComposeWordRight
)

type ChatComposeTyped struct {
	Text string
	Now  int
}

func (ChatComposeTyped) isMsg() {}

type ChatComposeBackspace struct {
	Word bool
	Now  int
}

func (ChatComposeBackspace) isMsg() {}

type ChatComposeDelete struct {
	Word bool
	Now  int
}

func (ChatComposeDelete) isMsg() {}

type ChatComposeCursorKey struct {
	Dir    ChatComposeDir
	Select bool
}

func (ChatComposeCursorKey) isMsg() {}

type ChatComposeSelectAll struct{}

func (ChatComposeSelectAll) isMsg() {}

func (m Model) composeButtons() history.ComposeButtons {
	return history.ComposeButtons{Attach: true, Emoji: true}
}

func (m Model) composeDocument() *text.Document {
	w := history.ComposeFieldWidth(m.Columns().Chat, m.composeButtons())
	return history.ComposeFieldDocument(m.ChatCompose.Text, w, m.ChatCompose.Metrics)
}

func (m Model) ComposeFieldHeight() int {
	if !m.ChatCompose.CanSend {
		return history.ComposeFieldHeight(false, 0, 0)
	}
	lineH := text.LineHeight(m.ChatCompose.Metrics.Height, tokens.ComposeFieldStyleLineHeight)
	content := m.composeDocument().Height(lineH)
	max := history.ComposeFieldMaxHeight(m.Height, 0, false)
	return history.ComposeFieldHeight(true, content, max)
}

func (m Model) ComposeGeometry() history.ComposeBar {
	return history.ComposeBarGeometry(m.Columns().Chat, m.Height, m.ComposeFieldHeight(), m.composeButtons())
}

func (m Model) composeViewportHeight() int {
	return history.ComposeScrollHeight(m.Height, m.ComposeFieldHeight(), m.ChatCompose.CanSend)
}

func (m *Model) composeViewportSync() {
	oldViewport := history.Viewport{Top: m.ChatScroll.Top, Height: m.ChatScroll.Height}
	wasAtBottom := m.ChatScroll.Top >= m.Chat.MaxOffset(oldViewport)
	m.ChatScroll.Height = m.composeViewportHeight()
	if wasAtBottom {
		m.ChatScroll.Top = m.Chat.MaxOffset(m.ChatScroll)
	} else {
		m.ChatScroll.Top = m.Chat.ClampOffset(m.ChatScroll.Top, m.ChatScroll)
	}
}

func (m *Model) composeEnsureCursorVisible(doc *text.Document) {
	if !m.ChatCompose.CanSend {
		return
	}
	rect := history.ComposeCursorRect(doc, m.ChatCompose.Cursor, m.ChatCompose.Metrics)
	lineH := text.LineHeight(m.ChatCompose.Metrics.Height, tokens.ComposeFieldStyleLineHeight)
	m.ChatCompose.Scroll = history.ComposeFieldScrollOffset(
		m.ChatCompose.Scroll, doc.Height(lineH), m.ComposeFieldHeight(), rect.Top, rect.Height)
}

func (m *Model) composeEdit(newText string, newCursor int) {
	m.ChatCompose.Text = newText
	m.ChatCompose.Cursor = newCursor
	m.ChatCompose.Anchor = newCursor
	m.ChatCompose.HasGoalX = false
	m.composeViewportSync()
	m.composeEnsureCursorVisible(m.composeDocument())
	m.composePlaceholderCheck()
}

func (m *Model) composePlaceholderCheck() {
	shifted := len([]rune(m.ChatCompose.Text)) > 0
	if shifted == m.ChatCompose.PlaceholderShifted {
		return
	}
	m.ChatCompose.PlaceholderShifted = shifted
	m.ChatCompose.PlaceholderFrom = m.ChatCompose.PlaceholderDegree
	m.ChatCompose.PlaceholderTo = 0
	if shifted {
		m.ChatCompose.PlaceholderTo = 1
	}
	m.ChatCompose.PlaceholderStarted = m.nowMs
	m.ChatCompose.PlaceholderAnim = true
}

func (m *Model) composePlaceholderTick(now int) {
	if !m.ChatCompose.PlaceholderAnim {
		return
	}
	elapsed := now - m.ChatCompose.PlaceholderStarted
	if elapsed >= tokens.ComposeAnimDurationMs {
		m.ChatCompose.PlaceholderDegree = m.ChatCompose.PlaceholderTo
		m.ChatCompose.PlaceholderAnim = false
	} else if elapsed >= 0 {
		t := float64(elapsed) / float64(tokens.ComposeAnimDurationMs)
		m.ChatCompose.PlaceholderDegree = m.ChatCompose.PlaceholderFrom +
			(m.ChatCompose.PlaceholderTo-m.ChatCompose.PlaceholderFrom)*t
	}
}

func (m *Model) composeTyped(msg ChatComposeTyped) {
	if !m.ChatCompose.CanSend {
		return
	}
	m.nowMs = msg.Now
	newText, newCursor := m.composeDocument().InsertAt(m.ChatCompose.Cursor, m.ChatCompose.Anchor, msg.Text)
	m.composeEdit(newText, newCursor)
}

func (m *Model) composeBackspace(msg ChatComposeBackspace) {
	if !m.ChatCompose.CanSend {
		return
	}
	m.nowMs = msg.Now
	var newText string
	var newCursor int
	if msg.Word {
		newText, newCursor = m.composeDocument().DeleteWordBackward(m.ChatCompose.Cursor, m.ChatCompose.Anchor)
	} else {
		newText, newCursor = m.composeDocument().DeleteBackward(m.ChatCompose.Cursor, m.ChatCompose.Anchor)
	}
	m.composeEdit(newText, newCursor)
}

func (m *Model) composeDelete(msg ChatComposeDelete) {
	if !m.ChatCompose.CanSend {
		return
	}
	m.nowMs = msg.Now
	var newText string
	var newCursor int
	if msg.Word {
		newText, newCursor = m.composeDocument().DeleteWordForward(m.ChatCompose.Cursor, m.ChatCompose.Anchor)
	} else {
		newText, newCursor = m.composeDocument().DeleteForward(m.ChatCompose.Cursor, m.ChatCompose.Anchor)
	}
	m.composeEdit(newText, newCursor)
}

func (m *Model) composeCursorKey(msg ChatComposeCursorKey) {
	if !m.ChatCompose.CanSend {
		return
	}
	c := &m.ChatCompose
	doc := m.composeDocument()
	newPos := c.Cursor
	vertical := false
	switch msg.Dir {
	case ComposeLeft:
		if msg.Select {
			newPos = doc.MoveLeft(c.Cursor, c.Cursor)
		} else {
			newPos = doc.MoveLeft(c.Cursor, c.Anchor)
		}
	case ComposeRight:
		if msg.Select {
			newPos = doc.MoveRight(c.Cursor, c.Cursor)
		} else {
			newPos = doc.MoveRight(c.Cursor, c.Anchor)
		}
	case ComposeHome:
		newPos = doc.MoveStartOfLine(c.Cursor)
	case ComposeEnd:
		newPos = doc.MoveEndOfLine(c.Cursor)
	case ComposeDocHome:
		newPos = doc.MoveHome()
	case ComposeDocEnd:
		newPos = doc.MoveEnd()
	case ComposeWordLeft:
		newPos = doc.MoveWordLeft(c.Cursor)
	case ComposeWordRight:
		newPos = doc.MoveWordRight(c.Cursor)
	case ComposeUp, ComposeDown:
		vertical = true
		newPos, c.GoalX = doc.MoveVertical(c.Cursor, c.GoalX, c.HasGoalX, msg.Dir == ComposeUp)
		c.HasGoalX = true
	}
	if !vertical {
		c.GoalX = doc.CursorAt(newPos).X
		c.HasGoalX = true
	}
	c.Cursor = newPos
	if !msg.Select {
		c.Anchor = newPos
	}
	m.composeViewportSync()
	m.composeEnsureCursorVisible(doc)
}

func (m *Model) composeSelectAll() {
	if !m.ChatCompose.CanSend {
		return
	}
	m.ChatCompose.Anchor = 0
	m.ChatCompose.Cursor = len([]rune(m.ChatCompose.Text))
}

func (m Model) ComposePane() history.ComposePaneView {
	if !m.ChatCompose.CanSend {
		return history.ComposePaneView{}
	}
	doc := m.composeDocument()
	lineH := text.LineHeight(m.ChatCompose.Metrics.Height, tokens.ComposeFieldStyleLineHeight)
	pane := history.ComposePaneView{
		Shown:      true,
		Geometry:   m.ComposeGeometry(),
		LineHeight: lineH,
		Scroll:     m.ChatCompose.Scroll,
		Lines:      doc.Lines,
		Caret:      history.ComposeCursorRect(doc, m.ChatCompose.Cursor, m.ChatCompose.Metrics),
		Selection:  doc.SelectionSpans(text.Selection{Anchor: m.ChatCompose.Anchor, Position: m.ChatCompose.Cursor}),
	}
	if m.ChatCompose.Placeholder != "" && m.ChatCompose.PlaceholderDegree < 1 {
		pane.Placeholder = history.ComposePlaceholderView{
			Text:     string(history.ComposePlaceholderText(m.ChatCompose.Placeholder, pane.Geometry.Field.Width, m.ChatCompose.Metrics)),
			X:        history.ComposePlaceholderX(m.ChatCompose.PlaceholderDegree),
			Baseline: history.ComposePlaceholderBaseline(m.ChatCompose.Metrics),
			Opacity:  history.ComposePlaceholderOpacity(m.ChatCompose.PlaceholderDegree),
		}
	}
	return pane
}
