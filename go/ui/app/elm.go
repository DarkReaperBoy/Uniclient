package app

import (
	"image/color"
	"math"
	"time"

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
	Items     []history.Item
	Msgs      []WireMessage
	ReadInbox int
	Unread    int
	MoreAbove bool
	Now       int
}

func (ChatLoaded) isMsg() {}

type ChatPrepended struct {
	Msgs      []WireMessage
	MoreAbove bool
	Now       int
}

func (ChatPrepended) isMsg() {}

type ChatPreloadTopRequested struct{}

func (ChatPreloadTopRequested) isMsg() {}

type ChatMeasured struct {
	Heights []int
	Hits    []history.HitBox
}

func (ChatMeasured) isMsg() {}

type ChatScrolled struct {
	DeltaY int
	Now    int
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
	Shift bool
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
	Row           int
	X             int
	Y             int
	Inside        bool
	Time          bool
	Action        ChatPressAction
	DownPress     bool
	MentionsPress bool
	ReactionPress bool
}

type ChatDateState struct {
	Shown            bool
	HasLast          bool
	LastRow          int
	LastOffset       int
	AlphaAnim        bool
	AlphaFrom        float32
	AlphaTo          float32
	AlphaStarted     int
	Alpha            float32
	HideAt           int
	AfterDayCrossing bool
}

type ChatDownState struct {
	Shown    bool
	Anim     bool
	From     float32
	To       float32
	Started  int
	Progress float32
}

type ChatMentionsState struct {
	Shown    bool
	Anim     bool
	From     float32
	To       float32
	Started  int
	Progress float32
}

type ChatReactionsState struct {
	Shown    bool
	Anim     bool
	From     float32
	To       float32
	Started  int
	Progress float32
}

type DialogsToUpState struct {
	Shown    bool
	Anim     bool
	From     float32
	To       float32
	Started  int
	Progress float32
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
	DialogsToUp       DialogsToUpState
	DialogsToUpPress  bool
	Chat              history.List
	ChatScroll        history.Viewport
	ChatMoreAbove     bool
	ChatPrependTop    int
	ChatPrependRows   int
	ChatDate          ChatDateState
	ChatDown          ChatDownState
	ChatMentions      ChatMentionsState
	ChatReactions     ChatReactionsState
	ChatCompose       ChatComposeState
	nowMs             int
	ChatTouch         TouchDrag
	ChatBar           BarDrag
	ChatDirty         bool
	ChatSelection     history.Selection
	ChatPress         ChatPressState
	Search            SearchState
	GlobalSearch      GlobalSearchState
	Accounts          []Account
	Open              ChatRef
	OpenValid         bool
	port              ChatPort
	chatMsgs          []WireMessage
	openGroup         bool
	openReadInbox     int
	openUnread        int
	openCanSend       bool
	openLoaded        bool
	chatJumpBottom    bool
	accountRows       map[string][]dialogs.Entry
	dialogFeed        []dialogs.Entry
	selectedAccount   string
	selectedChat      string
}

