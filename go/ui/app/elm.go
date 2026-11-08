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
	Hits    []history.HitBox
}

func (ChatMeasured) isMsg() {}

type ChatScrolled struct {
	DeltaY int
}

func (ChatScrolled) isMsg() {}

type ChatWheel struct {
	AngleX     int
	AngleY     int
	Accelerate bool
	Now        int
	Y          int
}

func (ChatWheel) isMsg() {}

type ChatTrackpadScrolled struct {
	PixelX     int
	PixelY     int
	Accelerate bool
	Now        int
	Y          int
}

func (ChatTrackpadScrolled) isMsg() {}

type ChatPressed struct {
	X     int
	Y     int
	Touch bool
	Now   int
}

func (ChatPressed) isMsg() {}

type ChatDragged struct {
	X   int
	Y   int
	Now int
}

func (ChatDragged) isMsg() {}

type ChatReleased struct {
	X   int
	Y   int
	Now int
}

func (ChatReleased) isMsg() {}

type ChatPressCanceled struct{}

func (ChatPressCanceled) isMsg() {}

type ChatTick struct {
	Now int
}

func (ChatTick) isMsg() {}

type ChatBottomRequested struct{}

func (ChatBottomRequested) isMsg() {}

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
	Dragging   bool
	LastY      int
	Overscroll int
}

type ChatPressAction uint8

const (
	ChatPressNone ChatPressAction = iota
	ChatPressPrepareSelect
	ChatPressPrepareDrag
	ChatPressSelecting
	ChatPressDragging
)

type ChatPressState struct {
	Row    int
	X      int
	Y      int
	Inside bool
	Time   bool
	Action ChatPressAction
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
	ChatTouch         TouchDrag
	ChatBar           BarDrag
	ChatDirty         bool
	ChatSelection     history.Selection
	ChatPress         ChatPressState
}

func InitialModel() Model {
	return Model{HasDialogs: true, Running: true,
		Dialogs:   dialogs.List{Selected: -1},
		ChatPress: ChatPressState{Row: -1}}
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
		m.Chat.Hits = nil
		m.ChatSelection = nil
		m.ChatDirty = true
		m.ChatScroll.Top = m.Chat.ClampOffset(m.ChatScroll.Top, m.ChatScroll)
		return m, nil
	case ChatMeasured:
		m.Chat.Heights = msg.Heights
		m.Chat.Hits = msg.Hits
		m.ChatDirty = false
		m.ChatScroll.Top = m.Chat.ClampOffset(m.ChatScroll.Top, m.ChatScroll)
		return m, nil
	case ChatScrolled:
		m.ChatScroll.Top = m.Chat.ClampOffset(m.ChatScroll.Top+msg.DeltaY, m.ChatScroll)
		return m, nil
	case ChatWheel:
		return m.chatWheel(msg)
	case ChatTrackpadScrolled:
		return m.chatTrackpad(msg)
	case ChatPressed:
		return m.pressChat(msg), nil
	case ChatDragged:
		return m.dragChat(msg), nil
	case ChatReleased:
		m.releaseChat(msg)
		return m, nil
	case ChatPressCanceled:
		m.ChatBar = BarDrag{}
		m.ChatTouch = TouchDrag{}
		m.ChatPress = ChatPressState{Row: -1}
		return m, nil
	case ChatTick:
		m.chatTick(msg.Now)
		return m, nil
	case ChatBottomRequested:
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
				d.State == dialogs.TouchScrollAuto)
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
	return m.DialogsTouch.State != dialogs.TouchScrollManual ||
		m.DialogsOverscroll.Returning ||
		m.ChatTouch.State != dialogs.TouchScrollManual
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

func (m *Model) chatScrollClassic(dy int) (Model, Cmd) {
	var cmd Cmd
	if history.ChatBottomRequest(m.ChatScroll.Top, dy, m.Chat.MaxOffset(m.ChatScroll)) {
		cmd = func() Msg { return ChatBottomRequested{} }
	}
	m.ChatScroll.Top = m.Chat.ClampOffset(m.ChatScroll.Top+dy, m.ChatScroll)
	return *m, cmd
}

