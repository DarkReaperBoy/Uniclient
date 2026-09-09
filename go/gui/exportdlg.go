package gui

// Export data wizard (AyuGram "Export data", matrix row 208, slice 100):
// Settings → Data & Storage gains "Export data" — a content-pane dialog
// with the takeout option groups (account / chats / media / other), a
// size limit, Start / Cancel / Skip-file controls, live progress from
// the engine's export events (step bar, per-file byte row), honest
// error cards (takeout delay, disk IO, api errors) and a completion
// card with the export path. Only accounts whose core supports takeout
// offer the entry (capability gate, no dead UI).

import (
	"image"
	"strconv"
	"strings"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// exportOption is one checkbox row.
type exportOption struct {
	key   string // ExportSettings field name
	label string
}

// exportGroup is one titled checkbox section.
type exportGroup struct {
	title string
	opts  []exportOption
}

// exportOptionGroups (pure, testable): the wizard's checkbox layout —
// AyuGram's export categories, every key a real engine settings field.
func exportOptionGroups() []exportGroup {
	return []exportGroup{
		{"Account", []exportOption{
			{"personal_info", "Personal information"},
			{"contacts", "Contacts list"},
			{"stories", "Stories"},
			{"profile_music", "Profile music"},
		}},
		{"Chats", []exportOption{
			{"personal_chats", "Personal chats"},
			{"bot_chats", "Bot chats"},
			{"private_groups", "Private groups"},
			{"private_channels", "Private channels"},
			{"public_groups", "Public groups"},
			{"public_channels", "Public channels"},
		}},
		{"Media", []exportOption{
			{"media_photos", "Photos"},
			{"media_video", "Videos"},
			{"media_voice", "Voice messages"},
			{"media_video_message", "Video messages"},
			{"media_sticker", "Stickers"},
			{"media_gif", "Animated GIFs"},
			{"media_file", "Files"},
		}},
		{"Other", []exportOption{
			{"sessions", "Active sessions"},
			{"other_data", "Other data"},
		}},
	}
}

// exportDlgState is the open wizard (nil when closed).
type exportDlgState struct {
	accountID string
	checked   map[string]bool
	running   bool // engine export in flight
	progress  *engine.ExportProgressEvent
	err       *engine.ExportErrorEvent
	done      *engine.ExportCompleteEvent
}

var (
	exportDlgTag     = new(struct{})
	exportDlgClose   widget.Clickable
	exportDlgStart   widget.Clickable
	exportDlgCancel  widget.Clickable
	exportDlgSkip    widget.Clickable
	exportDlgDoneBtn widget.Clickable
	exportSizeEd     widget.Editor
	exportOptBools   []widget.Bool // option checkbox pool, grown per frame
)

// parseExportSizeLimit (pure, testable): the size editor's text → MB,
// 0 on garbage, clamped to the engine's 8 GB ceiling.
func parseExportSizeLimit(s string) int {
	n, err := strconv.Atoi(strings.TrimSpace(s))
	if err != nil || n < 0 {
		return 0
	}
	if n > 8192 {
		return 8192
	}
	return n
}

// exportProgressPercent (pure, testable): overall wizard progress from
// the engine's step index + per-step fraction.
func exportProgressPercent(step, total int, prog float64) float32 {
	if total <= 0 {
		return 0
	}
	f := (float32(step) + float32(prog)) / float32(total)
	if f < 0 {
		return 0
	}
	if f > 1 {
		return 1
	}
	return f
}

// exportErrorText (pure, testable): an honest sentence for an export
// error — the takeout delay carries the wait, disk errors the path.
func exportErrorText(ev engine.ExportErrorEvent) string {
	switch ev.ErrorType {
	case "takeout_delay":
		return "Telegram limits data exports — try again in " + itoa(ev.HoursRemaining) + " h."
	case "takeout_invalid":
		return "Takeout session expired or invalid."
	}
	msg := ev.Description
	if msg == "" {
		msg = ev.ErrorName
	}
	if msg == "" {
		msg = ev.ErrorType
	}
	if ev.Path != "" {
		msg += " (at " + ev.Path + ")"
	}
	return msg
}

// exportSettingsFromChecks (pure, testable): the checkbox map + size
// limit → the engine's ExportSettings.
func exportSettingsFromChecks(checked map[string]bool, sizeMB int) engine.ExportSettings {
	return engine.ExportSettings{
		PersonalInfo:    checked["personal_info"],
		Contacts:        checked["contacts"],
		Stories:         checked["stories"],
		ProfileMusic:    checked["profile_music"],
		PersonalChats:   checked["personal_chats"],
		BotChats:        checked["bot_chats"],
		PrivateGroups:   checked["private_groups"],
		PrivateChannels: checked["private_channels"],
		PublicGroups:    checked["public_groups"],
		PublicChannels:  checked["public_channels"],
		MediaPhotos:     checked["media_photos"],
		MediaVideo:      checked["media_video"],
		MediaVoice:      checked["media_voice"],
		MediaVideoMsg:   checked["media_video_message"],
		MediaSticker:    checked["media_sticker"],
		MediaGif:        checked["media_gif"],
		MediaFile:       checked["media_file"],
		Sessions:        checked["sessions"],
		OtherData:       checked["other_data"],
		SizeLimitMB:     sizeMB,
	}
}

// openExportDialog opens the wizard for an account.
func (a *App) openExportDialog(accountID string) {
	a.mu.Lock()
	a.exportDlg = &exportDlgState{
		accountID: accountID,
		checked: map[string]bool{
			"personal_info": true, "contacts": true,
			"personal_chats": true, "private_groups": true,
			"media_photos": true, "media_video": true,
		},
	}
	a.mu.Unlock()
	exportSizeEd.SetText("")
	a.invalidate()
}

// closeExportDialog dismisses the wizard (cancels nothing — a running
// export keeps going and reports via toasts).
func (a *App) closeExportDialog() {
	a.mu.Lock()
	a.exportDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// startExport runs the engine takeout with the checked options.
func (a *App) startExport() {
	a.mu.Lock()
	d := a.exportDlg
	if d == nil || d.running {
		a.mu.Unlock()
		return
	}
	checked := make(map[string]bool, len(d.checked))
	for k, v := range d.checked {
		checked[k] = v
	}
	accountID := d.accountID
	d.running = true
	d.err = nil
	d.done = nil
	d.progress = nil
	a.mu.Unlock()
	size := parseExportSizeLimit(exportSizeEd.Text())
	go func() {
		if err := a.eng.StartExport(accountID, exportSettingsFromChecks(checked, size)); err != nil {
			a.setToast("Export: " + err.Error())
			a.mu.Lock()
			if a.exportDlg != nil {
				a.exportDlg.running = false
			}
			a.mu.Unlock()
			a.invalidate()
		}
	}()
	a.invalidate()
}

// cancelExport stops the running engine export.
func (a *App) cancelExport() {
	a.mu.Lock()
	d := a.exportDlg
	accountID := ""
	if d != nil {
		d.running = false
		accountID = d.accountID
	}
	a.mu.Unlock()
	if accountID != "" {
		a.eng.CancelExport(accountID)
	}
	a.setToast("Export cancelled")
	a.invalidate()
}

// skipExportFile skips the file the engine is currently downloading.
func (a *App) skipExportFile() {
	a.mu.Lock()
	d := a.exportDlg
	accountID, randomID := "", uint64(0)
	if d != nil && d.progress != nil {
		accountID = d.accountID
		randomID = d.progress.FileRandomID
	}
	a.mu.Unlock()
	if accountID == "" || randomID == 0 {
		return
	}
	a.eng.SkipExportFile(accountID, randomID)
}

// onExportProgress updates the wizard from an engine progress event.
func (a *App) onExportProgress(ev engine.ExportProgressEvent, accountID string) {
	a.mu.Lock()
	if d := a.exportDlg; d != nil && d.accountID == accountID {
		p := ev
		d.progress = &p
		d.running = true
	}
	a.mu.Unlock()
	a.invalidate()
}

// onExportError shows the engine's export failure.
func (a *App) onExportError(ev engine.ExportErrorEvent, accountID string) {
	a.mu.Lock()
	if d := a.exportDlg; d != nil && d.accountID == accountID {
		e := ev
		d.err = &e
		d.running = false
	}
	a.mu.Unlock()
	a.invalidate()
}

// onExportComplete shows the engine's export success card.
func (a *App) onExportComplete(ev engine.ExportCompleteEvent, accountID string) {
	a.mu.Lock()
	if d := a.exportDlg; d != nil && d.accountID == accountID {
		c := ev
		d.done = &c
		d.running = false
	}
	a.mu.Unlock()
	a.invalidate()
}

// layoutExportDialog renders the wizard as the content pane.
func (a *App) layoutExportDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.exportDlg
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, exportDlgTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			if !d.running {
				a.closeExportDialog()
			}
		}
	}
	if exportDlgClose.Clicked(gtx) && !d.running {
		a.closeExportDialog()
	}
	if exportDlgStart.Clicked(gtx) && !d.running && d.done == nil {
		a.startExport()
	}
	if exportDlgCancel.Clicked(gtx) && d.running {
		a.cancelExport()
	}
	if exportDlgSkip.Clicked(gtx) && d.running {
		a.skipExportFile()
	}
	if exportDlgDoneBtn.Clicked(gtx) {
		a.closeExportDialog()
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(440))
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(560))
		return roundedFill(gtx, a.ui.p.Surface, 16, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(18)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					// Header + close.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								return a.ui.H3("Export data").Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								btn := a.ui.IconButton(&exportDlgClose, iconContentClear, "Close")
								btn.Color = a.ui.p.TextDim
								return btn.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(12), "Telegram takeout — a copy of your data lands on this device.")
							lbl.Color = a.ui.p.TextFaint
							return lbl.Layout(gtx)
						})
					}),
					// Option groups / progress / result.
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						if d.done != nil {
							return a.exportDoneCard(gtx, *d.done)
						}
						if d.running {
							return a.exportProgressCard(gtx, d)
						}
						return a.exportOptionsList(gtx, d)
					}),
					// Error line.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if d.err == nil {
							return layout.Dimensions{}
						}
						return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(11), exportErrorText(*d.err))
							lbl.Color = a.ui.p.Error
							return lbl.Layout(gtx)
						})
					}),
					// Controls.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									if d.done != nil {
										bl := material.Button(a.ui.Theme, &exportDlgDoneBtn, "Done")
										bl.Background = a.ui.p.Accent
										bl.CornerRadius = 10
										return bl.Layout(gtx)
									}
									if d.running {
										bl := material.Button(a.ui.Theme, &exportDlgCancel, "Cancel export")
										bl.Background = a.ui.p.Error
										bl.CornerRadius = 10
										return bl.Layout(gtx)
									}
									bl := material.Button(a.ui.Theme, &exportDlgStart, "Start export")
									bl.Background = a.ui.p.Accent
									bl.CornerRadius = 10
									return bl.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									if !d.running || d.progress == nil || d.progress.FileRandomID == 0 {
										return layout.Dimensions{}
									}
									return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
										bl := a.ui.TextButton(&exportDlgSkip, "Skip file")
										bl.Color = a.ui.p.TextDim
										return bl.Layout(gtx)
									})
								}),
							)
						})
					}),
				)
			})
		})
	})
}

