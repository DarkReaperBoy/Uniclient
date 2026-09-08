package gui

import (
	"image"
	"strconv"

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

// Report flow (AyuGram parity, matrix #153 remainder): the Telegram
// interactive report — first messages.report returns a reason chooser
// (ReportResultChooseOption), picking one may ask for a comment
// (ReportResultAddComment), then reports. The engine already models the
// whole state machine; this dialog drives it.

// reportDlgState: open report dialog (nil when closed).
type reportDlgState struct {
	msgs            []engine.CachedMessage
	options         []cores.ReportOption // stage 1 list
	chosen          []byte               // picked option bytes
	commentOptional bool
	stage           int // 0 = asking server, 1 = choose, 2 = comment
	busy            bool
}

var (
	reportCancelBtn widget.Clickable
	reportSendBtn   widget.Clickable
	reportOptBtns   []widget.Clickable
	reportCommentEd widget.Editor
	reportKeyTag    = new(struct{})
)

// msgIDInt parses a message ID to int (0 on failure).
func msgIDInt(id string) int {
	n, err := strconv.Atoi(id)
	if err != nil {
		return 0
	}
	return n
}

// canReport: non-service messages from other people.
func canReport(m engine.CachedMessage) bool {
	return !m.IsService && !m.IsOutgoing
}

// openReportDialog starts the report flow for one message (context menu).
func (a *App) openReportDialog(msgs []engine.CachedMessage) {
	if len(msgs) == 0 {
		return
	}
	for _, m := range msgs {
		if msgIDInt(m.MsgID) == 0 {
			a.setToast("Cannot report this message")
			return
		}
	}
	a.mu.Lock()
	a.reportDlg = &reportDlgState{msgs: msgs}
	a.menu = nil
	a.mu.Unlock()
	reportCommentEd.SetText("")
	a.invalidate()
	a.reportStep(nil, "")
}

// closeReportDialog dismisses (blocked while a request is in flight).
func (a *App) closeReportDialog() {
	a.mu.Lock()
	if a.reportDlg == nil || a.reportDlg.busy {
		a.mu.Unlock()
		return
	}
	a.reportDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// reportStep issues one ReportMessage call and advances the dialog from the
// result. option nil = first (chooser) call.
func (a *App) reportStep(option []byte, comment string) {
	a.mu.Lock()
	if a.reportDlg == nil || a.reportDlg.busy {
		a.mu.Unlock()
		return
	}
	msgs := a.reportDlg.msgs
	a.reportDlg.busy = true
	a.reportDlg.stage = 0
	a.mu.Unlock()

	ids := make([]int, 0, len(msgs))
	for _, m := range msgs {
		ids = append(ids, msgIDInt(m.MsgID))
	}
	acc, chat := msgs[0].AccountID, msgs[0].ChatID

	go func() {
		res, err := a.eng.ReportMessage(acc, chat, ids, option, comment)
		a.mu.Lock()
		d := a.reportDlg
		if d == nil {
			a.mu.Unlock()
			return
		}
		d.busy = false
		if err != nil {
			a.reportDlg = nil
			a.mu.Unlock()
			a.setToast("Report failed: " + err.Error())
			return
		}
		switch res.Type {
		case "choose_option":
			d.stage = 1
			d.options = res.Options
		case "add_comment":
			d.stage = 2
			d.chosen = res.CommentOption
			d.commentOptional = res.CommentOptional
		case "message_id_required":
			a.reportDlg = nil
			a.mu.Unlock()
			a.setToast("Report: pick the messages first (select, then report)")
			return
		default: // "reported"
			a.reportDlg = nil
			a.mu.Unlock()
			a.setToast("Reported")
			return
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// reportPickOption chooses a reason and continues the flow.
func (a *App) reportPickOption(opt cores.ReportOption) {
	a.mu.Lock()
	if a.reportDlg == nil || a.reportDlg.busy {
		a.mu.Unlock()
		return
	}
	a.reportDlg.chosen = opt.Option
	a.mu.Unlock()
	a.reportStep(opt.Option, "")
}

// reportSendComment submits the optional comment.
func (a *App) reportSendComment() {
	a.mu.Lock()
	if a.reportDlg == nil || a.reportDlg.busy {
		a.mu.Unlock()
		return
	}
	chosen := a.reportDlg.chosen
	a.mu.Unlock()
	a.reportStep(chosen, reportCommentEd.Text())
}

// layoutReportDialog renders the report card over the chat pane.
func (a *App) layoutReportDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.reportDlg
	// Escape closes.
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, reportKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeReportDialog()
		}
	}
	if reportCancelBtn.Clicked(gtx) {
		a.closeReportDialog()
	}
	if reportSendBtn.Clicked(gtx) {
		a.reportSendComment()
	}

	growClickables(&reportOptBtns, len(d.options))

	paintScrimRect(gtx)

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(320))
		if gtx.Constraints.Max.Y > gtx.Dp(unit.Dp(420)) {
			gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(420))
		}
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.H3("Report")
						return lbl.Layout(gtx)
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return a.reportDialogBody(gtx, f, d)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if d.stage != 2 {
							return layout.Dimensions{}
						}
						return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.TextButton(&reportCancelBtn, "Cancel")
									return btn.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									label := "Report"
									if d.busy {
										label = "Reporting…"
									}
									btn := a.ui.PrimaryButton(&reportSendBtn, label)
									return btn.Layout(gtx)
								}),
							)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if d.stage == 2 {
							return layout.Dimensions{}
						}
						return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.TextButton(&reportCancelBtn, "Cancel")
							if d.busy {
								btn.Color = a.ui.p.TextFaint
							}
							return btn.Layout(gtx)
						})
					}),
				)
			})
		})
	})
}

func (a *App) reportDialogBody(gtx layout.Context, f frame, d *reportDlgState) layout.Dimensions {
	switch d.stage {
	case 0:
		return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(13), "Asking Telegram for the reasons…")
			return lbl.Layout(gtx)
		})
	case 1:
		if len(d.options) == 0 {
			return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(13), "No reasons available")
				return lbl.Layout(gtx)
			})
		}
		rows := make([]layout.FlexChild, 0, len(d.options)+1)
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(13), "Why are you reporting this?")
				return lbl.Layout(gtx)
			})
		}))
		for i, opt := range d.options {
			i, opt := i, opt
			rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := &reportOptBtns[i]
				if btn.Clicked(gtx) {
					a.reportPickOption(opt)
				}
				return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return material.ButtonLayout(a.ui.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(14), opt.Text)
							return lbl.Layout(gtx)
						})
					})
				})
			}))
		}
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
	default: // 2 = comment
		var rows []layout.FlexChild
		hint := "Add a comment"
		if d.commentOptional {
			hint += " (optional)"
		}
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(13), hint)
				return lbl.Layout(gtx)
			})
		}))
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						ed := a.ui.Editor(&reportCommentEd, hint)
						return ed.Layout(gtx)
					})
				})
			})
		}))
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
	}
}
