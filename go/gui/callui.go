package gui

// 1:1 call overlay (AyuGram parity slice 101): DM calls surfaced from the
// engine's complete call API. The chat header gains phone/video buttons for
// callable DMs (capability-gated), StartCall raises the full-window call
// panel, EventIncomingCall raises the ringing overlay with accept/decline,
// and EventCallState drives ringing → connecting → active → ended. Controls
// dispatch real engine calls: SetCallMuted, ToggleCamera, EndCall/DeclineCall.
// The panel auto-dismisses a few seconds after the call ends (AyuGram shows
// the ended state briefly). No simulated audio levels — the panel shows only
// what the engine reports.

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

// callUI is the 1:1 (DM) call session driving the overlay (slice 101).
type callUI struct {
	accountID string
	callID    string
	chatID    string
	peerName  string
	video     bool
	incoming  bool // ringing from the peer (vs. our outgoing call)

	state     string    // cores.CallState string
	startedAt time.Time // stamped on the first active transition
	endedAt   time.Time // stamped on the ended transition

	muted bool // local mirror of SetCallMuted
	camOn bool // local mirror of ToggleCamera
}

// callDismissDelay is how long the ended panel stays up before closing.
const callDismissDelay = 4 * time.Second

// dmCallButtons decides whether the chat header shows the 1:1 call buttons.
// Only DMs on accounts with the CALLS capability and non-bot peers — groups
// and channels use the group-call bar instead (slice 70).
func dmCallButtons(c engine.ChatInfo, caps []string) (voice, video bool) {
	if c.Type != engine.ChatTypeDMVal || c.IsBot {
		return false, false
	}
	if !capContains(caps, cores.CapCalls) {
		return false, false
	}
	return true, true
}

// capContains reports whether caps contains want.
func capContains(caps []string, want string) bool {
	for _, c := range caps {
		if c == want {
			return true
		}
	}
	return false
}

// newOutgoingCall builds the panel state for a call we placed.
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

// callUIFromSession builds the panel state for an incoming ringing call.
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

// matches reports whether an event belongs to this call session.
func (c *callUI) matches(accountID, callID string) bool {
	return c.accountID == accountID && c.callID == callID
}

// applyEvent folds one engine call-state transition into the session.
// Monotonic: ended is terminal, stale ringing never rewinds an active call,
// and startedAt is stamped exactly once (the elapsed timer is stable).
// Returns whether anything changed (caller invalidates).
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
			return false // initial only
		}
		c.state = state
		return true
	}
	return false
}

