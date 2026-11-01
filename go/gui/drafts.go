package gui

import (
	"image"
	"strings"
	"time"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/cores"
	"uniclient/engine"
)

type schedDlgState struct {
	preset  int
	when    time.Time
	busy    bool
	resched *engine.CachedMessage
}

var (
	schedKeyTag = new(struct{})
)

func schedulePresetWhen(preset int, now time.Time) (time.Time, bool) {
	switch preset {
	case 1:
		return now.Add(2 * time.Hour), true
	case 2:
		d := time.Date(now.Year(), now.Month(), now.Day(), 9, 0, 0, 0, now.Location())
		if !d.After(now) {
			d = d.AddDate(0, 0, 1)
		}
		return d, true
	default:
		return time.Time{}, false
	}
}

func parseScheduleInput(dateStr, timeStr string) (int64, bool) {
	dateStr = strings.TrimSpace(dateStr)
	timeStr = strings.TrimSpace(timeStr)
	d, err := time.ParseInLocation("2006-01-02", dateStr, time.Local)
	if err != nil {
		return 0, false
	}
	hm, err := time.ParseInLocation("15:04", timeStr, time.Local)
	if err != nil {
		return 0, false
	}
	when := time.Date(d.Year(), d.Month(), d.Day(), hm.Hour(), hm.Minute(), 0, 0, time.Local)
	return when.Unix(), true
}

func draftPreview(text string) string {
	const max = 48
	r := []rune(text)
	if len(r) > max {
		r = r[:max]
	}
	return "Draft: " + string(r)
}

func (a *App) flushDraft(k chatKey) {
	text := strings.TrimSpace(a.wid.composer.Text())
	a.mu.Lock()
	var prev engine.ChatInfo
	for _, c := range a.chats {
		if c.AccountID == k.AccountID && c.ChatID == k.ChatID {
			prev = c
			break
		}
	}
	a.mu.Unlock()
	if prev.DraftText == text {
		return
	}
	go func() {
		if err := a.eng.SaveDraft(k.AccountID, k.ChatID, text); err != nil {
			a.setToast("Draft save failed: " + err.Error())
			return
		}
		a.refreshChats()
	}()
}

func (a *App) clearDraft(k chatKey) {
	go func() {
		if err := a.eng.SaveDraft(k.AccountID, k.ChatID, ""); err == nil {
			a.refreshChats()
		}
	}()
}

func (a *App) openScheduleDialog() {
	a.mu.Lock()
	a.schedDlg = &schedDlgState{preset: 1, when: time.Now().Add(2 * time.Hour)}
	a.mu.Unlock()
	now := time.Now()
	a.wid.schedDateEd.SetText(now.Format("2006-01-02"))
	a.wid.schedTimeEd.SetText(now.Add(2 * time.Hour).Format("15:04"))
	a.invalidate()
}

func (a *App) closeScheduleDialog() {
	a.mu.Lock()
	if a.schedDlg == nil || a.schedDlg.busy {
		a.mu.Unlock()
		return
	}
	a.schedDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) sendTextScheduled(text string, scheduleDate int64, silent bool) {
	a.mu.Lock()
	k := a.selected
	replyID := a.cMode.replyTarget()
	a.cMode.cancel()
	a.sending = true
	a.mu.Unlock()
	a.invalidate()
	go func() {
		defer func() {
			a.mu.Lock()
			a.sending = false
			a.mu.Unlock()
			a.invalidate()
		}()
		if k == nil || text == "" {
			return
		}
		sendText, sendEnts := text, []cores.TextEntity(nil)
		if hasMarkdown(text) {
			sendText, sendEnts = parseMarkdown(text)
		}
		if _, err := a.eng.SendMessage(k.AccountID, k.ChatID, sendText, replyID, sendEnts, silent, scheduleDate, "", "", false, false, false, false, false); err != nil {
			a.setToast("Schedule failed: " + err.Error())
			return
		}
		if scheduleDate == schedWhenOnline {
			a.setToast("Will send when you're online")
			return
		}
		a.setToast("Scheduled for " + time.Unix(scheduleDate, 0).Format("Mon 15:04"))
	}()
}

func (a *App) sendWhenOnline() {
	a.mu.Lock()
	d := a.schedDlg
	if d == nil || d.busy {
		a.mu.Unlock()
		return
	}
	a.schedDlg.busy = true
	a.mu.Unlock()
	text := strings.TrimSpace(a.wid.composer.Text())
	if text == "" {
		a.setToast("Nothing to schedule")
		a.mu.Lock()
		a.schedDlg = nil
		a.mu.Unlock()
		a.invalidate()
		return
	}
	a.wid.composer.SetText("")
	a.sendTextScheduled(text, schedWhenOnline, a.wid.schedDlgSilent.Value)
	a.mu.Lock()
	a.schedDlg = nil
	a.mu.Unlock()
	a.invalidate()
	a.clearDraftAfterSend()
}

