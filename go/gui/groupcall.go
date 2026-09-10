package gui

// Group-call screen (AyuGram parity slice 102): joining a group call (the
// chat's live-call bar) now raises a real call screen in the Voice tab —
// participants with speaking/muted/hand-raised/video states from the
// engine's polled group-call info, self sorted first, and controls that
// dispatch real engine calls (SetCallMuted / RaiseHand / LeaveGroupCall).
// The poll ends and the screen closes when the engine reports the call no
// longer active — honest empty/exit states only (§1.10).

import (
	"image/color"
	"time"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/cores"
	"uniclient/engine"
)

// gcPollInterval: how often the joined call screen refreshes participants.
// Faster than the call-bar poll — speaking indicators need fresher data.
const gcPollInterval = 2 * time.Second

// joinedCall is the group call the user is currently in (slice 102).
type joinedCall struct {
	accountID  string
	callID     string
	chatID     string
	title      string // chat title fallback
	muted      bool   // local mirror of SetCallMuted (optimistic)
	handRaised bool   // local mirror of RaiseHand (optimistic)
	noiseOn    bool   // local mirror of SetNoiseSuppression (slice 103)
}

var (
	gcList       widget.List
	gcMuteBtn    widget.Clickable
	gcHandBtn    widget.Clickable
	gcNoiseBtn   widget.Clickable
	gcLeaveBtn   widget.Clickable
	gcRowJoinMap = map[string]*widget.Clickable{} // chatID → join button
)

// gcRowJoinBtnFor returns the per-row join clickable (pool keyed by chat).
func gcRowJoinBtnFor(chatID string) *widget.Clickable {
	if btn, ok := gcRowJoinMap[chatID]; ok {
		return btn
	}
	btn := new(widget.Clickable)
	gcRowJoinMap[chatID] = btn
	if len(gcRowJoinMap) > 64 {
		gcRowJoinMap = map[string]*widget.Clickable{chatID: btn}
	}
	return btn
}

func init() {
	gcList.Axis = layout.Vertical
}

// ── pure derivations ──────────────────────────────────────────────────────

// gcSelf finds self in the participant list (nil when absent).
func gcSelf(ps []engine.GroupCallParticipant, selfID string) *engine.GroupCallParticipant {
	if selfID == "" {
		return nil
	}
	for i := range ps {
		if ps[i].UserID == selfID {
			return &ps[i]
		}
	}
	return nil
}

// gcSelfMuted decides the mute toggle's state: the server's word when self
// is listed; the optimistic local mirror until then.
func gcSelfMuted(ps []engine.GroupCallParticipant, selfID string, localMuted bool) bool {
	if p := gcSelf(ps, selfID); p != nil {
		return p.IsMuted
	}
	return localMuted
}

// gcShowRaiseHand: the hand button appears only for force-muted self (muted
// by an admin, cannot self-unmute) — AyuGram's use case for raising a hand.
func gcShowRaiseHand(ps []engine.GroupCallParticipant, selfID string) bool {
	p := gcSelf(ps, selfID)
	return p != nil && p.IsMuted && !p.CanSelfUnmute
}

// gcRow is one rendered participant row.
type gcRow struct {
	name     string
	self     bool
	speaking bool
	muted    bool
	hand     bool
	video    bool
}

// gcRows maps engine participants to render rows, self first.
func gcRows(ps []engine.GroupCallParticipant, selfID string) []gcRow {
	rows := make([]gcRow, 0, len(ps))
	for _, p := range ps {
		rows = append(rows, gcRow{
			name:     p.DisplayName,
			self:     p.UserID == selfID && selfID != "",
			speaking: p.IsSpeaking,
			muted:    p.IsMuted,
			hand:     p.RaisedHandRating > 0,
			video:    p.HasVideo,
		})
	}
	if selfID != "" {
		// Stable partition: self first, everyone else keeps order.
		var self, others []gcRow
		for _, r := range rows {
			if r.self {
				self = append(self, r)
			} else {
				others = append(others, r)
			}
		}
		rows = append(self, others...)
	}
	for i := range rows {
		if rows[i].name == "" {
			rows[i].name = "Participant"
		}
	}
	return rows
}

