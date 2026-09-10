package gui

import (
	"fmt"
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

// Drafts + scheduled messages (AyuGram parity, matrix #drafts/#scheduled):
// the composer's text persists per chat via engine.SaveDraft (restored on
// open, saved on leave, cleared on send; rows show a "Draft: …" preview),
// and the ⏰ button schedules the composed text with SendMessage's
// scheduleDate. Scheduled messages render their planned time in the meta.

// schedDlgState: open schedule dialog (nil when closed).
type schedDlgState struct {
	preset  int // 0 custom, 1 in 2h, 2 tomorrow 9:00
	when    time.Time
	busy    bool
	resched *engine.CachedMessage // set when rescheduling an existing message
}

var (
	schedDlgCancel     widget.Clickable
	schedDlgSend       widget.Clickable
	schedDlgWhenOnline widget.Clickable
	schedDlgPresets    [3]widget.Clickable
	schedDlgSilent     widget.Bool
	schedDateEd        widget.Editor
	schedTimeEd        widget.Editor
	schedKeyTag        = new(struct{})
	composerSchedBtn   widget.Clickable // ⏰ next to send
)

// schedulePresets (pure, testable): the quick choices AyuGram offers.
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

// parseScheduleInput (pure, testable): "YYYY-MM-DD" + "HH:MM" → unix
// seconds; ok=false on malformed input.
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

// draftPreview (pure, testable): the chat-row preview for a draft.
func draftPreview(text string) string {
	const max = 48
	r := []rune(text)
	if len(r) > max {
		r = r[:max]
	}
	return "Draft: " + string(r)
}

// flushDraft persists the composer's current text as the chat's draft
// (called when leaving a chat; GUI goroutine).
func (a *App) flushDraft(k chatKey) {
	text := strings.TrimSpace(composer.Text())
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

// clearDraft empties the stored draft after a successful send.
func (a *App) clearDraft(k chatKey) {
	go func() {
		if err := a.eng.SaveDraft(k.AccountID, k.ChatID, ""); err == nil {
			a.refreshChats()
		}
	}()
}

// openScheduleDialog preps the ⏰ dialog for the composed text.
func (a *App) openScheduleDialog() {
	a.mu.Lock()
	a.schedDlg = &schedDlgState{preset: 1, when: time.Now().Add(2 * time.Hour)}
	a.mu.Unlock()
	now := time.Now()
	schedDateEd.SetText(now.Format("2006-01-02"))
	schedTimeEd.SetText(now.Add(2 * time.Hour).Format("15:04"))
	a.invalidate()
}

// closeScheduleDialog dismisses (blocked while scheduling).
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

// sendTextScheduled sends the composed text at a unix-seconds date. silent
// suppresses the notification (AyuGram 🔕, threaded from the schedule
// dialog's switch).
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
		// Compose markdown (slice 33): typed markers become entities.
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

// sendWhenOnline schedules the composed text for the magic "when the
// peer comes online" date (AyuGram schedule option).
func (a *App) sendWhenOnline() {
	a.mu.Lock()
	d := a.schedDlg
	if d == nil || d.busy {
		a.mu.Unlock()
		return
	}
	a.schedDlg.busy = true
	a.mu.Unlock()
	text := strings.TrimSpace(composer.Text())
	if text == "" {
		a.setToast("Nothing to schedule")
		a.mu.Lock()
		a.schedDlg = nil
		a.mu.Unlock()
		a.invalidate()
		return
	}
	composer.SetText("")
	a.sendTextScheduled(text, schedWhenOnline, schedDlgSilent.Value)
	a.mu.Lock()
	a.schedDlg = nil
	a.mu.Unlock()
	a.invalidate()
	a.clearDraftAfterSend()
}

// submitScheduleDialog reads the dialog's date/time and schedules.
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
		w, ok := parseScheduleInput(schedDateEd.Text(), schedTimeEd.Text())
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
		// Reschedule an existing scheduled message.
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
	text := strings.TrimSpace(composer.Text())
	if text == "" {
		a.setToast("Nothing to schedule")
		return
	}
	a.mu.Lock()
	a.schedDlg.busy = true
	a.mu.Unlock()
	composer.SetText("")
	a.sendTextScheduled(text, when, schedDlgSilent.Value)
	a.mu.Lock()
	a.schedDlg = nil
	a.mu.Unlock()
	a.invalidate()
	a.clearDraftAfterSend()
}

// clearDraftAfterSend clears the draft of the open chat after sending.
func (a *App) clearDraftAfterSend() {
	a.mu.Lock()
	k := a.selected
	a.mu.Unlock()
	if k != nil {
		a.clearDraft(*k)
	}
}

// layoutScheduleDialog renders the schedule card over the chat pane.
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
	if schedDlgCancel.Clicked(gtx) {
		a.closeScheduleDialog()
	}
	if schedDlgSend.Clicked(gtx) {
		a.submitScheduleDialog()
	}
	if schedDlgWhenOnline.Clicked(gtx) {
		a.sendWhenOnline()
	}
	for i := range schedDlgPresets {
		if schedDlgPresets[i].Clicked(gtx) {
			a.mu.Lock()
			if a.schedDlg != nil {
				a.schedDlg.preset = i
			}
			a.mu.Unlock()
			if p, ok := schedulePresetWhen(i, time.Now()); ok {
				schedDateEd.SetText(p.Format("2006-01-02"))
				schedTimeEd.SetText(p.Format("15:04"))
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
					// Send when online (AyuGram schedule option, slice 39).
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.TextButton(&schedDlgWhenOnline, "Send when they're online")
							btn.Color = a.ui.p.Accent
							return btn.Layout(gtx)
						})
					}),
					// Preset chips.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return a.schedChip(gtx, &schedDlgPresets[1], presetLabels[1], d.preset == 1)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return a.schedChip(gtx, &schedDlgPresets[2], presetLabels[2], d.preset == 2)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return a.schedChip(gtx, &schedDlgPresets[0], presetLabels[0], d.preset == 0)
								}),
							)
						})
					}),
					// Date + time editors.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
										return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
											ed := a.ui.Editor(&schedDateEd, "YYYY-MM-DD")
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
											ed := a.ui.Editor(&schedTimeEd, "HH:MM")
											return ed.Layout(gtx)
										})
									})
								}),
							)
						})
					}),
					// Silent switch (AyuGram 🔕 in the schedule dialog).
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Label(unit.Sp(14), "Silent — no notification")
									return lbl.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									tg := material.Switch(a.ui.Theme, &schedDlgSilent, "")
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
									btn := a.ui.TextButton(&schedDlgCancel, "Cancel")
									if d.busy {
										btn.Color = a.ui.p.TextFaint
									}
									return btn.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.PrimaryButton(&schedDlgSend, label)
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

// scheduledMetaLabel (pure, testable): meta text for a scheduled message.
// schedWhenOnline is Telegram's magic schedule_date for "send when the
// peer comes online" (0x7FFFFFFF).
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

// scheduleHint is used by the composer row (pure).
func scheduleHint(when time.Time) string {
	return fmt.Sprintf("Send at %s", when.Format("15:04"))
}
