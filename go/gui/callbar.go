package gui

import (
	"time"

	"gioui.org/layout"
	"gioui.org/unit"

	"uniclient/cores"
	"uniclient/engine"
)

const callPollInterval = 5 * time.Second

func callBarPollNeeded(c engine.ChatInfo, voiceRoom bool) bool {
	return c.HasActiveCall || voiceRoom
}

func callBarSubtitle(c engine.ChatInfo, gc *engine.GroupCallInfo, voiceRoom bool) string {
	if gc != nil && gc.TalkPowerBlocked {
		if voiceRoom {
			return "voice room · mic blocked (talk power)"
		}
		return "group call · mic blocked (talk power)"
	}
	if voiceRoom {
		if gc == nil {
			return "voice room · empty"
		}
		switch {
		case gc.ParticipantsCount == 1:
			return "voice room · 1 participant"
		case gc.ParticipantsCount > 1:
			return "voice room · " + itoa(gc.ParticipantsCount) + " participants"
		default:
			return "voice room · empty"
		}
	}
	if gc == nil {
		return "group call · live"
	}
	label := "group call · "
	switch {
	case gc.ParticipantsCount == 1:
		label += "1 participant"
	case gc.ParticipantsCount > 1:
		label += itoa(gc.ParticipantsCount) + " participants"
	default:
		label += "live"
	}
	if gc.IsRtmp {
		label += " · live stream"
	}
	return label
}

func voiceRoomChat(c engine.ChatInfo, caps []string) bool {
	if c.Type == engine.ChatTypeDMVal {
		return false
	}
	return capContains(caps, cores.CapVoiceRooms)
}

func callJoinedLabel(title string) string {
	return "Joined the group call in " + title
}

func (a *App) callBar(gtx layout.Context, f frame, chat *engine.ChatInfo) layout.Dimensions {
	if a.wid.callJoinBtn.Clicked(gtx) {
		if callBarInCall(*chat, f.joinedGC) {
			a.leaveJoinedCall()
		} else {
			a.callBarJoin(*chat)
		}
	}
	return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return iconHardwareHeadset.Layout(gtx, a.ui.p.Accent)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								title := chat.Title
								if f.groupCall != nil && f.groupCall.Title != "" {
									title = f.groupCall.Title
								}
								lbl := a.ui.Label(unit.Sp(14), title)
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(12), callBarSubtitle(*chat, f.groupCall, voiceRoomChat(*chat, f.hdrCaps)))
								lbl.Color = a.ui.p.Online
								return lbl.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						label := "JOIN"
						if callBarInCall(*chat, f.joinedGC) {
							label = "LEAVE"
						}
						btn := a.ui.PrimaryButton(&a.wid.callJoinBtn, label)
						return btn.Layout(gtx)
					}),
				)
			})
		})
	})
}

func callBarInCall(chat engine.ChatInfo, jc *joinedCall) bool {
	return jc != nil && jc.accountID == chat.AccountID && jc.chatID == chat.ChatID
}

func (a *App) callBarJoin(c engine.ChatInfo) {
	go func() {
		callID, err := a.eng.JoinGroupCall(c.AccountID, c.ChatID)
		a.applyCallJoinResult(c, callID, err)
	}()
}

func (a *App) applyCallJoinResult(c engine.ChatInfo, callID string, err error) {
	if err != nil {
		a.setToast("Join failed: " + err.Error())
		return
	}
	a.setJoinedCall(c.AccountID, callID, c.ChatID, c.Title)
	a.afterVoiceJoin(c)
	if mainOnlySurfaceShown(a) {
		a.mu.Lock()
		a.mode = 1
		a.mu.Unlock()
		go a.loadCalls()
	}
	a.invalidate()
	a.pollGroupCallOnce(c.AccountID, c.ChatID)
}

func (a *App) pollGroupCallOnce(accountID, chatID string) {
	gc, err := a.eng.GetGroupCall(accountID, chatID)
	a.mu.Lock()
	if err == nil && gc != nil && a.selected != nil && a.selected.AccountID == accountID && a.selected.ChatID == chatID {
		a.groupCall = gc
	} else if err != nil || gc == nil {
		a.groupCall = nil
	}
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) syncCallPoll() {
	a.mu.Lock()
	selected := a.selected
	var target *chatKey
	if selected != nil {
		caps := a.capsCached(selected.AccountID)
		for _, c := range a.chats {
			if c.AccountID == selected.AccountID && c.ChatID == selected.ChatID &&
				(callBarPollNeeded(c, voiceRoomChat(c, caps))) {
				k := *selected
				target = &k
				break
			}
		}
	}
	already := a.callPollFor
	a.callPollFor = target
	a.mu.Unlock()
	if target == nil {
		a.mu.Lock()
		a.groupCall = nil
		a.mu.Unlock()
		return
	}
	if already != nil && *already == *target {
		return
	}
	go func(k chatKey) {
		a.pollGroupCallOnce(k.AccountID, k.ChatID)
		t := time.NewTicker(callPollInterval)
		defer t.Stop()
		for range t.C {
			a.mu.Lock()
			cur := a.selected
			forChat := a.callPollFor
			a.mu.Unlock()
			if cur == nil || forChat == nil || *cur != k || *forChat != k {
				return
			}
			a.pollGroupCallOnce(k.AccountID, k.ChatID)
		}
	}(*target)
}

func (a *App) capsCached(accountID string) []string {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.hdrCapsFor == accountID {
		return a.hdrCaps
	}
	return nil
}