// gcCountLabel renders the participant count line.
func gcCountLabel(n int) string {
	switch {
	case n <= 0:
		return "no participants yet"
	case n == 1:
		return "1 participant"
	default:
		return itoa(n) + " participants"
	}
}

// voiceRoomCaps reports whether an account's capabilities mark it as a
// standing voice-room backend (Mumble, TeamSpeak).
func voiceRoomCaps(caps []string) bool { return capContains(caps, cores.CapVoiceRooms) }

// gcJoinedTitle picks the call's display title (server title beats chat
// title fallback).
func gcJoinedTitle(gc *engine.GroupCallInfo, fallback string) string {
	if gc != nil && gc.Title != "" {
		return gc.Title
	}
	return fallback
}

// ── state transitions ─────────────────────────────────────────────────────

// setJoinedCall records a successful group-call join (slice 102) and starts
// the participant poll.
func (a *App) setJoinedCall(accountID, callID, chatID, title string) {
	a.mu.Lock()
	a.joinedGC = &joinedCall{
		accountID: accountID,
		callID:    callID,
		chatID:    chatID,
		title:     title,
		muted:     true, // Telegram joins group calls muted by default
	}
	a.mu.Unlock()
	a.startJoinedCallPoll()
	a.invalidate()
}

// startJoinedCallPoll polls the joined call's participants until it ends.
func (a *App) startJoinedCallPoll() {
	go func() {
		a.pollJoinedCallOnce()
		t := time.NewTicker(gcPollInterval)
		defer t.Stop()
		for range t.C {
			a.mu.Lock()
			jc := a.joinedGC
			a.mu.Unlock()
			if jc == nil {
				return
			}
			a.pollJoinedCallOnce()
		}
	}()
}

// pollJoinedCallOnce refreshes the joined call's participant snapshot; a
// call reported inactive closes the screen (the user was removed / the call
// ended server-side).
func (a *App) pollJoinedCallOnce() {
	a.mu.Lock()
	jc := a.joinedGC
	a.mu.Unlock()
	if jc == nil {
		return
	}
	gc, err := a.eng.GetGroupCall(jc.accountID, jc.chatID)
	a.mu.Lock()
	if a.joinedGC != nil && a.joinedGC.callID == jc.callID {
		switch {
		case err != nil || gc == nil:
			// Keep the last known snapshot — transient fetch errors must
			// not blank the screen.
		case gc.Active:
			a.joinedGCInfo = gc
		default:
			a.joinedGC, a.joinedGCInfo = nil, nil
			go a.loadCalls()
		}
	}
	a.mu.Unlock()
	a.invalidate()
}

// leaveJoinedCall leaves the joined group call (button + call ended).
func (a *App) leaveJoinedCall() {
	a.mu.Lock()
	jc := a.joinedGC
	a.joinedGC, a.joinedGCInfo = nil, nil
	a.mu.Unlock()
	a.invalidate()
	if jc == nil {
		return
	}
	go func() {
		if err := a.eng.LeaveGroupCall(jc.accountID, jc.callID); err != nil {
			a.setToast("Leave failed: " + err.Error())
			return
		}
		a.setToast("Left the group call")
		a.loadCalls()
	}()
}

// toggleJoinedMute flips the mic in the joined call.
func (a *App) toggleJoinedMute() {
	a.mu.Lock()
	jc := a.joinedGC
	if jc == nil {
		a.mu.Unlock()
		return
	}
	jc.muted = !jc.muted
	muted, accountID, callID := jc.muted, jc.accountID, jc.callID
	a.mu.Unlock()
	a.invalidate()
	go func() {
		if err := a.eng.SetCallMuted(accountID, callID, muted); err != nil {
			a.setToast("Mute failed: " + err.Error())
		}
	}()
}

