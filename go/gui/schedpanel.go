package gui

import (
	"image"
	"strings"
	"time"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"

	"uniclient/engine"
)

// Scheduled-messages manager (AyuGram parity, matrix #scheduled-list):
// opened from the chat-header "⋮" menu. Lists the chat's scheduled
// messages (engine.GetScheduledMessages) with Send now / Reschedule /
// Delete actions. Rescheduling reuses the schedule dialog against the
// message (engine.RescheduleMessage); deletion goes through the new
// engine.DeleteScheduledMessages.

var (
	schedPanelTag = new(struct{})
)

// openSchedPanel loads the scheduled list for the open chat.
func (a *App) openSchedPanel() {
	a.mu.Lock()
	k := a.selected
	a.schedPanel = true
	a.schedMsgs = nil
	a.schedLoad = true
	a.headerMenu = nil
	a.mu.Unlock()
	a.invalidate()
	if k == nil {
		return
	}
	acc, chat := k.AccountID, k.ChatID
	go func() {
		msgs, err := a.eng.GetScheduledMessages(acc, chat)
		a.mu.Lock()
		a.schedMsgs = msgs
		a.schedLoad = false
		a.mu.Unlock()
		if err != nil {
			a.setToast("Scheduled: " + err.Error())
			return
		}
		a.invalidate()
	}()
}

// closeSchedPanel dismisses the panel.
func (a *App) closeSchedPanel() {
	a.mu.Lock()
	if !a.schedPanel {
		a.mu.Unlock()
		return
	}
	a.schedPanel = false
	a.schedMsgs = nil
	a.mu.Unlock()
	a.invalidate()
}

// reloadSchedPanel re-fetches the list (after an action).
func (a *App) reloadSchedPanel() {
	a.mu.Lock()
	k := a.selected
	a.schedMsgs = nil
	a.schedLoad = true
	a.mu.Unlock()
	a.invalidate()
	if k == nil {
		return
	}
	acc, chat := k.AccountID, k.ChatID
	go func() {
		msgs, err := a.eng.GetScheduledMessages(acc, chat)
		a.mu.Lock()
		a.schedMsgs = msgs
		a.schedLoad = false
		a.mu.Unlock()
		if err != nil {
			a.setToast("Scheduled: " + err.Error())
			return
		}
		a.invalidate()
	}()
}

// schedSendNow sends one scheduled message immediately.
func (a *App) schedSendNow(m engine.CachedMessage) {
	acc, chat, id := m.AccountID, m.ChatID, m.MsgID
	go func() {
		if err := a.eng.SendScheduledNow(acc, chat, []string{id}); err != nil {
			a.setToast("Send now failed: " + err.Error())
			return
		}
		a.setToast("Sent")
		a.reloadSchedPanel()
	}()
}

// schedDelete removes one scheduled message.
func (a *App) schedDelete(m engine.CachedMessage) {
	acc, chat, id := m.AccountID, m.ChatID, m.MsgID
	go func() {
		if err := a.eng.DeleteScheduledMessages(acc, chat, []string{id}); err != nil {
			a.setToast("Delete failed: " + err.Error())
			return
		}
		a.reloadSchedPanel()
	}()
}

// openReschedDialog preps the schedule dialog for an existing message.
func (a *App) openReschedDialog(m engine.CachedMessage) {
	a.mu.Lock()
	a.schedDlg = &schedDlgState{preset: 0, resched: &m}
	a.mu.Unlock()
	if m.ScheduleDate > 0 {
		w := time.Unix(m.ScheduleDate, 0)
		a.wid.schedDateEd.SetText(w.Format("2006-01-02"))
		a.wid.schedTimeEd.SetText(w.Format("15:04"))
	} else {
		now := time.Now().Add(time.Hour)
		a.wid.schedDateEd.SetText(now.Format("2006-01-02"))
		a.wid.schedTimeEd.SetText(now.Format("15:04"))
	}
	a.invalidate()
}

// schedRowText (pure, testable): preview line for a scheduled row.
func schedRowText(m engine.CachedMessage) string {
	txt := strings.TrimSpace(m.ContentText)
	if txt == "" && m.MediaType != 0 {
		txt = engine.MediaPreviewLabel(m.MediaType)
	}
	if txt == "" {
		txt = "(no text)"
	}
	const max = 72
	r := []rune(txt)
	if len(r) > max {
		return strings.TrimSpace(string(r[:max])) + "…"
	}
	return txt
}

