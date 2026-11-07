package app

import (
	"image/color"
	"math"

	"uniclient/ui/dialogs"
	"uniclient/ui/material"
	"uniclient/ui/tokens"
)

type Msg interface{ isMsg() }

type Resized struct {
	Width  int
	Height int
}

func (Resized) isMsg() {}

type Quit struct{}

func (Quit) isMsg() {}

type DialogsLoaded struct {
	Rows []dialogs.Entry
}

func (DialogsLoaded) isMsg() {}

type DialogRowPressed struct {
	Index int
}

func (DialogRowPressed) isMsg() {}

type DialogsScrolled struct {
	DeltaY int
}

func (DialogsScrolled) isMsg() {}

type DialogsLoadMoreRequested struct{}

func (DialogsLoadMoreRequested) isMsg() {}

type DialogsWheel struct {
	AngleX     int
	AngleY     int
	Accelerate bool
}

func (DialogsWheel) isMsg() {}

type DialogsTrackpadScrolled struct {
	PixelX     int
	PixelY     int
	Accelerate bool
}

func (DialogsTrackpadScrolled) isMsg() {}

type DialogsPressed struct {
	X     int
	Y     int
	Touch bool
}

func (DialogsPressed) isMsg() {}

type DialogsDragged struct {
	X int
	Y int
}

func (DialogsDragged) isMsg() {}

type DialogsReleased struct {
	X int
	Y int
}

func (DialogsReleased) isMsg() {}

type DialogsPressCanceled struct{}

func (DialogsPressCanceled) isMsg() {}

type Cmd func() Msg

type TouchDrag struct {
	Active    bool
	StartX    int
	StartY    int
	LastY     int
	Scrolling bool
}

type BarDrag struct {
	Dragging bool
	LastY    int
}

type Model struct {
	Width         int
	Height        int
	HasDialogs    bool
	ThirdPane     bool
	Running       bool
	Dialogs       dialogs.List
	DialogsScroll dialogs.Viewport
	DialogsTouch  TouchDrag
	DialogsBar    BarDrag
}

func InitialModel() Model {
	return Model{HasDialogs: true, Running: true, Dialogs: dialogs.List{Selected: -1}}
}

func Update(m Model, msg Msg) (Model, Cmd) {
	switch msg := msg.(type) {
	case Resized:
		if msg.Width < 0 {
			msg.Width = 0
		}
		if msg.Height < 0 {
			msg.Height = 0
		}
		m.Width = msg.Width
		m.Height = msg.Height
		m.DialogsScroll.Height = msg.Height
		m.DialogsScroll.Top = m.clampDialogsScroll(m.DialogsScroll.Top)
		return m, m.loadMoreCmd()
	case Quit:
		m.Running = false
		return m, nil
	case DialogsLoaded:
		m.Dialogs.Rows = msg.Rows
		if m.Dialogs.Selected >= len(msg.Rows) {
			m.Dialogs.Selected = -1
		}
		m.DialogsScroll.Top = m.clampDialogsScroll(m.DialogsScroll.Top)
		return m, m.loadMoreCmd()
	case DialogRowPressed:
		if msg.Index >= 0 && msg.Index < len(m.Dialogs.Rows) {
			m.Dialogs.Selected = msg.Index
		}
		return m, nil
	case DialogsScrolled:
		m.DialogsScroll.Top = m.clampDialogsScroll(m.DialogsScroll.Top + msg.DeltaY)
		return m, m.loadMoreCmd()
	case DialogsWheel:
		dy := dialogs.WheelDelta(msg.AngleX, msg.AngleY, tokens.WheelScrollLines,
			m.Columns().Dialogs, m.DialogsScroll.Height, msg.Accelerate)
		m.DialogsScroll.Top = m.clampDialogsScroll(m.DialogsScroll.Top + dy)
		return m, m.loadMoreCmd()
	case DialogsTrackpadScrolled:
		dy := dialogs.ScrollPixels(msg.PixelX, msg.PixelY,
			m.Columns().Dialogs, m.DialogsScroll.Height, msg.Accelerate)
		m.DialogsScroll.Top = m.clampDialogsScroll(m.DialogsScroll.Top + dy)
		return m, m.loadMoreCmd()
	case DialogsPressed:
		return m.pressDialogs(msg), nil
	case DialogsDragged:
		return m.dragDialogs(msg), nil
	case DialogsReleased:
		m.releaseDialogs(msg)
		return m, nil
	case DialogsPressCanceled:
		m.DialogsBar = BarDrag{}
		m.DialogsTouch = TouchDrag{}
		return m, nil
	case DialogsLoadMoreRequested:
		return m, nil
	}
	return m, nil
}

func (m *Model) pressDialogs(msg DialogsPressed) Model {
	width := m.Columns().Dialogs
	if width > tokens.ScrollBarWidth && msg.X >= width-tokens.ScrollBarWidth {
		thumb := m.Dialogs.ScrollbarThumb(m.DialogsScroll, width, m.DialogsScroll.Height)
		if !thumb.Hidden {
			m.DialogsBar = BarDrag{Dragging: true, LastY: msg.Y}
			if !dialogs.BarOver(thumb, msg.X-(width-tokens.ScrollBarWidth), msg.Y) {
				m.DialogsScroll.Top = m.clampDialogsScroll(
					m.Dialogs.BarTrackJump(m.DialogsScroll, width, m.DialogsScroll.Height, msg.Y))
			}
			return *m
		}
	}
	if msg.Touch {
		m.DialogsTouch = TouchDrag{Active: true, StartX: msg.X, StartY: msg.Y, LastY: msg.Y}
		return *m
	}
	if idx := m.Dialogs.RowAt(msg.Y+m.DialogsScroll.Top, width); idx >= 0 {
		m.Dialogs.Selected = idx
	}
	return *m
}