func InitialModel() Model {
	return Model{HasDialogs: true, Running: true,
		Dialogs:   dialogs.List{Selected: -1},
		ChatPress: ChatPressState{Row: -1},
		Search:    SearchState{Placeholder: "Search"}}
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
		m.DialogsScroll.Height = msg.Height - tokens.TopBarHeight
		if m.DialogsScroll.Height < 0 {
			m.DialogsScroll.Height = 0
		}
		m.DialogsScroll.Top = m.clampDialogsScroll(m.DialogsScroll.Top)
		m.dialogsToUpCheck()
		oldTop := m.ChatScroll.Top
		oldViewport := history.Viewport{Top: m.ChatScroll.Top, Height: m.ChatScroll.Height}
		wasAtBottom := m.ChatScroll.Top >= m.Chat.MaxOffset(oldViewport)
		m.ChatScroll.Height = m.composeViewportHeight()
		if wasAtBottom {
			m.ChatScroll.Top = m.Chat.MaxOffset(m.ChatScroll)
		} else {
			m.ChatScroll.Top = m.Chat.ClampOffset(m.ChatScroll.Top, m.ChatScroll)
		}
		m.ChatDirty = true
		m.chatViewportChanged(oldTop)
		cmd := m.loadMoreCmd()
		if cmd == nil {
			cmd = m.chatPreloadCmd()
		}
		return m, cmd
	case Quit:
		m.Running = false
		return m, nil
	case DialogsLoaded:
		m.setDialogRows(msg.Rows, true)
		return m, m.loadMoreCmd()
	case DialogRowPressed:
		if msg.Index >= 0 && msg.Index < m.Dialogs.RowCount() {
			m.selectDialogRow(msg.Index)
		}
		return m, nil
	case DialogsScrolled:
		m.DialogsScroll.Top = m.clampDialogsScroll(m.DialogsScroll.Top + msg.DeltaY)
		m.dialogsToUpCheck()
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
		next, cmd := m.pressDialogs(msg)
		return next, cmd
	case DialogsHeaderPressed:
		m.pressDialogsHeader(msg)
		return m, nil
	case EngineEventMsg:
		return m.applyEngineEvent(msg.Data)
	case DialogsDragged:
		return m.dragDialogs(msg), m.loadMoreCmd()
	case DialogsReleased:
		prev := m.Dialogs.Selected
		m.releaseDialogs(msg)
		return m, m.openCmdAfterPress(prev)
	case DialogsPressCanceled:
		m.DialogsBar = BarDrag{}
		m.DialogsTouch.Active = false
		m.DialogsTouch.Scrolling = false
		m.DialogsTouch.State = dialogs.TouchScrollManual
		m.DialogsToUpPress = false
		return m, nil
	case DialogsTick:
		m.nowMs = msg.Now
		m.dialogsTick(msg.Now)
		m.dialogsToUpTick(msg.Now)
		m.searchBlinkTick(msg.Now)
		cmd := m.searchGlobalTick(msg.Now)
		if cmd == nil {
			cmd = m.loadMoreCmd()
		}
		return m, cmd
	case SearchGlobalLoaded:
		m.nowMs = int(time.Now().UnixMilli())
		return m.applySearchGlobalLoaded(msg)
	case DialogsLoadMoreRequested:
		return m, nil
	case ChatLoaded:
		m.nowMs = msg.Now
		m.Chat.Items = msg.Items
		m.ChatMoreAbove = msg.MoreAbove
		m.ChatPrependTop = 0
		m.ChatPrependRows = 0
		m.ChatDate = ChatDateState{}
		m.ChatDown = ChatDownState{}
		m.ChatMentions = ChatMentionsState{}
		m.ChatReactions = ChatReactionsState{}
		m.Chat.Heights = nil
		m.Chat.Hits = nil
		m.ChatSelection = nil
		m.ChatDirty = true
		m.ChatScroll.Top = m.Chat.ClampOffset(m.ChatScroll.Top, m.ChatScroll)
		m.chatMentionsCheck()
		m.chatReactionsCheck()
		m.chatMsgs = msg.Msgs
		m.openReadInbox = msg.ReadInbox
		m.openUnread = msg.Unread
		if m.OpenValid && !m.openLoaded {
			m.openLoaded = true
			m.chatJumpBottom = true
			m.ChatCompose.CanSend = m.openCanSend
		}
		return m, nil
	case ChatPrepended:
		m.nowMs = msg.Now
		m.ChatMoreAbove = msg.MoreAbove
		if len(msg.Msgs) > 0 {
			pageItems := FeedItems(msg.Msgs, m.openReadInbox, time.UnixMilli(int64(msg.Now)), m.openGroup)
			if pageHasUnreadBar(pageItems) {
				for i := range m.Chat.Items {
					m.Chat.Items[i].UnreadBar = ""
				}
			}
			m.ChatPrependTop = m.ChatScroll.Top
			m.ChatPrependRows = len(msg.Msgs)
			m.ChatDate.LastRow += len(msg.Msgs)
			m.chatMsgs = append(append([]WireMessage(nil), msg.Msgs...), m.chatMsgs...)
			m.Chat.Items = append(pageItems, m.Chat.Items...)
			m.Chat.Heights = nil
			m.Chat.Hits = nil
			m.ChatSelection = nil
			m.ChatPress = ChatPressState{Row: -1}
			m.ChatDirty = true
			m.chatMentionsCheck()
			m.chatReactionsCheck()
		}
		return m, nil
	case ChatMeasured:
		oldTop := m.ChatScroll.Top
		m.Chat.Heights = msg.Heights
		m.Chat.Hits = msg.Hits
		m.ChatDirty = false
		if m.chatJumpBottom {
			m.chatJumpBottom = false
			m.ChatScroll.Top = m.Chat.MaxOffset(m.ChatScroll)
		} else if m.ChatPrependRows > 0 {
			shift := 0
			for i := 0; i < m.ChatPrependRows && i < len(m.Chat.Heights); i++ {
				shift += m.Chat.Heights[i]
			}
			m.ChatScroll.Top = m.Chat.ClampOffset(m.ChatPrependTop+shift, m.ChatScroll)
			m.ChatPrependTop = 0
			m.ChatPrependRows = 0
		} else {
			m.ChatScroll.Top = m.Chat.ClampOffset(m.ChatScroll.Top, m.ChatScroll)
		}
		m.chatViewportChanged(oldTop)
		return m, m.chatPreloadCmd()
	case ChatScrolled:
		m.nowMs = msg.Now
		oldTop := m.ChatScroll.Top
		m.ChatScroll.Top = m.Chat.ClampOffset(m.ChatScroll.Top+msg.DeltaY, m.ChatScroll)
		m.chatViewportChanged(oldTop)
		return m, m.chatPreloadCmd()
	case ChatWheel:
		return m.chatWheel(msg)
	case ChatTrackpadScrolled:
		return m.chatTrackpad(msg)
	case ChatPressed:
		return m.pressChat(msg), nil
	case ChatDragged:
		dragged := m.dragChat(msg)
		return dragged, dragged.chatPreloadCmd()
	case ChatReleased:
		m.releaseChat(msg)
		return m, nil
	case ChatPressCanceled:
		m.ChatBar = BarDrag{}
		m.ChatTouch = TouchDrag{}
		m.ChatPress = ChatPressState{Row: -1}
		m.ChatCompose.MousePressed = false
		m.ChatCompose.Grab = false
		m.ChatCompose.LastClickSet = false
		return m, nil
	case ChatTick:
		m.nowMs = msg.Now
		m.chatTick(msg.Now)
		m.chatDateTick(msg.Now)
		m.chatDownTick(msg.Now)
		m.chatMentionsTick(msg.Now)
		m.chatReactionsTick(msg.Now)
		m.composePlaceholderTick(msg.Now)
		m.composeBlinkTick(msg.Now)
		return m, m.chatPreloadCmd()
	case ChatComposeTyped:
		m.composeTyped(msg)
		return m, nil
	case ChatComposeSubmitted:
		m.nowMs = msg.Now
		return m, m.composeSubmittedCmd()
	case ChatComposeSendRequested:
		if !msg.OK {
			m.composeEdit(msg.Text, len([]rune(msg.Text)))
		}
		return m, nil
	case SearchTyped:
		m.searchTyped(msg)
		return m, nil
	case SearchBackspace:
		m.searchBackspace(msg)
		return m, nil
	case SearchFocusLost:
		m.searchBlur()
		return m, nil
	case ChatComposeBackspace:
		m.composeBackspace(msg)
		return m, nil
	case ChatComposeDelete:
		m.composeDelete(msg)
		return m, nil
	case ChatComposeCursorKey:
		m.composeCursorKey(msg)
		return m, nil
	case ChatComposeSelectAll:
		m.composeSelectAll()
		return m, nil
	case ChatComposePressed:
		m.composePressed(msg)
		return m, nil
	case ChatComposeDragged:
		m.composeDragged(msg)
		return m, nil
	case ChatComposeReleased:
		m.composeReleased(msg)
		return m, nil
	case ChatComposeFocusLost:
		m.composeFocusLost()
		return m, nil
	case ChatBottomRequested:
		return m, nil
	case ChatPreloadTopRequested:
		return m, m.chatPreloadTopCmd()
	}
	return m, nil
}

