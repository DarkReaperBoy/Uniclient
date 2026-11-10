package app

import (
	"unicode/utf8"

	"uniclient/ui/dialogs"
	"uniclient/ui/tokens"
)

type SearchState struct {
	Text        string
	Cursor      int
	Focused     bool
	CursorOn    bool
	NextBlinkAt int
	Placeholder string
}

type DialogsHeaderPressed struct {
	X   int
	Y   int
	Now int
}

func (DialogsHeaderPressed) isMsg() {}

type SearchTyped struct {
	Text string
	Now  int
}

func (SearchTyped) isMsg() {}

type SearchBackspace struct {
	Now int
}

func (SearchBackspace) isMsg() {}

type SearchFocusLost struct{}

func (SearchFocusLost) isMsg() {}

func (m *Model) searchFocus(now int) {
	m.Search.Focused = true
	m.Search.CursorOn = true
	m.Search.NextBlinkAt = now + tokens.CursorFlashTimeMs/2
	m.ChatCompose.Focused = false
	m.ChatCompose.CursorOn = false
}

func (m *Model) searchBlur() {
	m.Search.Focused = false
	m.Search.CursorOn = false
}

func (m *Model) pressDialogsHeader(msg DialogsHeaderPressed) {
	m.nowMs = msg.Now
	if dialogs.HeaderFieldHit(m.Columns().Dialogs, msg.X, msg.Y) {
		m.searchFocus(msg.Now)
		return
	}
	m.searchBlur()
}

func (m *Model) searchTyped(msg SearchTyped) {
	m.nowMs = msg.Now
	m.Search.Text = m.Search.Text[:m.Search.Cursor] + msg.Text + m.Search.Text[m.Search.Cursor:]
	m.Search.Cursor += len(msg.Text)
	m.reprojectDialogRows()
}

func (m *Model) searchBackspace(msg SearchBackspace) {
	m.nowMs = msg.Now
	if m.Search.Cursor == 0 {
		return
	}
	_, size := utf8.DecodeLastRuneInString(m.Search.Text[:m.Search.Cursor])
	m.Search.Text = m.Search.Text[:m.Search.Cursor-size] + m.Search.Text[m.Search.Cursor:]
	m.Search.Cursor -= size
	m.reprojectDialogRows()
}

func (m *Model) searchBlinkTick(now int) {
	if !m.Search.Focused || now < m.Search.NextBlinkAt {
		return
	}
	m.Search.NextBlinkAt = now + tokens.CursorFlashTimeMs/2
	m.Search.CursorOn = !m.Search.CursorOn
}

func (m Model) SearchBlinkActive() bool {
	return m.Search.Focused
}