// exportOptionsList renders the checkbox groups + size limit.
func (a *App) exportOptionsList(gtx layout.Context, d *exportDlgState) layout.Dimensions {
	groups := exportOptionGroups()
	n := 0
	for _, g := range groups {
		n += len(g.opts)
	}
	if len(exportOptBools) != n {
		exportOptBools = make([]widget.Bool, n)
	}
	// Seed the pool from the dialog's checked map once per open.
	if !a.exportOptsSynced {
		j := 0
		for _, g := range groups {
			for _, o := range g.opts {
				exportOptBools[j].Value = d.checked[o.key]
				j++
			}
		}
		a.exportOptsSynced = true
	}

	var children []layout.FlexChild
	i := 0
	for _, g := range groups {
		g := g
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(11), strings.ToUpper(g.title))
				lbl.Color = a.ui.p.TextFaint
				return lbl.Layout(gtx)
			})
		}))
		for _, o := range g.opts {
			o := o
			idx := i
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				chk := material.CheckBox(a.ui.Theme, &exportOptBools[idx], o.label)
				chk.Color = a.ui.p.Accent
				return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return chk.Layout(gtx)
				})
			}))
			// Sync the click back into the dialog's checked map.
			if exportOptBools[idx].Update(gtx) {
				a.mu.Lock()
				if a.exportDlg != nil {
					a.exportDlg.checked[o.key] = exportOptBools[idx].Value
				}
				a.mu.Unlock()
			}
			i++
		}
	}
	// Size limit row.
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(13), "Size limit")
					return lbl.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						exportSizeEd.SingleLine = true
						gtx.Constraints.Max.X = gtx.Dp(unit.Dp(90))
						ed := a.ui.Editor(&exportSizeEd, "MB")
						return ed.Layout(gtx)
					})
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(11), "MB per file (0 = engine default; max 8192)")
						lbl.Color = a.ui.p.TextFaint
						return lbl.Layout(gtx)
					})
				}),
			)
		})
	}))
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// exportProgressCard renders the live progress view.
func (a *App) exportProgressCard(gtx layout.Context, d *exportDlgState) layout.Dimensions {
	p := engine.ExportProgressEvent{Step: "Preparing…"}
	if d.progress != nil {
		p = *d.progress
	}
	pct := exportProgressPercent(p.StepIndex, p.TotalSteps, p.Progress)
	children := []layout.FlexChild{
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Label(unit.Sp(14), p.Step)
			return lbl.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return material.ProgressBar(a.ui.Theme, pct).Layout(gtx)
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			info := p.Info
			if info == "" {
				info = "Working…"
			}
			lbl := a.ui.Dim(unit.Sp(12), info)
			lbl.Color = a.ui.p.TextFaint
			return lbl.Layout(gtx)
		}),
	}
	if p.BytesCount > 0 {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(12), p.BytesName+" — "+fmtBytes(p.BytesLoaded)+" / "+fmtBytes(p.BytesCount))
				return lbl.Layout(gtx)
			})
		}))
	}
	if p.TotalFiles > 0 {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(12), itoa(p.TotalFiles)+" files · "+fmtBytes(p.TotalSize))
				return lbl.Layout(gtx)
			})
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// exportDoneCard renders the completion view.
func (a *App) exportDoneCard(gtx layout.Context, done engine.ExportCompleteEvent) layout.Dimensions {
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.ui.H3("Export complete").Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Label(unit.Sp(13), done.ExportPath)
				return lbl.Layout(gtx)
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(12), itoa(done.TotalFiles)+" files · "+fmtBytes(done.TotalSize))
				lbl.Color = a.ui.p.TextFaint
				return lbl.Layout(gtx)
			})
		}),
	)
}

// firstTakeoutAccount (pure, testable): the account the Export-data row
// targets — the first takeout-capable account, "" hides the row.
func firstTakeoutAccount(ids []string) string {
	if len(ids) == 0 {
		return ""
	}
	return ids[0]
}