// toggleJoinedHand raises/lowers the hand (force-muted self only).
func (a *App) toggleJoinedHand() {
	a.mu.Lock()
	jc := a.joinedGC
	if jc == nil {
		a.mu.Unlock()
		return
	}
	jc.handRaised = !jc.handRaised
	raised, accountID, callID := jc.handRaised, jc.accountID, jc.callID
	a.mu.Unlock()
	a.invalidate()
	go func() {
		if err := a.eng.RaiseHand(accountID, callID, raised); err != nil {
			a.setToast("Raise hand failed: " + err.Error())
		}
	}()
}

// toggleJoinedNoise flips the in-call noise suppression (slice 103).
func (a *App) toggleJoinedNoise() {
	a.mu.Lock()
	jc := a.joinedGC
	if jc == nil {
		a.mu.Unlock()
		return
	}
	jc.noiseOn = !jc.noiseOn
	on, accountID, callID := jc.noiseOn, jc.accountID, jc.callID
	a.mu.Unlock()
	a.invalidate()
	go func() {
		if err := a.eng.SetNoiseSuppression(accountID, callID, on); err != nil {
			a.setToast("Noise suppression failed: " + err.Error())
		}
	}()
}

// joinGroupCallFromVoice joins from a Voice-tab row (slice 102: the Join
// button became real — it was informational-only before the call screen).
func (a *App) joinGroupCallFromVoice(c engine.ChatInfo) {
	go func() {
		id, err := a.eng.JoinGroupCall(c.AccountID, c.ChatID)
		if err != nil {
			a.setToast("Join failed: " + err.Error())
			return
		}
		a.setJoinedCall(c.AccountID, id, c.ChatID, c.Title)
		a.afterVoiceJoin(c)
	}()
}

// afterVoiceJoin surfaces the join result: the toast plus — when the
// device layer is unavailable (Android today) — an honest notice that
// mic and speaker are off rather than a silent half-working room.
func (a *App) afterVoiceJoin(c engine.ChatInfo) {
	if voiceRoomCaps(a.capsCached(c.AccountID)) {
		a.setToast("Joined the voice room " + c.Title)
	} else {
		a.setToast(callJoinedLabel(c.Title))
	}
	if err := a.eng.AudioDeviceError(); err != nil {
		a.setToast("Microphone and speaker unavailable: " + err.Error())
	}
}

// ── layout ────────────────────────────────────────────────────────────────

// layoutGroupCallScreen: the joined-call surface replacing the Voice tab
// content while in a call (slice 102).
func (a *App) layoutGroupCallScreen(gtx layout.Context, f frame) layout.Dimensions {
	jc := f.joinedGC
	info := f.joinedGCInfo
	selfID := accountByID(f, jc.accountID).SelfUserID
	var ps []engine.GroupCallParticipant
	if info != nil {
		ps = info.Participants
	}
	rows := gcRows(ps, selfID)

	muted := gcSelfMuted(ps, selfID, jc.muted)
	showHand := gcShowRaiseHand(ps, selfID)
	if gcMuteBtn.Clicked(gtx) {
		a.toggleJoinedMute()
	}
	if gcHandBtn.Clicked(gtx) {
		a.toggleJoinedHand()
	}
	if gcNoiseBtn.Clicked(gtx) {
		a.toggleJoinedNoise()
	}
	if gcLeaveBtn.Clicked(gtx) {
		a.leaveJoinedCall()
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		// Header: call title + live count + leave button.
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(14), Left: unit.Dp(18), Right: unit.Dp(18), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								title := jc.title
								if info != nil && info.Title != "" {
									title = info.Title
								}
								if f.cfg.Streamer {
									return a.masked(gtx, a.ui.H2(title).Layout)
								}
								return a.ui.H2(title).Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(13), gcLiveLabel(info))
								lbl.Color = a.ui.p.Online
								return lbl.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.PrimaryButton(&gcLeaveBtn, "LEAVE")
						btn.Background = a.ui.p.Error
						return btn.Layout(gtx)
					}),
				)
			})
		}),
		// Controls row: mute (state-aware) + raise hand (force-muted only).
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Left: unit.Dp(18), Right: unit.Dp(18), Bottom: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				var children []layout.FlexChild
				children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					label := "MUTE"
					if muted {
						label = "UNMUTE"
					}
					btn := a.ui.PrimaryButton(&gcMuteBtn, label)
					if muted {
						btn.Background = a.ui.p.Error
					}
					return btn.Layout(gtx)
				}))
				if showHand {
					children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							label := "RAISE HAND"
							if jc.handRaised {
								label = "LOWER HAND"
							}
							btn := a.ui.PrimaryButton(&gcHandBtn, label)
							return btn.Layout(gtx)
						})
					}))
				}
				if !voiceRoomCaps(a.capsCached(jc.accountID)) {
					children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.PrimaryButton(&gcNoiseBtn, gcNoiseLabel(jc.noiseOn))
							if jc.noiseOn {
								btn.Background = a.ui.p.Online
							}
							return btn.Layout(gtx)
						})
					}))
				}
				return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, children...)
			})
		}),
		// Participants.
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			if len(rows) == 0 {
				return layout.Inset{Left: unit.Dp(18), Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(13), "Connecting to the call…")
					lbl.Color = a.ui.p.TextFaint
					return lbl.Layout(gtx)
				})
			}
			list := material.List(a.ui.Theme, &gcList)
			return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return list.Layout(gtx, len(rows), func(gtx layout.Context, i int) layout.Dimensions {
					return a.gcParticipantRow(gtx, f, rows[i])
				})
			})
		}),
	)
}

