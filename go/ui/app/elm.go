package app

import (
	"image/color"
	"math"

	"uniclient/ui/dialogs"
	"uniclient/ui/history"
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
	Now        int
}

func (DialogsWheel) isMsg() {}

type DialogsTrackpadScrolled struct {
	PixelX     int
	PixelY     int
	Accelerate bool
	Now        int
}

func (DialogsTrackpadScrolled) isMsg() {}

type DialogsPressed struct {
	X     int
	Y     int
	Touch bool
	Now   int
}

func (DialogsPressed) isMsg() {}

type DialogsDragged struct {
	X   int
	Y   int
	Now int
}

func (DialogsDragged) isMsg() {}

type DialogsReleased struct {
	X   int
	Y   int
	Now int
}

func (DialogsReleased) isMsg() {}

type DialogsPressCanceled struct{}

func (DialogsPressCanceled) isMsg() {}

type DialogsTick struct {
	Now int
}

func (DialogsTick) isMsg() {}

type ChatLoaded struct {
	Items []history.Item
}

func (ChatLoaded) isMsg() {}

type ChatMeasured struct {
	Heights []int
}

func (ChatMeasured) isMsg() {}

type ChatScrolled struct {
	DeltaY int
}

func (ChatScrolled) isMsg() {}

type Cmd func() Msg

type TouchDrag struct {
	Active              bool
	StartX              int
	StartY              int
	LastX               int
	LastY               int
	Scrolling           bool
	PrevValid           bool
	Speed               dialogs.TouchSpeed
	SpeedTime           int
	State               int
	WaitingAcceleration bool
	AccelerationTime    int
	TouchTime           int
}

type BarDrag struct {
	Dragging bool
	LastY    int
}

type Model struct {
	Width             int
	Height            int
	HasDialogs        bool
	ThirdPane         bool
	Running           bool
	Dialogs           dialogs.List
	DialogsScroll     dialogs.Viewport
	DialogsTouch      TouchDrag
	DialogsBar        BarDrag
	DialogsOverscroll dialogs.Overscroll
	Chat              history.List
	ChatScroll        history.Viewport
	ChatDirty         bool
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
		m.ChatScroll.Height = msg.Height
		m.ChatScroll.Top = m.Chat.ClampOffset(m.ChatScroll.Top, m.ChatScroll)
		m.ChatDirty = true
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
		return m.scrollClassic(dy, msg.Now), m.loadMoreCmd()
	case DialogsTrackpadScrolled:
		dy := dialogs.ScrollPixels(msg.PixelX, msg.PixelY,
			m.Columns().Dialogs, m.DialogsScroll.Height, msg.Accelerate)
		return m.scrollClassic(dy, msg.Now), m.loadMoreCmd()
	case DialogsPressed:
		return m.pressDialogs(msg), nil
	case DialogsDragged:
		return m.dragDialogs(msg), m.loadMoreCmd()
	case DialogsReleased:
		m.releaseDialogs(msg)
		return m, nil
	case DialogsPressCanceled:
		m.DialogsBar = BarDrag{}
		m.DialogsTouch.Active = false
		m.DialogsTouch.Scrolling = false
		m.DialogsTouch.State = dialogs.TouchScrollManual
		return m, nil
	case DialogsTick:
		m.dialogsTick(msg.Now)
		return m, m.loadMoreCmd()
	case DialogsLoadMoreRequested:
		return m, nil
	case ChatLoaded:
		m.Chat.Items = msg.Items
		m.Chat.Heights = nil
		m.ChatDirty = true
		m.ChatScroll.Top = m.Chat.ClampOffset(m.ChatScroll.Top, m.ChatScroll)
		return m, nil
	case ChatMeasured:
		m.Chat.Heights = msg.Heights
		m.ChatDirty = false
		m.ChatScroll.Top = m.Chat.ClampOffset(m.ChatScroll.Top, m.ChatScroll)
		return m, nil
	case ChatScrolled:
		m.ChatScroll.Top = m.Chat.ClampOffset(m.ChatScroll.Top+msg.DeltaY, m.ChatScroll)
		return m, nil
	}
	return m, nil
}

func (m *Model) scrollClassic(dy, now int) Model {
	if m.DialogsOverscroll.Stretch == 0 {
		m.DialogsScroll.Top = m.clampDialogsScroll(m.DialogsScroll.Top + dy)
		return *m
	}
	if !m.DialogsOverscroll.Animating(now) {
		m.DialogsOverscroll.Return(now)
	}
	return *m
}

