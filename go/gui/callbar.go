package gui

import (
	"time"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"

	"uniclient/cores"
	"uniclient/engine"
)

// Group-call live bar (AyuGram parity slice 70): while the open chat has an
// active group call (ChatInfo.HasActiveCall, kept current by the engine's
// chat snapshots), a live bar sits under the chat header with the call's
// title, participant count (engine.GetGroupCall, polled), and a JOIN
// button that runs the real engine join (JoinGroupCall — or Create when
// none exists) and flips to the Voice tab, where the call row already
// renders (slice 64 surface). No simulated participants: numbers come from
// the engine or the bar is omitted.

const callPollInterval = 5 * time.Second

var callJoinBtn widget.Clickable

// callBarPollNeeded reports whether the poll loop should fetch call info
// for a chat (chats with a live call, or voice-room channels whose
// occupancy changes as users join/leave).
func callBarPollNeeded(c engine.ChatInfo, voiceRoom bool) bool {
	return c.HasActiveCall || voiceRoom
}

// callBarSubtitle derives the bar's status line.
func callBarSubtitle(c engine.ChatInfo, gc *engine.GroupCallInfo, voiceRoom bool) string {
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

// voiceRoomChat reports whether the chat is a standing voice room
// (Mumble/TeamSpeak channel): the bar shows even when empty because
// joining an empty room is a real action.
func voiceRoomChat(c engine.ChatInfo, caps []string) bool {
	if c.Type == engine.ChatTypeDMVal {
		return false
	}
	return capContains(caps, cores.CapVoiceRooms)
}

// callJoinedLabel is the toast shown after a successful join.
func callJoinedLabel(title string) string {
	return "Joined the group call in " + title
}

// callBar renders the live bar under the chat header.
func (a *App) callBar(gtx layout.Context, f frame, chat *engine.ChatInfo) layout.Dimensions {
	if callJoinBtn.Clicked(gtx) {
		acc, id, title := chat.AccountID, chat.ChatID, chat.Title
		go func() {
			callID, err := a.eng.JoinGroupCall(acc, id)
			if err != nil {
				a.setToast("Join failed: " + err.Error())
				return
			}
			// Slice 102: record the joined call — the Voice tab becomes
			// the group-call screen (participants, mute, leave).
			a.setJoinedCall(acc, callID, id, title)
			a.afterVoiceJoin(engine.ChatInfo{AccountID: acc, ChatID: id, Title: title})
			a.mu.Lock()
			a.mode = 1
			a.mu.Unlock()
			go a.loadCalls() // Voice tab surface (slice 64)
			a.invalidate()
			a.pollGroupCallOnce(acc, id)
		}()
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
						btn := a.ui.PrimaryButton(&callJoinBtn, "JOIN")
						return btn.Layout(gtx)
					}),
				)
			})
		})
	})
}

// pollGroupCallOnce fetches call info for a chat and stores it.
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

// syncCallPoll starts/stops the background poll loop for the open chat.
// Called on chat open and whenever the chat list refreshes (HasActiveCall
// can flip at any time from engine events).
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
		return // loop is already watching this chat
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

// capsCached returns the cached account capabilities (the header caps
// load keeps them fresh); an empty list is conservative and honest.
func (a *App) capsCached(accountID string) []string {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.hdrCapsFor == accountID {
		return a.hdrCaps
	}
	return nil
}