// statusLine renders the panel's status text for the current state.
func (c *callUI) statusLine(now time.Time) string {
	switch c.state {
	case string(cores.CallStateEnded):
		if !c.startedAt.IsZero() {
			// Frozen at the moment the call ended.
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

// callControls is the visible control set for the current state.
type callControls struct {
	accept  bool // incoming ringing: green answer button
	decline bool // incoming ringing: red hang-up button
	mute    bool // active: mic toggle
	camera  bool // active video: camera toggle
	end     bool // ringing/connecting/active: red hang-up
	close   bool // ended: dismiss
}

// controls derives the buttons from the call state.
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

// dismissible reports whether the ended panel may auto-close.
func (c *callUI) dismissible(now time.Time) bool {
	return c.state == string(cores.CallStateEnded) && !c.endedAt.IsZero() && now.Sub(c.endedAt) >= callDismissDelay
}

// callElapsedTickerWanted: the 1s invalidation loop runs only while this
// exact call session is active (the timer needs a redraw every second).
func callElapsedTickerWanted(c *callUI, accountID, callID string) bool {
	return c != nil && c.matches(accountID, callID) && c.state == string(cores.CallStateActive)
}

// ── button pool ───────────────────────────────────────────────────────────

var (
	callAcceptBtn  widget.Clickable
	callDeclineBtn widget.Clickable
	callMuteBtn    widget.Clickable
	callCamBtn     widget.Clickable
	callEndBtn     widget.Clickable
	callCloseBtn   widget.Clickable

	callKeyTag = new(bool) // overlay keyboard layer
)

// ── state transitions ─────────────────────────────────────────────────────

// loadHdrCaps caches the open chat's account capabilities for the header's
// call buttons (slice 101). One fetch per account per session.
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

// startDMCall places a 1:1 call from the chat header (slice 101).
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

// onIncomingCallEvent: EventIncomingCall → ringing overlay (slice 101).
// The peer name resolves from the loaded chat list; the avatar follows at
// render time from the same source. Only one 1:1 call surface at a time —
// a second ringing call is dropped (the engine keeps its own state).
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

// onCallStateEvent: EventCallState → state machine (slice 101).
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
		go a.loadCalls() // the history row appears server-side
		go a.scheduleCallDismiss()
	}
	a.invalidate()
}

// startCallElapsedTicker redraws every second while the call is active.
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

// scheduleCallDismiss closes the ended panel after its brief display.
func (a *App) scheduleCallDismiss() {
	time.Sleep(callDismissDelay + 500*time.Millisecond)
	a.mu.Lock()
	if a.call != nil && a.call.dismissible(time.Now()) {
		a.call = nil
	}
	a.mu.Unlock()
	a.invalidate()
}

// acceptCall answers the ringing incoming call.
func (a *App) acceptCall() {
	a.mu.Lock()
	c := a.call
	if c == nil || !c.incoming || c.state != string(cores.CallStateRinging) {
		a.mu.Unlock()
		return
	}
	// Optimistic: the panel flips to connecting immediately; the engine's
	// call-state event drives the rest.
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

// declineCall rejects the ringing incoming call and closes the panel.
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

// endCall hangs up the outgoing/active call; the panel stays for the ended
// summary (the engine's ended event or the dismiss timer clears it).
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

// toggleCallMute flips the mic and applies it to the engine.
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

// toggleCallCamera flips the outgoing video track (video calls only).
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

// closeCallPanel dismisses the ended panel.
func (a *App) closeCallPanel() {
	a.mu.Lock()
	if a.call != nil && a.call.state == string(cores.CallStateEnded) {
		a.call = nil
	}
	a.mu.Unlock()
	a.invalidate()
}

// ── layout ────────────────────────────────────────────────────────────────

// layoutCallOverlay renders the 1:1 call surface over the whole window
// (slice 101): dark backdrop, peer avatar, name, status/timer, controls.
func (a *App) layoutCallOverlay(gtx layout.Context, f frame) layout.Dimensions {
	c := f.call

	// Keep keyboard focus out of the covered composer.
	gtx.Execute(key.FocusCmd{Tag: nil})

	// Keyboard: Escape declines an incoming ring, cancels an outgoing
	// ring/connect, dismisses the ended panel — never silently hangs up an
	// active call (that needs the explicit red button).
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

	// Full-window dark backdrop.
	scrim := color.NRGBA{R: 0x08, G: 0x0D, B: 0x12, A: 0xF2}
	paintFill(gtx.Ops, scrim, gtx.Constraints.Max)

	ct := c.controls()
	if ct.accept && callAcceptBtn.Clicked(gtx) {
		a.acceptCall()
	}
	if ct.decline && callDeclineBtn.Clicked(gtx) {
		a.declineCall()
	}
	if ct.mute && callMuteBtn.Clicked(gtx) {
		a.toggleCallMute()
	}
	if ct.camera && callCamBtn.Clicked(gtx) {
		a.toggleCallCamera()
	}
	if ct.end && callEndBtn.Clicked(gtx) {
		a.endCall()
	}
	if ct.close && callCloseBtn.Clicked(gtx) {
		a.closeCallPanel()
	}

	status := c.statusLine(f.now)
	statusColor := a.ui.p.TextDim
	if c.state == string(cores.CallStateActive) {
		statusColor = a.ui.p.Online
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
			// Peer avatar: real userpic when the chat is loaded.
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Bottom: unit.Dp(18)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					if chat, ok := findChatByPeer(f, c.accountID, c.chatID); ok {
						return a.streamerAvatar(gtx, f, chat, unit.Dp(128), dotNone)
					}
					return a.ui.Avatar(gtx, c.peerName, unit.Dp(128), dotNone)
				})
			}),
			// Peer name (masked in streamer mode — identity leaks).
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.H2(c.peerName)
				lbl.Color = color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF}
				if f.cfg.Streamer {
					return a.masked(gtx, lbl.Layout)
				}
				return lbl.Layout(gtx)
			}),
			// Video-call tag.
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
			// Status line / elapsed timer.
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(36)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(15), status)
					lbl.Color = statusColor
					return lbl.Layout(gtx)
				})
			}),
			// Control row.
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.layoutCallControls(gtx, c, ct)
			}),
		)
	})
}

// layoutCallControls renders the round control buttons for the state.
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
			add(&callAcceptBtn, iconCommunicationCall, "Answer", a.ui.p.Online, white)
		}
		if ct.decline {
			add(&callDeclineBtn, iconContentClear, "Decline", a.ui.p.Error, white)
		}
	case ct.end:
		if ct.mute {
			if c.muted {
				add(&callMuteBtn, iconAVMicOff, "Unmute", a.ui.p.Accent, white)
			} else {
				add(&callMuteBtn, iconAVMic, "Mute", a.ui.p.Accent, white)
			}
		}
		if ct.camera {
			if c.camOn {
				add(&callCamBtn, iconAVVideocamOff, "Turn camera off", a.ui.p.Accent, white)
			} else {
				add(&callCamBtn, iconAVVideocam, "Turn camera on", a.ui.p.Accent, white)
			}
		}
		add(&callEndBtn, iconCommunicationCallEnd, "Hang up", a.ui.p.Error, white)
	case ct.close:
		add(&callCloseBtn, iconContentClear, "Close", a.ui.p.SurfaceHi, white)
	}
	return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx, children...)
}

// callRoundButton renders a 64dp circular icon button.
func (a *App) callRoundButton(gtx layout.Context, btn *widget.Clickable, icon *widget.Icon, desc string, bg, fg color.NRGBA) layout.Dimensions {
	b := material.IconButton(a.ui.Theme, btn, icon, desc)
	b.Background = bg
	b.Color = fg
	b.Size = unit.Dp(28)
	b.Inset = layout.UniformInset(unit.Dp(18))
	return b.Layout(gtx)
}

var _ = paint.Fill