func (m *Model) scrollClassic(dy, now int) Model {
	m.nowMs = now
	if m.DialogsOverscroll.Stretch == 0 {
		m.DialogsScroll.Top = m.clampDialogsScroll(m.DialogsScroll.Top + dy)
		m.dialogsToUpCheck()
		return *m
	}
	if !m.DialogsOverscroll.Animating(now) {
		m.DialogsOverscroll.Return(now)
	}
	return *m
}

func (m *Model) pressDialogs(msg DialogsPressed) (Model, Cmd) {
	prev := m.Dialogs.Selected
	m.nowMs = msg.Now
	m.searchBlur()
	if m.dialogsToUpHitAt(msg.X, msg.Y) {
		m.DialogsBar = BarDrag{}
		m.DialogsTouch = TouchDrag{}
		m.DialogsToUpPress = true
		return *m, nil
	}
	width := m.Columns().Dialogs
	if !msg.Touch && width > tokens.ScrollBarWidth && msg.X >= width-tokens.ScrollBarWidth {
		thumb := m.Dialogs.ScrollbarThumb(m.DialogsScroll, width, m.DialogsScroll.Height)
		if !thumb.Hidden {
			m.DialogsBar = BarDrag{Dragging: true, LastY: msg.Y}
			if !dialogs.BarOver(thumb, msg.X-(width-tokens.ScrollBarWidth), msg.Y) {
				m.DialogsScroll.Top = m.clampDialogsScroll(
					m.Dialogs.BarTrackJump(m.DialogsScroll, width, m.DialogsScroll.Height, msg.Y))
				m.dialogsToUpCheck()
			}
			return *m, nil
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
		return *m, nil
	}
	if idx := m.Dialogs.RowAt(msg.Y+m.DialogsScroll.Top, width); idx >= 0 {
		m.selectDialogRow(idx)
	}
	return *m, m.openCmdAfterPress(prev)
}

func (m *Model) openCmdAfterPress(prev int) Cmd {
	if m.Dialogs.Selected == prev || m.port == nil ||
		m.Dialogs.Selected < 0 || m.Dialogs.Selected >= m.Dialogs.RowCount() {
		return nil
	}
	row := m.Dialogs.EntryAt(m.Dialogs.Selected)
	if row.Account == "" || row.ChatID == "" {
		return nil
	}
	m.Open = ChatRef{Account: row.Account, ID: row.ChatID}
	m.OpenValid = true
	m.openGroup = row.Group
	m.openReadInbox = row.ReadInbox
	m.openUnread = row.Unread
	m.openCanSend = row.ChatType != dialogs.ChatChannel
	m.openLoaded = false
	port, group, readInbox, unread := m.port, row.Group, row.ReadInbox, row.Unread
	account, chat := row.Account, row.ChatID
	return func() Msg {
		msgs, ok := port.Messages(account, chat, chatHistoryLimit)
		if !ok {
			return nil
		}
		return ChatLoaded{Msgs: msgs, ReadInbox: readInbox, Unread: unread, MoreAbove: len(msgs) == chatHistoryLimit, Items: FeedItems(msgs, readInbox, time.Now(), group), Now: int(time.Now().UnixMilli())}
	}
}

func (m *Model) composeSubmittedCmd() Cmd {
	if !m.OpenValid || m.port == nil || !m.ChatCompose.CanSend || m.ChatCompose.Text == "" {
		return nil
	}
	text := m.ChatCompose.Text
	account, chat := m.Open.Account, m.Open.ID
	port := m.port
	m.composeEdit("", 0)
	return func() Msg {
		return ChatComposeSendRequested{OK: port.Send(account, chat, text), Text: text}
	}
}

func (m *Model) dragDialogs(msg DialogsDragged) Model {
	m.nowMs = msg.Now
	if m.DialogsBar.Dragging {
		dy := msg.Y - m.DialogsBar.LastY
		m.DialogsBar.LastY = msg.Y
		m.DialogsScroll.Top = m.clampDialogsScroll(
			m.DialogsScroll.Top + m.Dialogs.BarDragScale(
				m.DialogsScroll, m.Columns().Dialogs, m.DialogsScroll.Height, dy))
		m.dialogsToUpCheck()
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
	m.nowMs = msg.Now
	m.DialogsBar = BarDrag{}
	if m.DialogsToUpPress {
		m.DialogsToUpPress = false
		if m.dialogsToUpHitAt(msg.X, msg.Y) {
			m.DialogsScroll.Top = m.clampDialogsScroll(0)
			m.dialogsToUpCheck()
		}
		return
	}
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
			m.selectDialogRow(idx)
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
		m.dialogsToUpCheck()
	}
}

func (m *Model) applyTouchDelta(dx, dy int, phase dialogs.Phase, now int) {
	d := dialogs.ScrollPixels(dx, dy, 0, 0, false)
	m.DialogsScroll.Top = m.DialogsOverscroll.ApplyInput(
		m.DialogsScroll.Top, m.dialogsMaxOffset(), d, phase, true, now, now)
	m.dialogsToUpCheck()
}

func (m Model) dialogsMaxOffset() int {
	return m.Dialogs.MaxOffset(m.Columns().Dialogs, m.DialogsScroll.Height)
}

func (m *Model) dialogsToUpHitAt(x, y int) bool {
	return dialogs.ToUpHit(m.Columns().Dialogs, m.DialogsScroll.Height,
		m.DialogsToUp.Progress, x, y)
}

func (m *Model) dialogsToUpCheck() {
	narrow := m.Columns().Dialogs < tokens.DialogsRightButtonMinPaneWidth
	shown := m.Dialogs.ToUpShown(m.DialogsScroll, m.Columns().Dialogs)
	if shown == m.DialogsToUp.Shown {
		return
	}
	m.DialogsToUp.Shown = shown
	if narrow {
		m.DialogsToUp.Anim = false
		m.DialogsToUp.Progress = 0
		m.DialogsToUp.From = 0
		m.DialogsToUp.To = 0
		return
	}
	m.DialogsToUp.From = m.DialogsToUp.Progress
	m.DialogsToUp.To = 0
	if shown {
		m.DialogsToUp.To = 1
	}
	m.DialogsToUp.Started = m.nowMs
	m.DialogsToUp.Anim = true
}

func (m *Model) dialogsToUpTick(now int) {
	if !m.DialogsToUp.Anim {
		return
	}
	elapsed := now - m.DialogsToUp.Started
	if elapsed >= tokens.HistoryToDownDurationMs {
		m.DialogsToUp.Progress = m.DialogsToUp.To
		m.DialogsToUp.Anim = false
	} else if elapsed >= 0 {
		t := float32(elapsed) / float32(tokens.HistoryToDownDurationMs)
		m.DialogsToUp.Progress = m.DialogsToUp.From +
			(m.DialogsToUp.To-m.DialogsToUp.From)*t
	}
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

func (m Model) chatPreloadCmd() Cmd {
	if !m.ChatMoreAbove || !m.Chat.PreloadTopNeeded(m.ChatScroll) {
		return nil
	}
	return func() Msg { return ChatPreloadTopRequested{} }
}

func (m Model) chatPreloadTopCmd() Cmd {
	if m.port == nil || !m.OpenValid || !m.openLoaded || !m.ChatMoreAbove || len(m.chatMsgs) == 0 {
		return nil
	}
	port, account, chat := m.port, m.Open.Account, m.Open.ID
	beforeMs := m.chatMsgs[0].TimestampMs + 1
	loaded := make(map[string]struct{}, len(m.chatMsgs))
	for _, wm := range m.chatMsgs {
		loaded[wm.ID] = struct{}{}
	}
	return func() Msg {
		page, ok := port.MessagesBefore(account, chat, beforeMs, chatHistoryLimit)
		if !ok {
			return nil
		}
		fresh := make([]WireMessage, 0, len(page))
		for _, wm := range page {
			if _, dup := loaded[wm.ID]; dup {
				continue
			}
			fresh = append(fresh, wm)
		}
		return ChatPrepended{Msgs: fresh, MoreAbove: len(page) == chatHistoryLimit && len(fresh) > 0, Now: int(time.Now().UnixMilli())}
	}
}

func pageHasUnreadBar(items []history.Item) bool {
	for i := range items {
		if items[i].UnreadBar != "" {
			return true
		}
	}
	return false
}

func (m *Model) chatViewportChanged(oldTop int) {
	if m.ChatScroll.Top < oldTop {
		m.chatDateCheckUpward()
	} else {
		m.chatDateCheckDownward()
	}
	m.chatDownCheck()
}

func (m *Model) chatDownCheck() {
	shown := m.Chat.DownShown(m.ChatScroll)
	if shown == m.ChatDown.Shown {
		return
	}
	m.ChatDown.Shown = shown
	m.ChatDown.From = m.ChatDown.Progress
	m.ChatDown.To = 0
	if shown {
		m.ChatDown.To = 1
	}
	m.ChatDown.Started = m.nowMs
	m.ChatDown.Anim = true
}

func (m *Model) chatDownTick(now int) {
	if !m.ChatDown.Anim {
		return
	}
	elapsed := now - m.ChatDown.Started
	if elapsed >= tokens.HistoryToDownDurationMs {
		m.ChatDown.Progress = m.ChatDown.To
		m.ChatDown.Anim = false
	} else if elapsed >= 0 {
		t := float32(elapsed) / float32(tokens.HistoryToDownDurationMs)
		m.ChatDown.Progress = m.ChatDown.From +
			(m.ChatDown.To-m.ChatDown.From)*t
	}
}

func (m *Model) chatMentionsCheck() {
	shown := m.Chat.MentionsShown()
	if shown == m.ChatMentions.Shown {
		return
	}
	m.ChatMentions.Shown = shown
	m.ChatMentions.From = m.ChatMentions.Progress
	m.ChatMentions.To = 0
	if shown {
		m.ChatMentions.To = 1
	}
	m.ChatMentions.Started = m.nowMs
	m.ChatMentions.Anim = true
}

func (m *Model) chatMentionsTick(now int) {
	if !m.ChatMentions.Anim {
		return
	}
	elapsed := now - m.ChatMentions.Started
	if elapsed >= tokens.HistoryToDownDurationMs {
		m.ChatMentions.Progress = m.ChatMentions.To
		m.ChatMentions.Anim = false
	} else if elapsed >= 0 {
		t := float32(elapsed) / float32(tokens.HistoryToDownDurationMs)
		m.ChatMentions.Progress = m.ChatMentions.From +
			(m.ChatMentions.To-m.ChatMentions.From)*t
	}
}

func (m *Model) chatReactionsCheck() {
	shown := m.Chat.ReactionsShown()
	if shown == m.ChatReactions.Shown {
		return
	}
	m.ChatReactions.Shown = shown
	m.ChatReactions.From = m.ChatReactions.Progress
	m.ChatReactions.To = 0
	if shown {
		m.ChatReactions.To = 1
	}
	m.ChatReactions.Started = m.nowMs
	m.ChatReactions.Anim = true
}

func (m *Model) chatReactionsTick(now int) {
	if !m.ChatReactions.Anim {
		return
	}
	elapsed := now - m.ChatReactions.Started
	if elapsed >= tokens.HistoryToDownDurationMs {
		m.ChatReactions.Progress = m.ChatReactions.To
		m.ChatReactions.Anim = false
	} else if elapsed >= 0 {
		t := float32(elapsed) / float32(tokens.HistoryToDownDurationMs)
		m.ChatReactions.Progress = m.ChatReactions.From +
			(m.ChatReactions.To-m.ChatReactions.From)*t
	}
}

func (m *Model) chatDateCheckUpward() {
	row, offset := m.Chat.ScrollDateAnchor(m.ChatScroll)
	if row < 0 {
		m.ChatDate.HasLast = false
		m.ChatDate.LastRow = 0
		m.ChatDate.LastOffset = 0
		m.chatDateHide()
		return
	}
	if !m.ChatDate.HasLast || row != m.ChatDate.LastRow || offset != m.ChatDate.LastOffset {
		if m.ChatDate.HasLast && !m.ChatDate.Shown {
			m.chatDateToggle()
		}
		m.ChatDate.HasLast = true
		m.ChatDate.LastRow = row
		m.ChatDate.LastOffset = offset
		m.ChatDate.HideAt = m.nowMs + tokens.ScrollDateHideMs
	}
}

func (m *Model) chatDateCheckDownward() {
	row, offset := m.Chat.ScrollDateAnchor(m.ChatScroll)
	prevRow := -1
	if m.ChatDate.HasLast {
		prevRow = m.ChatDate.LastRow
	}
	m.ChatDate.HasLast = row >= 0
	m.ChatDate.LastRow = row
	m.ChatDate.LastOffset = offset
	crossedDay := prevRow >= 0 && row >= 0 &&
		prevRow < len(m.Chat.Items) && row < len(m.Chat.Items) &&
		m.Chat.Items[prevRow].DateText != "" && m.Chat.Items[row].DateText != "" &&
		m.Chat.Items[prevRow].DateText != m.Chat.Items[row].DateText
	if crossedDay {
		if !m.ChatDate.Shown {
			m.chatDateToggle()
		}
		m.ChatDate.AfterDayCrossing = true
		m.ChatDate.HideAt = m.nowMs + tokens.ScrollDateHideOnDayCrossingMs
	} else if !m.ChatDate.AfterDayCrossing {
		m.chatDateHideByTimer()
	}
}

func (m *Model) chatDateHideByTimer() {
	m.ChatDate.HideAt = 0
	m.ChatDate.AfterDayCrossing = false
	m.chatDateHide()
}

func (m *Model) chatDateHide() {
	if m.ChatDate.Shown {
		m.chatDateToggle()
	}
}

func (m *Model) chatDateToggle() {
	m.ChatDate.Shown = !m.ChatDate.Shown
	m.ChatDate.AlphaFrom = 0
	m.ChatDate.AlphaTo = 1
	if !m.ChatDate.Shown {
		m.ChatDate.AlphaFrom = 1
		m.ChatDate.AlphaTo = 0
	}
	m.ChatDate.AlphaStarted = m.nowMs
	m.ChatDate.AlphaAnim = true
	m.ChatDate.Alpha = m.ChatDate.AlphaFrom
}

func (m *Model) chatDateTick(now int) {
	if m.ChatDate.AlphaAnim {
		elapsed := now - m.ChatDate.AlphaStarted
		if elapsed >= tokens.HistoryDateFadeMs {
			m.ChatDate.Alpha = m.ChatDate.AlphaTo
			m.ChatDate.AlphaAnim = false
		} else if elapsed >= 0 {
			t := float32(elapsed) / float32(tokens.HistoryDateFadeMs)
			m.ChatDate.Alpha = m.ChatDate.AlphaFrom +
				(m.ChatDate.AlphaTo-m.ChatDate.AlphaFrom)*t
		}
	}
	if m.ChatDate.HideAt > 0 && now >= m.ChatDate.HideAt {
		m.ChatDate.HideAt = 0
		m.ChatDate.AfterDayCrossing = false
		m.chatDateHide()
	}
}

func (m Model) ChatDateActive() bool {
	return m.ChatDate.AlphaAnim || m.ChatDate.HideAt > 0
}

func (m Model) ChatDownActive() bool {
	return m.ChatDown.Anim
}

func (m Model) ChatMentionsActive() bool {
	return m.ChatMentions.Anim
}

func (m Model) ChatComposePlaceholderActive() bool {
	return m.ChatCompose.PlaceholderAnim
}

func (m Model) ChatComposeBlinkActive() bool {
	return m.ChatCompose.Focused
}

func (m Model) ChatReactionsActive() bool {
	return m.ChatReactions.Anim
}

func (m Model) DialogsToUpActive() bool {
	return m.DialogsToUp.Anim
}

func (m *Model) chatScrollClassic(dy int) (Model, Cmd) {
	var cmd Cmd
	if history.ChatBottomRequest(m.ChatScroll.Top, dy, m.Chat.MaxOffset(m.ChatScroll)) {
		cmd = func() Msg { return ChatBottomRequested{} }
	}
	oldTop := m.ChatScroll.Top
	m.ChatScroll.Top = m.Chat.ClampOffset(m.ChatScroll.Top+dy, m.ChatScroll)
	m.chatViewportChanged(oldTop)
	if cmd == nil {
		cmd = m.chatPreloadCmd()
	}
	return *m, cmd
}

func (m *Model) chatWheel(msg ChatWheel) (Model, Cmd) {
	m.nowMs = msg.Now
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
	m.nowMs = msg.Now
	if absInt(msg.PixelX) > absInt(msg.PixelY) &&
		m.Chat.ConsumeScrollAction(msg.PixelX, msg.PixelY, true, msg.Y+m.ChatScroll.Top) {
		return *m, nil
	}
	dy := dialogs.ScrollPixels(msg.PixelX, msg.PixelY,
		m.Columns().Chat, m.ChatScroll.Height, msg.Accelerate)
	return m.chatScrollClassic(dy)
}

func (m *Model) chatTouchScroll(dy int) bool {
	oldTop := m.ChatScroll.Top
	to := m.Chat.ClampOffset(m.ChatScroll.Top-dy, m.ChatScroll)
	moved := to != m.ChatScroll.Top
	m.ChatScroll.Top = to
	if moved {
		m.chatViewportChanged(oldTop)
	}
	return moved
}

func (m *Model) pressChat(msg ChatPressed) Model {
	m.nowMs = msg.Now
	if m.composeFieldHitAt(msg.X, msg.Y) {
		m.ChatBar = BarDrag{}
		m.ChatTouch = TouchDrag{}
		m.ChatPress = ChatPressState{Row: -1}
		m.composePressed(ChatComposePressed{X: msg.X, Y: msg.Y, Shift: msg.Shift, Now: msg.Now})
		return *m
	}
	m.ChatCompose.LastClickSet = false
	if m.chatReactionsHitAt(msg.X, msg.Y) {
		m.ChatBar = BarDrag{}
		m.ChatTouch = TouchDrag{}
		m.ChatPress = ChatPressState{Row: -1, X: msg.X, Y: msg.Y, ReactionPress: true}
		return *m
	}
	if m.chatMentionsHitAt(msg.X, msg.Y) {
		m.ChatBar = BarDrag{}
		m.ChatTouch = TouchDrag{}
		m.ChatPress = ChatPressState{Row: -1, X: msg.X, Y: msg.Y, MentionsPress: true}
		return *m
	}
	if m.chatDownHitAt(msg.X, msg.Y) {
		m.ChatBar = BarDrag{}
		m.ChatTouch = TouchDrag{}
		m.ChatPress = ChatPressState{Row: -1, X: msg.X, Y: msg.Y, DownPress: true}
		return *m
	}
	if !msg.Touch {
		width := m.Columns().Chat
		if width > tokens.HistoryScrollBarWidth && msg.X >= width-tokens.HistoryScrollBarWidth {
			thumb := m.Chat.ScrollbarThumb(m.ChatScroll, m.ChatScroll.Height)
			if !thumb.Hidden {
				m.ChatBar = BarDrag{Dragging: true, LastY: msg.Y}
				m.ChatPress = ChatPressState{Row: -1}
				if !history.BarOver(thumb, msg.X-(width-tokens.HistoryScrollBarWidth), msg.Y) {
					oldTop := m.ChatScroll.Top
					m.ChatScroll.Top = m.Chat.ClampOffset(
						m.Chat.BarTrackJump(m.ChatScroll, m.ChatScroll.Height, msg.Y), m.ChatScroll)
					m.chatViewportChanged(oldTop)
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
	m.nowMs = msg.Now
	if m.ChatCompose.Grab {
		m.composeDragged(ChatComposeDragged{X: msg.X, Y: msg.Y, Now: msg.Now})
		return *m
	}
	if m.ChatBar.Dragging {
		dy := msg.Y - m.ChatBar.LastY
		m.ChatBar.LastY = msg.Y
		top, accum := m.Chat.ApplyBarDrag(m.ChatScroll, m.ChatScroll.Height, dy, m.ChatBar.Overscroll)
		m.ChatBar.Overscroll = accum
		oldTop := m.ChatScroll.Top
		m.ChatScroll.Top = top
		m.chatViewportChanged(oldTop)
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
	if m.ChatCompose.Grab {
		m.composeReleased(ChatComposeReleased{X: msg.X, Y: msg.Y, Now: msg.Now})
		return
	}
	m.ChatBar = BarDrag{}
	if !m.ChatTouch.Active {
		press := m.ChatPress
		m.ChatPress = ChatPressState{Row: -1}
		if press.ReactionPress {
			m.chatReactionsClick(msg.X, msg.Y)
			return
		}
		if press.MentionsPress {
			m.chatMentionsClick(msg.X, msg.Y)
			return
		}
		if press.DownPress {
			m.chatDownClick(msg.X, msg.Y)
			return
		}
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

func (m *Model) chatDownHitAt(x, y int) bool {
	return history.DownButtonHit(m.Columns().Chat, m.ChatScroll.Height,
		m.ChatDown.Progress, x, y)
}

func (m *Model) chatMentionsHitAt(x, y int) bool {
	return history.MentionsButtonHit(m.Columns().Chat, m.ChatScroll.Height,
		m.ChatMentions.Progress, m.ChatDown.Progress, x, y)
}

func (m *Model) chatReactionsHitAt(x, y int) bool {
	return history.ReactionsButtonHit(m.Columns().Chat, m.ChatScroll.Height,
		m.ChatReactions.Progress, m.ChatDown.Progress, m.ChatMentions.Progress, x, y)
}

func (m *Model) chatReactionsClick(x, y int) {
	if !m.chatReactionsHitAt(x, y) {
		return
	}
	top := m.Chat.ReactionsJumpTop(m.ChatScroll)
	if top < 0 {
		return
	}
	oldTop := m.ChatScroll.Top
	m.ChatScroll.Top = m.Chat.ClampOffset(top, m.ChatScroll)
	m.chatViewportChanged(oldTop)
}

func (m *Model) chatMentionsClick(x, y int) {
	if !m.chatMentionsHitAt(x, y) {
		return
	}
	top := m.Chat.MentionsJumpTop(m.ChatScroll)
	if top < 0 {
		return
	}
	oldTop := m.ChatScroll.Top
	m.ChatScroll.Top = m.Chat.ClampOffset(top, m.ChatScroll)
	m.chatViewportChanged(oldTop)
}

func (m *Model) chatDownClick(x, y int) {
	if !m.chatDownHitAt(x, y) {
		return
	}
	oldTop := m.ChatScroll.Top
	m.ChatScroll.Top = m.Chat.ClampOffset(m.Chat.DownJumpTop(m.ChatScroll), m.ChatScroll)
	m.chatViewportChanged(oldTop)
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
		s.Dialogs.ToUpProgress = m.DialogsToUp.Progress
		s.Dialogs.Header = dialogs.HeaderLayout(m.Columns().Dialogs)
		s.Dialogs.Header.Text = m.Search.Text
		s.Dialogs.Header.Cursor = m.Search.Cursor
		s.Dialogs.Header.Focused = m.Search.Focused
		s.Dialogs.Header.CaretOn = m.Search.CursorOn
		s.Dialogs.Header.Placeholder = m.Search.Placeholder
	}
	s.Chat = m.Chat.Pane(m.ChatScroll, m.Columns().Chat)
	s.Chat.ThumbDragging = m.ChatBar.Dragging
	s.Chat.DateAlpha = m.ChatDate.Alpha
	s.Chat.DownProgress = m.ChatDown.Progress
	s.Chat.DownBadgeText = tokens.FormatUnreadCounter(m.openUnread, false, false)
	s.Chat.MentionsProgress = m.ChatMentions.Progress
	s.Chat.ReactionsProgress = m.ChatReactions.Progress
	s.Chat.Compose = m.ComposePane()
	if len(m.Accounts) == 0 {
		if cols := m.Columns(); cols.Dialogs < m.Width {
			s.Chat.EmptyText = AddAccountPrompt
		} else {
			s.Dialogs.EmptyText = AddAccountPrompt
		}
	}
	return s
}