func (m *Model) dragDialogs(msg DialogsDragged) Model {
	if m.DialogsBar.Dragging {
		dy := msg.Y - m.DialogsBar.LastY
		m.DialogsBar.LastY = msg.Y
		m.DialogsScroll.Top = m.clampDialogsScroll(
			m.DialogsScroll.Top + m.Dialogs.BarDragScale(
				m.DialogsScroll, m.Columns().Dialogs, m.DialogsScroll.Height, dy))
		return *m
	}
	if m.DialogsTouch.Active {
		d := m.DialogsTouch
		if !d.Scrolling && absInt(msg.X-d.StartX)+absInt(msg.Y-d.StartY) >= tokens.TouchDragStartDistance {
			d.Scrolling = true
		}
		if d.Scrolling {
			m.DialogsScroll.Top = m.clampDialogsScroll(m.DialogsScroll.Top - (msg.Y - d.LastY))
		}
		d.LastY = msg.Y
		m.DialogsTouch = d
	}
	return *m
}

func (m *Model) releaseDialogs(msg DialogsReleased) {
	m.DialogsBar = BarDrag{}
	if m.DialogsTouch.Active {
		tap := !m.DialogsTouch.Scrolling
		m.DialogsTouch = TouchDrag{}
		if tap {
			if idx := m.Dialogs.RowAt(msg.Y+m.DialogsScroll.Top, m.Columns().Dialogs); idx >= 0 {
				m.Dialogs.Selected = idx
			}
		}
	}
}

func absInt(v int) int {
	if v < 0 {
		return -v
	}
	return v
}

func (m Model) clampDialogsScroll(top int) int {
	return m.Dialogs.ClampOffset(top, m.Columns().Dialogs, m.DialogsScroll.Height)
}

func (m Model) loadMoreCmd() Cmd {
	if !m.Dialogs.LoadMoreNeeded(m.DialogsScroll, m.Columns().Dialogs) {
		return nil
	}
	return func() Msg { return DialogsLoadMoreRequested{} }
}

type PaneMode int

const (
	PaneSingle PaneMode = iota
	PaneDouble
	PaneTriple
)

type Columns struct {
	Dialogs int
	Chat    int
	Third   int
}

func (m Model) PaneMode() PaneMode {
	if m.HasDialogs && m.Width < tokens.LayoutOneColumnMaxWidth {
		return PaneSingle
	}
	if m.Width < m.minimalThreeColumnWidth() || !m.ThirdPane {
		return PaneDouble
	}
	return PaneTriple
}

func (m Model) Columns() Columns {
	switch m.PaneMode() {
	case PaneSingle:
		return Columns{Dialogs: m.Width, Chat: m.Width}
	case PaneDouble:
		dialogs := m.dialogsWidthFromRatio()
		if max := m.Width - tokens.ColumnMinWidthMain; dialogs > max {
			dialogs = max
		}
		return Columns{Dialogs: dialogs, Chat: m.Width - dialogs}
	default:
		dialogs := m.dialogsWidthFromRatio()
		third := m.thirdWidth()
		dialogs, third = m.shrinkDialogsAndThird(dialogs, third)
		return Columns{Dialogs: dialogs, Chat: m.Width - dialogs - third, Third: third}
	}
}

func (m Model) minimalThreeColumnWidth() int {
	left := 0
	if m.HasDialogs {
		left = tokens.ColumnMinWidthLeft
	}
	return left + tokens.ColumnMinWidthMain + tokens.ColumnMinWidthThird
}

func (m Model) dialogsWidthFromRatio() int {
	if !m.HasDialogs {
		return 0
	}
	w := int(math.Round(float64(m.Width) * tokens.DialogsWidthRatioDefault))
	if w < tokens.ColumnMinWidthLeft {
		w = tokens.ColumnMinWidthLeft
	}
	return w
}

func (m Model) thirdWidth() int {
	w := tokens.ThirdColumnWidthDefault
	if w < tokens.ColumnMinWidthThird {
		w = tokens.ColumnMinWidthThird
	}
	if w > tokens.ColumnMaxWidthThird {
		w = tokens.ColumnMaxWidthThird
	}
	return w
}

func (m Model) shrinkDialogsAndThird(dialogs, third int) (int, int) {
	chat := tokens.ColumnMinWidthMain
	if dialogs+third+chat <= m.Width {
		return dialogs, third
	}
	thirdNew := (m.Width - chat) * third / (dialogs + third)
	dialogsNew := (m.Width - chat) * dialogs / (dialogs + third)
	if thirdNew < tokens.ColumnMinWidthThird {
		thirdNew = tokens.ColumnMinWidthThird
		dialogsNew = m.Width - thirdNew - chat
	} else if m.HasDialogs && dialogsNew < tokens.ColumnMinWidthLeft {
		dialogsNew = tokens.ColumnMinWidthLeft
		thirdNew = m.Width - dialogsNew - chat
	}
	return dialogsNew, thirdNew
}

type Scene struct {
	Background color.NRGBA
	Dialogs    dialogs.Pane
}

func View(m Model) Scene {
	s := Scene{Background: material.SchemeFor(material.Light).Surface}
	if m.HasDialogs {
		s.Dialogs = m.Dialogs.Pane(m.DialogsScroll, m.Columns().Dialogs)
	}
	return s
}