func (a *App) submitScheduleDialog() {
	a.mu.Lock()
	d := a.schedDlg
	if d == nil || d.busy {
		a.mu.Unlock()
		return
	}
	preset := d.preset
	a.mu.Unlock()

	var when int64
	if p, ok := schedulePresetWhen(preset, time.Now()); ok {
		when = p.Unix()
	} else {
		w, ok := parseScheduleInput(a.wid.schedDateEd.Text(), a.wid.schedTimeEd.Text())
		if !ok {
			a.setToast("Enter date as YYYY-MM-DD and time as HH:MM")
			return
		}
		when = w
	}
	if when <= time.Now().Unix() {
		a.setToast("Pick a time in the future")
		return
	}
	a.mu.Lock()
	resched := a.schedDlg.resched
	a.mu.Unlock()
	if resched != nil {
		a.mu.Lock()
		a.schedDlg.busy = true
		a.mu.Unlock()
		go func() {
			if err := a.eng.RescheduleMessage(resched.AccountID, resched.ChatID, resched.MsgID, when); err != nil {
				a.setToast("Reschedule failed: " + err.Error())
			} else {
				a.setToast("Rescheduled for " + time.Unix(when, 0).Format("Mon 15:04"))
			}
			a.mu.Lock()
			a.schedDlg = nil
			a.mu.Unlock()
			a.reloadSchedPanel()
		}()
		return
	}
	text := strings.TrimSpace(a.wid.composer.Text())
	if text == "" {
		a.setToast("Nothing to schedule")
		return
	}
	a.mu.Lock()
	a.schedDlg.busy = true
	a.mu.Unlock()
	a.wid.composer.SetText("")
	a.sendTextScheduled(text, when, a.wid.schedDlgSilent.Value)
	a.mu.Lock()
	a.schedDlg = nil
	a.mu.Unlock()
	a.invalidate()
	a.clearDraftAfterSend()
}

func (a *App) clearDraftAfterSend() {
	a.mu.Lock()
	k := a.selected
	a.mu.Unlock()
	if k != nil {
		a.clearDraft(*k)
	}
}

func (a *App) layoutScheduleDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.schedDlg
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, schedKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeScheduleDialog()
		}
	}
	if a.wid.schedDlgCancel.Clicked(gtx) {
		a.closeScheduleDialog()
	}
	if a.wid.schedDlgSend.Clicked(gtx) {
		a.submitScheduleDialog()
	}
	if a.wid.schedDlgWhenOnline.Clicked(gtx) {
		a.sendWhenOnline()
	}
	for i := range a.schedDlgPresets {
		if a.schedDlgPresets[i].Clicked(gtx) {
			a.mu.Lock()
			if a.schedDlg != nil {
				a.schedDlg.preset = i
			}
			a.mu.Unlock()
			if p, ok := schedulePresetWhen(i, time.Now()); ok {
				a.wid.schedDateEd.SetText(p.Format("2006-01-02"))
				a.wid.schedTimeEd.SetText(p.Format("15:04"))
			}
			a.invalidate()
		}
	}

	paintScrimRect(gtx)

	presetLabels := [3]string{"Custom", "In 2 hours", "Tomorrow 9:00"}
	label := "Schedule"
	if d.busy {
		label = "Scheduling…"
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(340))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.H3("Schedule message")
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(13), "The message will send automatically at this time")
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.TextButton(&a.wid.schedDlgWhenOnline, "Send when they're online")
							btn.Color = a.ui.p.Accent
							return btn.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return a.schedChip(gtx, &a.schedDlgPresets[1], presetLabels[1], d.preset == 1)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return a.schedChip(gtx, &a.schedDlgPresets[2], presetLabels[2], d.preset == 2)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return a.schedChip(gtx, &a.schedDlgPresets[0], presetLabels[0], d.preset == 0)
								}),
							)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
										return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
											ed := a.ui.Editor(&a.wid.schedDateEd, "YYYY-MM-DD")
											return ed.Layout(gtx)
										})
									})
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return layout.Inset{Left: unit.Dp(6), Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
										lbl := a.ui.Dim(unit.Sp(14), "at")
										return lbl.Layout(gtx)
									})
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									gtx.Constraints.Max.X = gtx.Dp(unit.Dp(110))
									return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
										return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
											ed := a.ui.Editor(&a.wid.schedTimeEd, "HH:MM")
											return ed.Layout(gtx)
										})
									})
								}),
							)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Label(unit.Sp(14), "Silent — no notification")
									return lbl.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									tg := material.Switch(a.ui.Theme, &a.wid.schedDlgSilent, "")
									tg.Color.Enabled = a.ui.p.Accent
									tg.Color.Disabled = a.ui.p.SurfaceHi
									tg.Color.Track = a.ui.p.SurfaceHi
									return tg.Layout(gtx)
								}),
							)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.TextButton(&a.wid.schedDlgCancel, "Cancel")
									if d.busy {
										btn.Color = a.ui.p.TextFaint
									}
									return btn.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.PrimaryButton(&a.wid.schedDlgSend, label)
									return btn.Layout(gtx)
								}),
							)
						})
					}),
				)
			})
		})
	})
}

func (a *App) schedChip(gtx layout.Context, btn *widget.Clickable, label string, active bool) layout.Dimensions {
	return layout.Inset{Right: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		bg := a.ui.p.SurfaceHi
		if active {
			bg = a.ui.p.AccentDim
		}
		return roundedFill(gtx, bg, 8, func(gtx layout.Context) layout.Dimensions {
			return material.ButtonLayout(a.ui.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(12), label)
					return lbl.Layout(gtx)
				})
			})
		})
	})
}

const schedWhenOnline int64 = 0x7FFFFFFF

func scheduledMetaLabel(m engine.CachedMessage) string {
	if m.ScheduleDate == 0 {
		return ""
	}
	lbl := ""
	if m.ScheduleDate == schedWhenOnline {
		lbl = "scheduled · when online"
	} else {
		lbl = "scheduled " + time.Unix(m.ScheduleDate, 0).Format("Mon 15:04")
	}
	if m.IsSilent {
		lbl = "silent · " + lbl
	}
	return lbl
}