// schedRowWhen (pure, testable): the time line.
func schedRowWhen(m engine.CachedMessage) string {
	if m.ScheduleDate == 0 {
		return "unscheduled"
	}
	return time.Unix(m.ScheduleDate, 0).Format("Mon 2 Jan · 15:04")
}

// layoutSchedPanel replaces the chat pane with the scheduled list.
func (a *App) layoutSchedPanel(gtx layout.Context, f frame, chat *engine.ChatInfo) layout.Dimensions {
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, schedPanelTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeSchedPanel()
		}
	}
	if a.wid.schedPanelBack.Clicked(gtx) {
		a.closeSchedPanel()
	}

	msgs := f.schedMsgs
	growClickables(&a.wid.schedRowSend, len(msgs))
	growClickables(&a.wid.schedRowResched, len(msgs))
	growClickables(&a.wid.schedRowDelete, len(msgs))
	for i, m := range msgs {
		i, m := i, m
		if a.wid.schedRowSend[i].Clicked(gtx) {
			a.schedSendNow(m)
		}
		if a.wid.schedRowResched[i].Clicked(gtx) {
			a.openReschedDialog(m)
		}
		if a.wid.schedRowDelete[i].Clicked(gtx) {
			a.schedDelete(m)
		}
	}

	title := "Scheduled messages"
	if chat != nil {
		title = "Scheduled · " + chat.Title
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		// Header.
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(8), Right: unit.Dp(12)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.IconButton(&a.wid.schedPanelBack, iconNavigationBack, "Back to chat")
							btn.Color = a.ui.p.TextDim
							return btn.Layout(gtx)
						}),
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.H3(title)
								lbl.MaxLines = 1
								return lbl.Layout(gtx)
							})
						}),
					)
				})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.ui.Divider(gtx)
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			if f.schedLoad {
				return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(14), "Loading scheduled messages…")
					return lbl.Layout(gtx)
				})
			}
			if len(msgs) == 0 {
				return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.H3("Nothing scheduled")
							lbl.Color = a.ui.p.TextFaint
							return lbl.Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(13), "Use the ⏰ button next to the message field.")
							lbl.Color = a.ui.p.TextFaint
							return lbl.Layout(gtx)
						}),
					)
				})
			}
			return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return a.wid.schedPanelList.Layout(gtx, len(msgs), func(gtx layout.Context, i int) layout.Dimensions {
					return a.schedRow(gtx, msgs[i], i)
				})
			})
		}),
	)
}

func (a *App) schedRow(gtx layout.Context, m engine.CachedMessage, i int) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4), Left: unit.Dp(8), Right: unit.Dp(8)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return roundedFill(gtx, a.ui.p.SurfaceHi, 12, func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(11), schedRowWhen(m))
							lbl.Color = a.ui.p.Accent
							return lbl.Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(14), schedRowText(m))
							lbl.MaxLines = 2
							return lbl.Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										btn := a.ui.TextButton(&a.wid.schedRowSend[i], "Send now")
										btn.Color = a.ui.p.Accent
										return btn.Layout(gtx)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										btn := a.ui.TextButton(&a.wid.schedRowResched[i], "Reschedule")
										return btn.Layout(gtx)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										btn := a.ui.TextButton(&a.wid.schedRowDelete[i], "Delete")
										btn.Color = a.ui.p.Error
										return btn.Layout(gtx)
									}),
								)
							})
						}),
					)
				})
			})
		},
	)
}

// paintAvatarRing strokes an accent ring around a size×size avatar
// (unread-stories indicator, AyuGram parity).
func paintAvatarRing(gtx layout.Context, u *UI, size int) {
	w := float32(gtx.Dp(unit.Dp(2)))
	if w < 1 {
		w = 1
	}
	pad := int(w) / 2
	spec := clip.Ellipse{Min: image.Pt(pad, pad), Max: image.Pt(size-pad, size-pad)}.Path(gtx.Ops)
	stroke := clip.Stroke{Path: spec, Width: w}
	paint.FillShape(gtx.Ops, u.p.Accent, stroke.Op())
}