func (m *Model) pressDialogs(msg DialogsPressed) Model {
	width := m.Columns().Dialogs
	if !msg.Touch && width > tokens.ScrollBarWidth && msg.X >= width-tokens.ScrollBarWidth {
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
		d := m.DialogsTouch
		d.Active = true
		d.StartX, d.StartY = msg.X, msg.Y
		d.LastX, d.LastY = msg.X, msg.Y
		if d.State == dialogs.TouchScrollAuto {
			d.State = dialogs.TouchScrollAcceleration
			d.WaitingAcceleration = true
			d.AccelerationTime = msg.Now
			d.PrevValid = true
			d.SpeedTime = msg.Now
		} else {
			d = TouchDrag{Active: true, StartX: msg.X, StartY: msg.Y, LastX: msg.X, LastY: msg.Y, State: dialogs.TouchScrollManual}
		}
		m.DialogsTouch = d
		m.applyTouchDelta(0, 0, dialogs.PhaseBegin, msg.Now)
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
	d := m.DialogsTouch
	if !d.Active {
		return *m
	}
	now := msg.Now
	dx, dy := msg.X-d.LastX, msg.Y-d.LastY
	if !d.Scrolling && absInt(msg.X-d.StartX)+absInt(msg.Y-d.StartY) >= tokens.TouchDragStartDistance {
		d.Scrolling = true
		d = sampleTouchSpeed(d, msg.X, msg.Y, now)
		dx, dy = 0, 0
	}
	if d.Scrolling {
		if d.State == dialogs.TouchScrollManual {
			m.applyTouchDelta(dx, dy, dialogs.PhaseUpdate, now)
			d = sampleTouchSpeed(d, msg.X, msg.Y, now)
		} else if d.State == dialogs.TouchScrollAcceleration {
			d = sampleTouchSpeed(d, msg.X, msg.Y, now)
			d.AccelerationTime = now
			if d.Speed == (dialogs.TouchSpeed{}) {
				d.State = dialogs.TouchScrollManual
			}
		}
	} else {
		d.LastX, d.LastY = msg.X, msg.Y
	}
	m.DialogsTouch = d
	return *m
}

func sampleTouchSpeed(d TouchDrag, x, y, now int) TouchDrag {
	if d.PrevValid {
		elapsed := now - d.SpeedTime
		if elapsed != 0 {
			d.Speed = dialogs.TouchSpeedSample(d.Speed, x-d.LastX, y-d.LastY, elapsed,
				d.State != dialogs.TouchScrollManual)
		}
	} else {
		d.PrevValid = true
	}
	d.SpeedTime = now
	d.LastX, d.LastY = x, y
	return d
}

func (m *Model) releaseDialogs(msg DialogsReleased) {
	m.DialogsBar = BarDrag{}
	if !m.DialogsTouch.Active {
		return
	}
	tap := !m.DialogsTouch.Scrolling
	if m.DialogsTouch.Scrolling {
		switch m.DialogsTouch.State {
		case dialogs.TouchScrollManual:
			m.DialogsTouch.State = dialogs.TouchScrollAuto
			m.DialogsTouch.PrevValid = false
			m.DialogsTouch.TouchTime = msg.Now
		case dialogs.TouchScrollAcceleration:
			m.DialogsTouch.State = dialogs.TouchScrollAuto
			m.DialogsTouch.WaitingAcceleration = false
			m.DialogsTouch.PrevValid = false
		}
	}
	m.DialogsTouch.Active = false
	if tap {
		m.DialogsTouch = TouchDrag{}
		if idx := m.Dialogs.RowAt(msg.Y+m.DialogsScroll.Top, m.Columns().Dialogs); idx >= 0 {
			m.Dialogs.Selected = idx
		}
	}
}

func (m *Model) dialogsTick(now int) {
	d := m.DialogsTouch
	if d.State == dialogs.TouchScrollAuto || d.State == dialogs.TouchScrollAcceleration {
		if d.State == dialogs.TouchScrollAcceleration && d.WaitingAcceleration &&
			now-d.AccelerationTime > tokens.TouchAccelerationTimeoutMs {
			d.State = dialogs.TouchScrollManual
			m.applyTouchDelta(0, 0, dialogs.PhaseEnd, now)
			d.Speed = dialogs.TouchSpeed{}
			d.PrevValid = false
		} else {
			elapsed := now - d.TouchTime
			if elapsed > 0 {
				dx, dy := dialogs.FlingDelta(d.Speed, elapsed)
				phase := dialogs.PhaseMomentum
				if d.Active {
					phase = dialogs.PhaseUpdate
				}
				m.applyTouchDelta(dx, dy, phase, now)
				if d.Speed == (dialogs.TouchSpeed{}) {
					d.State = dialogs.TouchScrollManual
					m.applyTouchDelta(0, 0, dialogs.PhaseEnd, now)
					d.Scrolling = false
				} else {
					d.TouchTime = now
				}
				d.Speed = dialogs.TouchDeaccelerate(d.Speed, elapsed)
			}
		}
		m.DialogsTouch = d
	}
	if m.DialogsOverscroll.Returning && now > m.DialogsOverscroll.ReturnStart {
		m.DialogsScroll.Top = m.DialogsOverscroll.SpringUpdate(
			m.DialogsScroll.Top, m.dialogsMaxOffset(), now)
	}
}

func (m *Model) applyTouchDelta(dx, dy int, phase dialogs.Phase, now int) {
	d := dialogs.ScrollPixels(dx, dy, 0, 0, false)
	m.DialogsScroll.Top = m.DialogsOverscroll.ApplyInput(
		m.DialogsScroll.Top, m.dialogsMaxOffset(), d, phase, true, now, now)
}

func (m Model) dialogsMaxOffset() int {
	return m.Dialogs.MaxOffset(m.Columns().Dialogs, m.DialogsScroll.Height)
}

func (m Model) KineticActive() bool {
	return m.DialogsTouch.State != dialogs.TouchScrollManual || m.DialogsOverscroll.Returning
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
	Chat       history.ChatPane
}

func View(m Model) Scene {
	s := Scene{Background: material.SchemeFor(material.Light).Surface}
	if m.HasDialogs {
		s.Dialogs = m.Dialogs.Pane(m.DialogsScroll, m.Columns().Dialogs)
	}
	s.Chat = m.Chat.Pane(m.ChatScroll, m.Columns().Chat)
	return s
}