// gcLiveLabel renders the count line under the title.
func gcLiveLabel(info *engine.GroupCallInfo) string {
	if info == nil {
		return "group call · live"
	}
	label := "group call · "
	if info.ParticipantsCount > 0 {
		label += gcCountLabel(info.ParticipantsCount)
	} else if len(info.Participants) > 0 {
		label += gcCountLabel(len(info.Participants))
	} else {
		label += "live"
	}
	if info.IsRtmp {
		label += " · live stream"
	}
	return label
}

// gcParticipantRow renders one participant (self first, flagged "You").
func (a *App) gcParticipantRow(gtx layout.Context, f frame, r gcRow) layout.Dimensions {
	name := r.name
	subColor := a.ui.p.TextDim
	var sub string
	switch {
	case r.speaking:
		sub = "speaking"
		subColor = a.ui.p.Online
	case r.hand:
		sub = "hand raised"
	case r.muted && r.self:
		sub = "you are muted"
	case r.muted:
		sub = "muted"
	}
	return layout.Inset{Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							// Speaking participants get the online dot.
							dot := dotNone
							if r.speaking {
								dot = dotOnline
							}
							return a.ui.Avatar(gtx, name, unit.Dp(40), dot)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								shown := name
								if r.self {
									shown = name + " (You)"
								}
								lbl := a.ui.Label(unit.Sp(15), shown)
								if f.cfg.Streamer {
									return a.masked(gtx, lbl.Layout)
								}
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								if sub == "" {
									return layout.Dimensions{}
								}
								lbl := a.ui.Dim(unit.Sp(12), sub)
								lbl.Color = subColor
								if f.cfg.Streamer {
									return a.masked(gtx, lbl.Layout)
								}
								return lbl.Layout(gtx)
							}),
						)
					}),
					// State icons: mic-off / hand / video.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						type ic struct {
							icon  *widget.Icon
							color color.NRGBA
						}
						var icons []ic
						if r.muted {
							icons = append(icons, ic{iconAVMicOff, a.ui.p.TextDim})
						}
						if r.hand {
							icons = append(icons, ic{iconActionInfo, a.ui.p.Accent})
						}
						if r.video {
							icons = append(icons, ic{iconAVVideocam, a.ui.p.TextDim})
						}
						if len(icons) == 0 {
							return layout.Dimensions{}
						}
						var children []layout.FlexChild
						for _, x := range icons {
							x := x
							children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									gtx.Constraints.Max.X = gtx.Dp(unit.Dp(20))
									gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(20))
									return x.icon.Layout(gtx, x.color)
								})
							}))
						}
						return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, children...)
					}),
				)
			})
		})
	})
}
