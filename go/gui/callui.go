package gui

import (
	"image/color"
	"time"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/cores"
	"uniclient/engine"
)

type callUI struct {
	accountID string
	callID    string
	chatID    string
	peerName  string
	video     bool
	incoming  bool

	state     string
	startedAt time.Time
	endedAt   time.Time

	muted bool
	camOn bool
}

const callDismissDelay = 4 * time.Second

func dmCallButtons(c engine.ChatInfo, caps []string) (voice, video bool) {
	if c.Type != engine.ChatTypeDMVal || c.IsBot {
		return false, false
	}
	if !capContains(caps, cores.CapCalls) {
		return false, false
	}
	return true, true
}

func capContains(caps []string, want string) bool {
	for _, c := range caps {
		if c == want {
			return true
		}
	}
	return false
}

func newOutgoingCall(accountID, chatID, peerName string, video bool, callID string) *callUI {
	return &callUI{
		accountID: accountID,
		chatID:    chatID,
		peerName:  peerName,
		video:     video,
		callID:    callID,
		state:     string(cores.CallStateRinging),
		camOn:     video,
	}
}

func callUIFromSession(accountID string, cs *cores.CallSession, peerName string, video bool) *callUI {
	if peerName == "" {
		peerName = "Unknown caller"
	}
	if cs == nil {
		return nil
	}
	return &callUI{
		accountID: accountID,
		chatID:    cs.ChatID,
		peerName:  peerName,
		video:     video || cs.IsVideo,
		incoming:  true,
		callID:    cs.ID,
		state:     string(cores.CallStateRinging),
	}
}

func (c *callUI) matches(accountID, callID string) bool {
	return c.accountID == accountID && c.callID == callID
}

func (c *callUI) applyEvent(state string, now time.Time) bool {
	switch state {
	case string(cores.CallStateEnded):
		if c.state == string(cores.CallStateEnded) {
			return false
		}
		c.state = state
		c.endedAt = now
		return true
	case string(cores.CallStateActive):
		if c.state == state || c.state == string(cores.CallStateEnded) {
			return false
		}
		if c.startedAt.IsZero() {
			c.startedAt = now
		}
		c.state = state
		return true
	case string(cores.CallStateConnecting):
		if c.state == state || c.state == string(cores.CallStateActive) || c.state == string(cores.CallStateEnded) {
			return false
		}
		c.state = state
		return true
	case string(cores.CallStateRinging):
		if c.state != "" {
			return false
		}
		c.state = state
		return true
	}
	return false
}

func (c *callUI) statusLine(now time.Time) string {
	switch c.state {
	case string(cores.CallStateEnded):
		if !c.startedAt.IsZero() {
			return "Call ended · " + fmtDur(int(c.endedAt.Sub(c.startedAt).Seconds()))
		}
		return "Call ended"
	case string(cores.CallStateActive):
		return fmtDur(int(now.Sub(c.startedAt).Seconds()))
	case string(cores.CallStateConnecting):
		return "Connecting…"
	case string(cores.CallStateRinging):
		if c.incoming {
			return "Incoming call…"
		}
		return "Ringing…"
	}
	return ""
}

type callControls struct {
	accept  bool
	decline bool
	mute    bool
	camera  bool
	end     bool
	close   bool
}

func (c *callUI) controls() callControls {
	var ct callControls
	switch c.state {
	case string(cores.CallStateRinging):
		if c.incoming {
			ct.accept = true
			ct.decline = true
		} else {
			ct.end = true
		}
	case string(cores.CallStateConnecting):
		ct.end = true
	case string(cores.CallStateActive):
		ct.mute = true
		ct.end = true
		if c.video {
			ct.camera = true
		}
	case string(cores.CallStateEnded):
		ct.close = true
	}
	return ct
}

func (c *callUI) dismissible(now time.Time) bool {
	return c.state == string(cores.CallStateEnded) && !c.endedAt.IsZero() && now.Sub(c.endedAt) >= callDismissDelay
}

func callElapsedTickerWanted(c *callUI, accountID, callID string) bool {
	return c != nil && c.matches(accountID, callID) && c.state == string(cores.CallStateActive)
}

var (
	callKeyTag = new(bool)
)

func (a *App) loadHdrCaps(k chatKey) {
	a.mu.Lock()
	cur := a.hdrCapsFor
	a.mu.Unlock()
	if cur == k.AccountID {
		return
	}
	go func() {
		caps := a.eng.AccountCapabilities(k.AccountID)
		a.mu.Lock()
		a.hdrCaps, a.hdrCapsFor = caps, k.AccountID
		a.mu.Unlock()
		a.invalidate()
	}()
}