func (m *Model) chatWheel(msg ChatWheel) (Model, Cmd) {
	rawX, rawY := dialogs.WheelScaled(msg.AngleX, msg.AngleY, tokens.WheelScrollLines)
	if absInt(rawX) > absInt(rawY) &&
		m.Chat.ConsumeScrollAction(rawX, rawY, true, msg.Y+m.ChatScroll.Top) {
		return *m, nil
	}
	dy := dialogs.WheelDelta(msg.AngleX, msg.AngleY, tokens.WheelScrollLines,
		m.Columns().Chat, m.ChatScroll.Height, msg.Accelerate)
	return m.chatScrollClassic(dy)
}

func (m *Model) chatTrackpad(msg ChatTrackpadScrolled) (Model, Cmd) {
	if absInt(msg.PixelX) > absInt(msg.PixelY) &&
		m.Chat.ConsumeScrollAction(msg.PixelX, msg.PixelY, true, msg.Y+m.ChatScroll.Top) {
		return *m, nil
	}
	dy := dialogs.ScrollPixels(msg.PixelX, msg.PixelY,
		m.Columns().Chat, m.ChatScroll.Height, msg.Accelerate)
	return m.chatScrollClassic(dy)
}

func (m *Model) chatTouchScroll(dy int) bool {
	to := m.Chat.ClampOffset(m.ChatScroll.Top-dy, m.ChatScroll)
	moved := to != m.ChatScroll.Top
	m.ChatScroll.Top = to
	return moved
}

func (m *Model) pressChat(msg ChatPressed) Model {
	if !msg.Touch {
		width := m.Columns().Chat
		if width > tokens.HistoryScrollBarWidth && msg.X >= width-tokens.HistoryScrollBarWidth {
			thumb := m.Chat.ScrollbarThumb(m.ChatScroll, m.ChatScroll.Height)
			if !thumb.Hidden {
				m.ChatBar = BarDrag{Dragging: true, LastY: msg.Y}
				m.ChatPress = ChatPressState{Row: -1}
				if !history.BarOver(thumb, msg.X-(width-tokens.HistoryScrollBarWidth), msg.Y) {
					m.ChatScroll.Top = m.Chat.ClampOffset(
						m.Chat.BarTrackJump(m.ChatScroll, m.ChatScroll.Height, msg.Y), m.ChatScroll)
				}
				return *m
			}
		}
		m.ChatPress = m.chatPressAt(msg.X, msg.Y)
		return *m
	}
	d := m.ChatTouch
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
	m.ChatTouch = d
	return *m
}

func (m Model) chatPressAt(x, y int) ChatPressState {
	row := m.Chat.RowAt(y + m.ChatScroll.Top)
	if row < 0 || row >= len(m.Chat.Items) || m.Chat.Items[row].Empty {
		return ChatPressState{Row: -1}
	}
	var inside, timeCursor bool
	if row < len(m.Chat.Hits) {
		inside = m.Chat.Hits[row].PointStateOf(m.Chat.Items[row], x, y+m.ChatScroll.Top) == history.PointInside
		timeCursor = m.Chat.Hits[row].TimeHit(x, y+m.ChatScroll.Top)
	}
	action := ChatPressNone
	switch {
	case m.ChatSelection.InSelectionMode():
		if inside && m.ChatSelection.ContainsRow(row) {
			action = ChatPressPrepareDrag
		} else {
			action = ChatPressPrepareSelect
		}
	case timeCursor && inside:
		action = ChatPressPrepareDrag
	case inside:
		action = ChatPressSelecting
	default:
		action = ChatPressPrepareSelect
	}
	return ChatPressState{Row: row, X: x, Y: y, Inside: inside, Time: timeCursor, Action: action}
}

