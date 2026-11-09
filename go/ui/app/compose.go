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

	Focused              bool
	CursorOn             bool
	NextBlinkAt          int
	MousePressed         bool
	Grab                 bool
	LastClickSet         bool
	LastClickAt          int
	LastClickX           int
	LastClickY           int
	TrippleClickDeadline int
	TrippleClickX        int
	TrippleClickY        int
	WordSelActive        bool
	WordSelAnchor        int
	WordSelCursor        int
	BlockSelActive       bool
	BlockSelAnchor       int
	BlockSelCursor       int

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

type ChatComposePressed struct {
	X     int
	Y     int
	Shift bool
	Now   int
}

func (ChatComposePressed) isMsg() {}

type ChatComposeDragged struct {
	X   int
	Y   int
	Now int
}

func (ChatComposeDragged) isMsg() {}

type ChatComposeReleased struct {
	X   int
	Y   int
	Now int
}

func (ChatComposeReleased) isMsg() {}

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

func manhattan(ax, ay, bx, by int) int {
	d := ax - bx
	if d < 0 {
		d = -d
	}
	e := ay - by
	if e < 0 {
		e = -e
	}
	return d + e
}

func (m Model) composeFieldHitAt(x, y int) bool {
	if !m.ChatCompose.CanSend {
		return false
	}
	f := m.ComposeGeometry().Field
	return f.Width > 0 && f.Height > 0 &&
		x >= f.Left && x < f.Left+f.Width &&
		y >= f.Top && y < f.Top+f.Height
}

func (m Model) composeHitTest(x, y int) int {
	doc := m.composeDocument()
	g := m.ComposeGeometry()
	fy := y - g.Field.Top - tokens.ComposeTextMarginTop + m.ChatCompose.Scroll
	lineH := text.LineHeight(m.ChatCompose.Metrics.Height, tokens.ComposeFieldStyleLineHeight)
	line := fy / lineH
	if line < 0 {
		line = 0
	}
	if line >= len(doc.Lines) {
		line = len(doc.Lines) - 1
	}
	pos := doc.Lines[line].Start +
		doc.XToColumn(line, x-g.Field.Left-tokens.ComposeTextMarginLeft)
	if pos < 0 {
		return 0
	}
	if pos > len(doc.Text) {
		return len(doc.Text)
	}
	return pos
}

func (m *Model) composeSetGoalX(doc *text.Document) {
	c := &m.ChatCompose
	c.GoalX = doc.CursorAt(c.Cursor).X
	c.HasGoalX = true
}

func (m *Model) composePressed(msg ChatComposePressed) {
	if !m.ChatCompose.CanSend {
		return
	}
	m.nowMs = msg.Now
	c := &m.ChatCompose
	if !c.Focused {
		c.Focused = true
		c.CursorOn = true
		c.NextBlinkAt = msg.Now + tokens.CursorFlashTimeMs/2
	}
	doc := m.composeDocument()
	hit := m.composeHitTest(msg.X, msg.Y)
	prevAt, prevX, prevY, prevSet := c.LastClickAt, c.LastClickX, c.LastClickY, c.LastClickSet
	c.LastClickAt, c.LastClickX, c.LastClickY, c.LastClickSet = msg.Now, msg.X, msg.Y, true
	c.Grab = true
	if c.TrippleClickDeadline > 0 && msg.Now < c.TrippleClickDeadline &&
		manhattan(msg.X, msg.Y, c.TrippleClickX, c.TrippleClickY) < tokens.TouchDragStartDistance {
		end := doc.MoveEndOfBlock(c.Cursor)
		if end < len(doc.Text) {
			end++
		}
		c.Anchor = doc.MoveStartOfBlock(c.Cursor)
		c.Cursor = end
		c.BlockSelAnchor, c.BlockSelCursor, c.BlockSelActive = c.Anchor, end, true
		c.MousePressed = true
		c.TrippleClickDeadline = 0
		m.composeSetGoalX(doc)
		m.composeViewportSync()
		m.composeEnsureCursorVisible(doc)
		return
	}
	if prevSet && msg.Now-prevAt < tokens.MouseDoubleClickIntervalMs &&
		manhattan(msg.X, msg.Y, prevX, prevY) < tokens.TouchDragStartDistance {
		c.Anchor = hit
		c.Cursor = hit
		c.WordSelActive = false
		c.BlockSelActive = false
		c.MousePressed = false
		if line := doc.CursorAt(hit).Line; len(doc.Lines[line].Runes) > 0 {
			if ws, we := doc.MoveStartOfWord(hit), doc.MoveEndOfWord(hit); we > ws {
				c.Anchor, c.Cursor = ws, we
				c.WordSelAnchor, c.WordSelCursor, c.WordSelActive = ws, we, true
			}
		}
		c.TrippleClickDeadline = msg.Now + tokens.MouseDoubleClickIntervalMs
		c.TrippleClickX, c.TrippleClickY = msg.X, msg.Y
		m.composeSetGoalX(doc)
		return
	}
	if msg.Shift {
		switch {
		case c.BlockSelActive:
			m.composeExtendBlockwise(doc, hit)
		case c.WordSelActive:
			m.composeExtendWordwise(doc, hit, msg.X)
		default:
			c.Cursor = hit
		}
	} else {
		c.Cursor = hit
		c.Anchor = hit
		c.WordSelActive = false
		c.BlockSelActive = false
	}
	c.MousePressed = true
	m.composeSetGoalX(doc)
	m.composeViewportSync()
	m.composeEnsureCursorVisible(doc)
}

