package gui

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

type exportOption struct {
	key   string
	label string
}

type exportGroup struct {
	title string
	opts  []exportOption
}

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

type exportDlgState struct {
	accountID string
	checked   map[string]bool
	running   bool
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
	exportOptBools   []widget.Bool
)

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
	a.exportOptsSynced = false
	a.mu.Unlock()
	exportSizeEd.SetText("")
	a.invalidate()
}

func (a *App) closeExportDialog() {
	a.mu.Lock()
	a.exportDlg = nil
	a.exportOptsSynced = false
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) updateExportDlg(fn func(d *exportDlgState) bool) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.exportDlg == nil {
		return
	}
	next := *a.exportDlg
	if !fn(&next) {
		return
	}
	a.exportDlg = &next
}

func (a *App) startExport() {
	checked := map[string]bool{}
	accountID := ""
	started := false
	a.updateExportDlg(func(cur *exportDlgState) bool {
		if cur.running {
			return false
		}
		for k, v := range cur.checked {
			checked[k] = v
		}
		accountID = cur.accountID
		cur.running = true
		cur.err = nil
		cur.done = nil
		cur.progress = nil
		started = true
		return true
	})
	if !started {
		return
	}
	size := parseExportSizeLimit(exportSizeEd.Text())
	go func() {
		if err := a.eng.StartExport(accountID, exportSettingsFromChecks(checked, size)); err != nil {
			a.setToast("Export: " + err.Error())
			a.updateExportDlg(func(cur *exportDlgState) bool {
				if cur.accountID != accountID {
					return false
				}
				cur.running = false
				return true
			})
			a.invalidate()
		}
	}()
	a.invalidate()
}

func (a *App) cancelExport() {
	accountID := ""
	a.updateExportDlg(func(cur *exportDlgState) bool {
		accountID = cur.accountID
		cur.running = false
		return true
	})
	if accountID != "" {
		a.eng.CancelExport(accountID)
	}
	a.setToast("Export cancelled")
	a.invalidate()
}

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

func (a *App) onExportProgress(ev engine.ExportProgressEvent, accountID string) {
	p := ev
	a.updateExportDlg(func(cur *exportDlgState) bool {
		if cur.accountID != accountID {
			return false
		}
		cur.progress = &p
		cur.running = true
		return true
	})
	a.invalidate()
}

func (a *App) onExportError(ev engine.ExportErrorEvent, accountID string) {
	e := ev
	a.updateExportDlg(func(cur *exportDlgState) bool {
		if cur.accountID != accountID {
			return false
		}
		cur.err = &e
		cur.running = false
		return true
	})
	a.invalidate()
}

func (a *App) onExportComplete(ev engine.ExportCompleteEvent, accountID string) {
	c := ev
	a.updateExportDlg(func(cur *exportDlgState) bool {
		if cur.accountID != accountID {
			return false
		}
		cur.done = &c
		cur.running = false
		return true
	})
	a.invalidate()
}

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
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						if d.done != nil {
							return a.exportDoneCard(gtx, *d.done)
						}
						if d.running {
							return a.exportProgressCard(gtx, d)
						}
						return a.exportOptionsList(gtx, d)
					}),
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

func (a *App) exportOptionsList(gtx layout.Context, d *exportDlgState) layout.Dimensions {
	groups := exportOptionGroups()
	n := 0
	for _, g := range groups {
		n += len(g.opts)
	}
	if len(exportOptBools) != n {
		exportOptBools = make([]widget.Bool, n)
	}
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

func firstTakeoutAccount(ids []string) string {
	if len(ids) == 0 {
		return ""
	}
	return ids[0]
}
