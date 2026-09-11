package gui

// mutedlg.go — slice 134: the mute-duration picker (tdesktop's "Mute for"
// dialog). The notifications switch stays the instant on/off; the clock
// chip next to it opens this picker with Telegram's presets
// (1 hour / 8 hours / 2 days / until turned back on) plus an Unmute row.
// Timed mutes ride engine.MuteChat(muted, durationSeconds) → the core's
// MuteChatFor (account.updateNotifySettings mute_until).

import (
	"image"
	"time"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"
)

// mutePreset is one "Mute for…" option.
type mutePreset struct {
	label string
	secs  int
}

// mutePresets: tdesktop's list (forever = secs 0 → plain muted flag).
var mutePresets = []mutePreset{
	{"1 hour", 3600},
	{"8 hours", 8 * 3600},
	{"2 days", 2 * 86400},
	{"Until turned back on", 0},
}

// mutePresetAction maps a preset to the engine wire (muted flag +
// duration). Pure — unit-tested.
func mutePresetAction(secs int) (muted bool, duration int32) {
	return true, int32(secs)
}

// muteDlgState is the open mute picker.
type muteDlgState struct {
	accountID string
	chatID    string
	title     string
}

var (
	muteDlgCancelBtn widget.Clickable
	muteDlgRowBtns   []widget.Clickable
	muteDlgUnmuteBtn widget.Clickable
	muteDlgKeyTag    = new(struct{})
)

// openMuteDialog opens the mute-duration picker for the open chat.
func (a *App) openMuteDialog(k chatKey, title string) {
	a.mu.Lock()
	a.muteDlg = &muteDlgState{accountID: k.AccountID, chatID: k.ChatID, title: title}
	a.mu.Unlock()
	a.invalidate()
}

// closeMuteDialog dismisses it.
func (a *App) closeMuteDialog() {
	a.mu.Lock()
	a.muteDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// applyMutePreset applies a picked preset (async + toast).
func (a *App) applyMutePreset(accountID, chatID string, secs int) {
	muted, dur := mutePresetAction(secs)
	label := "Muted"
	if secs > 0 {
		label = "Muted · " + ttlLabel(secs)
	}
	a.closeMuteDialog()
	go func() {
		if err := a.eng.MuteChat(accountID, chatID, muted, dur); err != nil {
			a.setToast("Mute failed: " + err.Error())
			return
		}
		a.setToast(label)
	}()
}

// applyUnmute unmutes the chat (async + toast).
func (a *App) applyUnmute(accountID, chatID string) {
	a.closeMuteDialog()
	go func() {
		if err := a.eng.MuteChat(accountID, chatID, false, 0); err != nil {
			a.setToast("Unmute failed: " + err.Error())
			return
		}
		a.setToast("Notifications on")
	}()
}

// layoutMuteDialog renders the duration picker (content-pane replacement,
// like the other header dialogs).
func (a *App) layoutMuteDialog(gtx layout.Context, f frame) layout.Dimensions {
	st := f.muteDlg
	growClickables(&muteDlgRowBtns, len(mutePresets))

	// Esc closes (self-handled).
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, muteDlgKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeMuteDialog()
		}
	}
	if muteDlgCancelBtn.Clicked(gtx) {
		a.closeMuteDialog()
	}
	for i := range mutePresets {
		if muteDlgRowBtns[i].Clicked(gtx) {
			a.applyMutePreset(st.accountID, st.chatID, mutePresets[i].secs)
			return layout.Dimensions{}
		}
	}
	if muteDlgUnmuteBtn.Clicked(gtx) {
		a.applyUnmute(st.accountID, st.chatID)
		return layout.Dimensions{}
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(320))
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(420))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.H3("Mute for…")
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if st.title == "" {
							return layout.Dimensions{}
						}
						return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(12), st.title)
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
								flexChildrenOf(len(mutePresets), func(gtx layout.Context, i int) layout.Dimensions {
									return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
										btn := material.Button(a.ui.Theme, &muteDlgRowBtns[i], mutePresets[i].label)
										btn.CornerRadius = 10
										btn.Inset = layout.UniformInset(unit.Dp(9))
										btn.Background = a.ui.p.SurfaceHi
										btn.Color = a.ui.p.Text
										return btn.Layout(gtx)
									})
								})...)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.TextButton(&muteDlgUnmuteBtn, "Unmute")
							btn.Color = a.ui.p.Accent
							return btn.Layout(gtx)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Dimensions{}
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						btn := material.Button(a.ui.Theme, &muteDlgCancelBtn, "Cancel")
						btn.Background = a.ui.p.SurfaceHi
						btn.Color = a.ui.p.Text
						btn.CornerRadius = 10
						return btn.Layout(gtx)
					}),
				)
			})
		})
	})
}

// muteClockBtn opens the picker from the notifications row.
var muteClockBtn widget.Clickable

// muteRowWithPicker renders the notifications row with the duration chip.
// While a timed mute is active the label gains a "Muted until …" subtitle
// (slice 136) that re-renders on the minute.
func (a *App) muteRowWithPicker(gtx layout.Context, f frame, k chatKey, sw *widget.Bool) layout.Dimensions {
	if muteClockBtn.Clicked(gtx) {
		title := ""
		a.mu.Lock()
		for i := range a.chats {
			if a.chats[i].AccountID == k.AccountID && a.chats[i].ChatID == k.ChatID {
				title = a.chats[i].Title
				break
			}
		}
		a.mu.Unlock()
		a.openMuteDialog(k, title)
	}
	// Timed-mute subtitle + minute-boundary tick.
	sub := ""
	var muteUntil int64
	a.mu.Lock()
	for i := range a.chats {
		if a.chats[i].AccountID == k.AccountID && a.chats[i].ChatID == k.ChatID {
			if a.chats[i].IsMuted && a.chats[i].MuteUntil > 0 {
				muteUntil = a.chats[i].MuteUntil
				sub = "Muted until " + formatMutedUntil(muteUntil, time.Now().Unix())
			}
			break
		}
	}
	a.mu.Unlock()
	if muteUntil > 0 {
		now := time.Now()
		nextMinute := now.Truncate(time.Minute).Add(time.Minute + 50*time.Millisecond)
		gtx.Execute(op.InvalidateCmd{At: nextMinute})
	}
	return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return iconSocialNotif.Layout(gtx, a.ui.p.TextDim)
			}),
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					title := a.ui.Label(unit.Sp(14), "Notifications")
					if sub == "" {
						return title.Layout(gtx)
					}
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return title.Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(11), sub)
							return lbl.Layout(gtx)
						}),
					)
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.IconButton(&muteClockBtn, iconActionSchedule, "Mute duration")
				btn.Color = a.ui.p.TextDim
				return btn.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				sw2 := material.Switch(a.ui.Theme, sw, "")
				sw2.Color.Enabled = a.ui.p.Accent
				sw2.Color.Disabled = a.ui.p.SurfaceHi
				sw2.Color.Track = a.ui.p.SurfaceHi
				return sw2.Layout(gtx)
			}),
		)
	})
}