func (a *App) startDMCall(chat engine.ChatInfo, video bool) {
	go func() {
		id, err := a.eng.StartCall(chat.AccountID, chat.ChatID, video)
		if err != nil {
			a.setToast("Call failed: " + err.Error())
			return
		}
		a.mu.Lock()
		a.call = newOutgoingCall(chat.AccountID, chat.ChatID, chat.Title, video, id)
		a.mu.Unlock()
		a.invalidate()
	}()
}

func (a *App) onIncomingCallEvent(accountID string, cs *cores.CallSession) {
	a.mu.Lock()
	if a.call != nil {
		a.mu.Unlock()
		return
	}
	peer := ""
	for _, c := range a.chats {
		if c.AccountID == accountID && c.ChatID == cs.ChatID {
			peer = c.Title
			break
		}
	}
	a.call = callUIFromSession(accountID, cs, peer, cs.IsVideo)
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) onCallStateEvent(accountID string, cs *cores.CallSession) {
	a.mu.Lock()
	c := a.call
	if c == nil || !c.matches(accountID, cs.ID) {
		a.mu.Unlock()
		return
	}
	now := time.Now()
	wasActive := c.state == string(cores.CallStateActive)
	changed := c.applyEvent(string(cs.State), now)
	nowActive := c.state == string(cores.CallStateActive)
	ended := c.state == string(cores.CallStateEnded)
	a.mu.Unlock()
	if !changed {
		return
	}
	if !wasActive && nowActive {
		a.startCallElapsedTicker(accountID, cs.ID)
	}
	if ended {
		go a.loadCalls()
		go a.scheduleCallDismiss()
		if callRateable(c, now) && mainOnlySurfaceShown(a) {
			a.openRateCall(c)
		}
	}
	a.invalidate()
}

func (a *App) startCallElapsedTicker(accountID, callID string) {
	go func() {
		t := time.NewTicker(time.Second)
		defer t.Stop()
		for range t.C {
			a.mu.Lock()
			want := callElapsedTickerWanted(a.call, accountID, callID)
			a.mu.Unlock()
			if !want {
				return
			}
			a.invalidate()
		}
	}()
}

func (a *App) scheduleCallDismiss() {
	time.Sleep(callDismissDelay + 500*time.Millisecond)
	a.mu.Lock()
	if a.call != nil && a.call.dismissible(time.Now()) {
		a.call = nil
	}
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) acceptCall() {
	a.mu.Lock()
	c := a.call
	if c == nil || !c.incoming || c.state != string(cores.CallStateRinging) {
		a.mu.Unlock()
		return
	}
	c.applyEvent(string(cores.CallStateConnecting), time.Now())
	accountID, callID := c.accountID, c.callID
	a.mu.Unlock()
	a.invalidate()
	go func() {
		if _, err := a.eng.AcceptCall(accountID, callID); err != nil {
			a.setToast("Answer failed: " + err.Error())
		}
	}()
}

func (a *App) declineCall() {
	a.mu.Lock()
	c := a.call
	a.call = nil
	a.mu.Unlock()
	if c == nil {
		return
	}
	a.invalidate()
	go func() {
		if err := a.eng.DeclineCall(c.accountID, c.callID); err != nil {
			a.setToast("Decline failed: " + err.Error())
		}
	}()
}

func (a *App) endCall() {
	a.mu.Lock()
	c := a.call
	if c == nil {
		a.mu.Unlock()
		return
	}
	accountID, callID := c.accountID, c.callID
	a.mu.Unlock()
	go func() {
		if err := a.eng.EndCall(accountID, callID); err != nil {
			a.setToast("End call failed: " + err.Error())
		}
	}()
}

func (a *App) toggleCallMute() {
	a.mu.Lock()
	c := a.call
	if c == nil || c.state != string(cores.CallStateActive) {
		a.mu.Unlock()
		return
	}
	c.muted = !c.muted
	muted, accountID, callID := c.muted, c.accountID, c.callID
	a.mu.Unlock()
	a.invalidate()
	go func() {
		if err := a.eng.SetCallMuted(accountID, callID, muted); err != nil {
			a.setToast("Mute failed: " + err.Error())
		}
	}()
}

func (a *App) toggleCallCamera() {
	a.mu.Lock()
	c := a.call
	if c == nil || c.state != string(cores.CallStateActive) || !c.video {
		a.mu.Unlock()
		return
	}
	c.camOn = !c.camOn
	on, accountID, callID := c.camOn, c.accountID, c.callID
	a.mu.Unlock()
	a.invalidate()
	go func() {
		if err := a.eng.ToggleCamera(accountID, callID, on); err != nil {
			a.setToast("Camera failed: " + err.Error())
		}
	}()
}