func (m *Model) finishChatPress(press ChatPressState, x, y int) {
	if press.Row < 0 || press.Row >= len(m.Chat.Items) {
		return
	}
	if press.Action != ChatPressPrepareSelect && press.Action != ChatPressPrepareDrag {
		return
	}
	if m.ChatSelection.InSelectionMode() {
		m.ChatSelection = history.ChangeSelection(
			m.ChatSelection, press.Row, m.Chat.Items[press.Row], history.SelectInvert)
		return
	}
	row := m.Chat.RowAt(y + m.ChatScroll.Top)
	if row < 0 || row >= len(m.Chat.Hits) || row >= len(m.Chat.Items) {
		return
	}
	if m.Chat.Hits[row].TimeHit(x, y+m.ChatScroll.Top) {
		m.ChatSelection = history.ChangeSelection(
			m.ChatSelection, press.Row, m.Chat.Items[press.Row], history.SelectAdd)
	}
}

func (m *Model) dragChat(msg ChatDragged) Model {
	if m.ChatBar.Dragging {
		dy := msg.Y - m.ChatBar.LastY
		m.ChatBar.LastY = msg.Y
		top, accum := m.Chat.ApplyBarDrag(m.ChatScroll, m.ChatScroll.Height, dy, m.ChatBar.Overscroll)
		m.ChatBar.Overscroll = accum
		m.ChatScroll.Top = top
		return *m
	}
	if !m.ChatTouch.Active {
		if p := m.ChatPress; p.Row >= 0 && p.Row < len(m.Chat.Items) {
			row := m.Chat.RowAt(msg.Y + m.ChatScroll.Top)
			if row != p.Row || absInt(msg.X-p.X)+absInt(msg.Y-p.Y) >= tokens.TouchDragStartDistance {
				if p.Action == ChatPressPrepareDrag {
					p.Action = ChatPressDragging
				} else if p.Action == ChatPressPrepareSelect {
					p.Action = ChatPressSelecting
				}
				m.ChatPress = p
			}
		}
		return *m
	}
	d := m.ChatTouch
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
			if !m.Chat.ConsumeScrollAction(dx, dy, true, msg.Y+m.ChatScroll.Top) {
				m.chatTouchScroll(dy)
			}
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
	m.ChatTouch = d
	return *m
}

func (m *Model) releaseChat(msg ChatReleased) {
	m.ChatBar = BarDrag{}
	if !m.ChatTouch.Active {
		press := m.ChatPress
		m.ChatPress = ChatPressState{Row: -1}
		m.finishChatPress(press, msg.X, msg.Y)
		return
	}
	d := m.ChatTouch
	tap := !d.Scrolling
	if d.Scrolling {
		switch d.State {
		case dialogs.TouchScrollManual:
			d.State = dialogs.TouchScrollAuto
			d.PrevValid = false
			d.TouchTime = msg.Now
		case dialogs.TouchScrollAcceleration:
			d.State = dialogs.TouchScrollAuto
			d.WaitingAcceleration = false
			d.PrevValid = false
		}
	}
	d.Active = false
	m.ChatTouch = d
	if tap {
		m.ChatTouch = TouchDrag{}
		press := m.chatPressAt(msg.X, msg.Y)
		m.finishChatPress(press, msg.X, msg.Y)
	}
}

func (m *Model) chatTick(now int) {
	d := m.ChatTouch
	if d.State != dialogs.TouchScrollAuto && d.State != dialogs.TouchScrollAcceleration {
		return
	}
	if d.State == dialogs.TouchScrollAcceleration && d.WaitingAcceleration &&
		now-d.AccelerationTime > tokens.TouchAccelerationTimeoutMs {
		d.State = dialogs.TouchScrollManual
		d.Speed = dialogs.TouchSpeed{}
		d.PrevValid = false
		m.ChatTouch = d
		return
	}
	elapsed := now - d.TouchTime
	if elapsed <= 0 {
		return
	}
	dx, dy := dialogs.FlingDelta(d.Speed, elapsed)
	consumed := m.Chat.ConsumeScrollAction(dx, dy, true, d.LastY+m.ChatScroll.Top)
	hasScrolled := consumed || m.chatTouchScroll(dy)
	if d.Speed == (dialogs.TouchSpeed{}) || !hasScrolled {
		d.State = dialogs.TouchScrollManual
		d.Scrolling = false
	} else {
		d.TouchTime = now
	}
	d.Speed = dialogs.TouchDeaccelerate(d.Speed, elapsed)
	m.ChatTouch = d
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
	s.Chat.ThumbDragging = m.ChatBar.Dragging
	return s
}