func (m *Model) composeExtendBlockwise(doc *text.Document, hit int) {
	c := &m.ChatCompose
	if hit >= c.BlockSelAnchor && hit <= c.BlockSelCursor {
		c.Anchor = c.BlockSelAnchor
		c.Cursor = c.BlockSelCursor
		return
	}
	if hit < c.BlockSelCursor {
		c.Anchor = c.BlockSelCursor
		c.Cursor = doc.MoveStartOfBlock(hit)
	} else {
		c.Anchor = c.BlockSelAnchor
		end := doc.MoveEndOfBlock(hit)
		if end < len(doc.Text) {
			end++
		}
		c.Cursor = end
	}
}

func (m *Model) composeExtendWordwise(doc *text.Document, hit, mouseX int) {
	c := &m.ChatCompose
	if hit >= c.WordSelAnchor && hit <= c.WordSelCursor {
		c.Anchor = c.WordSelAnchor
		c.Cursor = c.WordSelCursor
		return
	}
	ws := doc.MoveStartOfWord(hit)
	we := doc.MoveEndOfWord(hit)
	if ws == hit || we == hit || we == ws {
		return
	}
	if doc.CursorAt(ws).Line != doc.CursorAt(we).Line {
		return
	}
	g := m.ComposeGeometry()
	mx := mouseX - g.Field.Left - tokens.ComposeTextMarginLeft
	startX := doc.CursorAt(ws).X
	endX := doc.CursorAt(we).X
	if mx < startX || mx > endX {
		return
	}
	if hit < c.WordSelCursor {
		c.Anchor = c.WordSelCursor
	} else {
		c.Anchor = c.WordSelAnchor
	}
	if mx-startX < endX-mx {
		c.Cursor = ws
	} else {
		c.Cursor = we
	}
}

func (m *Model) composeDragged(msg ChatComposeDragged) {
	if !m.ChatCompose.CanSend {
		return
	}
	m.nowMs = msg.Now
	c := &m.ChatCompose
	doc := m.composeDocument()
	hit := m.composeHitTest(msg.X, msg.Y)
	switch {
	case c.BlockSelActive:
		m.composeExtendBlockwise(doc, hit)
	case c.WordSelActive:
		m.composeExtendWordwise(doc, hit, msg.X)
	case c.MousePressed:
		c.Cursor = hit
	}
	m.composeSetGoalX(doc)
}

func (m *Model) composeReleased(msg ChatComposeReleased) {
	m.nowMs = msg.Now
	m.ChatCompose.MousePressed = false
	m.ChatCompose.Grab = false
}

func (m *Model) composeBlinkTick(now int) {
	c := &m.ChatCompose
	if !c.Focused || now < c.NextBlinkAt {
		return
	}
	c.NextBlinkAt = now + tokens.CursorFlashTimeMs/2
	c.CursorOn = !c.CursorOn
	if c.Anchor != c.Cursor {
		c.CursorOn = false
	}
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
		CaretOn:    m.ChatCompose.CursorOn,
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