func (a *App) closeCallPanel() {
	a.mu.Lock()
	if a.call != nil && a.call.state == string(cores.CallStateEnded) {
		a.call = nil
	}
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) layoutCallOverlay(gtx layout.Context, f frame) layout.Dimensions {
	c := f.call

	gtx.Execute(key.FocusCmd{Tag: nil})

	{
		stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
		event.Op(gtx.Ops, callKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			switch c.state {
			case string(cores.CallStateRinging):
				if c.incoming {
					a.declineCall()
				} else {
					a.endCall()
				}
			case string(cores.CallStateConnecting):
				a.endCall()
			case string(cores.CallStateEnded):
				a.closeCallPanel()
			}
		}
	}

	scrim := color.NRGBA{R: 0x08, G: 0x0D, B: 0x12, A: 0xF2}
	paintFill(gtx.Ops, scrim, gtx.Constraints.Max)

	ct := c.controls()
	if ct.accept && a.wid.callAcceptBtn.Clicked(gtx) {
		a.acceptCall()
	}
	if ct.decline && a.wid.callDeclineBtn.Clicked(gtx) {
		a.declineCall()
	}
	if ct.mute && a.wid.callMuteBtn.Clicked(gtx) {
		a.toggleCallMute()
	}
	if ct.camera && a.wid.callCamBtn.Clicked(gtx) {
		a.toggleCallCamera()
	}
	if ct.end && a.wid.callEndBtn.Clicked(gtx) {
		a.endCall()
	}
	if ct.close && a.wid.callCloseBtn.Clicked(gtx) {
		a.closeCallPanel()
	}

	status := c.statusLine(f.now)
	statusColor := a.ui.p.TextDim
	if c.state == string(cores.CallStateActive) {
		statusColor = a.ui.p.Online
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Bottom: unit.Dp(18)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					if chat, ok := findChatByPeer(f, c.accountID, c.chatID); ok {
						return a.streamerAvatar(gtx, f, chat, unit.Dp(128), dotNone)
					}
					return a.ui.Avatar(gtx, c.peerName, unit.Dp(128), dotNone)
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.H2(c.peerName)
				lbl.Color = color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF}
				if f.cfg.Streamer {
					return a.masked(gtx, lbl.Layout)
				}
				return lbl.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if !c.video {
					return layout.Dimensions{}
				}
				return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(13), "video call")
					lbl.Color = a.ui.p.TextFaint
					return lbl.Layout(gtx)
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(36)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(15), status)
					lbl.Color = statusColor
					return lbl.Layout(gtx)
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.layoutCallControls(gtx, c, ct)
			}),
		)
	})
}

func (a *App) layoutCallControls(gtx layout.Context, c *callUI, ct callControls) layout.Dimensions {
	var children []layout.FlexChild
	add := func(btn *widget.Clickable, icon *widget.Icon, desc string, bg color.NRGBA, fg color.NRGBA) {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return a.callRoundButton(gtx, btn, icon, desc, bg, fg)
			})
		}))
	}
	white := color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF}
	switch {
	case ct.accept || ct.decline:
		if ct.accept {
			add(&a.wid.callAcceptBtn, iconCommunicationCall, "Answer", a.ui.p.Online, white)
		}
		if ct.decline {
			add(&a.wid.callDeclineBtn, iconContentClear, "Decline", a.ui.p.Error, white)
		}
	case ct.end:
		if ct.mute {
			if c.muted {
				add(&a.wid.callMuteBtn, iconAVMicOff, "Unmute", a.ui.p.Accent, white)
			} else {
				add(&a.wid.callMuteBtn, iconAVMic, "Mute", a.ui.p.Accent, white)
			}
		}
		if ct.camera {
			if c.camOn {
				add(&a.wid.callCamBtn, iconAVVideocamOff, "Turn camera off", a.ui.p.Accent, white)
			} else {
				add(&a.wid.callCamBtn, iconAVVideocam, "Turn camera on", a.ui.p.Accent, white)
			}
		}
		add(&a.wid.callEndBtn, iconCommunicationCallEnd, "Hang up", a.ui.p.Error, white)
	case ct.close:
		add(&a.wid.callCloseBtn, iconContentClear, "Close", a.ui.p.SurfaceHi, white)
	}
	return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx, children...)
}

func (a *App) callRoundButton(gtx layout.Context, btn *widget.Clickable, icon *widget.Icon, desc string, bg, fg color.NRGBA) layout.Dimensions {
	b := material.IconButton(a.ui.Theme, btn, icon, desc)
	b.Background = bg
	b.Color = fg
	b.Size = unit.Dp(28)
	b.Inset = layout.UniformInset(unit.Dp(18))
	return b.Layout(gtx)
}

var _ = paint.Fill
