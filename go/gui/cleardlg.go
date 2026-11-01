package gui

import (
	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget/material"

	"uniclient/engine"
)

type clearDlgState struct {
	chat engine.ChatInfo
	busy bool
}

func clearDialogTitle(title string) string {
	_ = title
	return "Clear history?"
}

func clearDialogHint(revokeAvailable bool) string {
	if revokeAvailable {
		return "This can't be undone."
	}
	return "This can't be undone. Messages stay on the other side."
}

func canRevokeClearHistory(c engine.ChatInfo) bool {
	switch c.Type {
	case engine.ChatTypeDMVal:
		return true
	case engine.ChatTypeGroupVal, engine.ChatTypeChanVal:
		return c.IsAdmin || c.IsCreator
	default:
		return false
	}
}

func (a *App) openClearDialog(chat engine.ChatInfo) {
	a.mu.Lock()
	a.clearDlg = &clearDlgState{chat: chat}
	a.chatMenu = nil
	a.mu.Unlock()
	a.wid.clearDlgChk.Value = false
	a.invalidate()
}

func (a *App) closeClearDialog() {
	a.mu.Lock()
	if a.clearDlg == nil {
		a.mu.Unlock()
		return
	}
	if a.clearDlg.busy {
		a.mu.Unlock()
		return
	}
	a.clearDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) submitClearDialog() {
	a.mu.Lock()
	if a.clearDlg == nil || a.clearDlg.busy {
		a.mu.Unlock()
		return
	}
	d := *a.clearDlg
	d.chat = a.clearDlg.chat
	revoke := a.wid.clearDlgChk.Value && canRevokeClearHistory(d.chat)
	a.clearDlg.busy = true
	a.mu.Unlock()

	go func() {
		err := a.eng.ClearHistory(d.chat.AccountID, d.chat.ChatID, revoke)
		a.mu.Lock()
		a.clearDlg = nil
		a.mu.Unlock()
		a.invalidate()
		if err != nil {
			a.setToast("Clear history failed: " + err.Error())
			return
		}
		a.setToast("History cleared")
		a.mu.Lock()
		sel := a.selected
		a.mu.Unlock()
		if sel != nil && sel.AccountID == d.chat.AccountID && sel.ChatID == d.chat.ChatID {
			a.refreshMessages()
		}
		a.refreshChats()
	}()
}

func (a *App) layoutClearDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.clearDlg
	if a.wid.clearDlgCancel.Clicked(gtx) {
		a.closeClearDialog()
	}
	if a.wid.clearDlgClear.Clicked(gtx) {
		a.submitClearDialog()
	}

	paintScrimRect(gtx)

	title := clearDialogTitle(d.chat.Title)
	showChk := canRevokeClearHistory(d.chat)
	label := "Clear"
	if d.busy {
		label = "Clearing…"
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(320))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.H3(title)
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(13), clearDialogHint(showChk))
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if !showChk {
							return layout.Dimensions{}
						}
						return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							chk := material.CheckBox(a.ui.Theme, &a.wid.clearDlgChk, "Also delete for everyone")
							chk.Color = a.ui.p.Accent
							return chk.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.TextButton(&a.wid.clearDlgCancel, "Cancel")
									if d.busy {
										btn.Color = a.ui.p.TextFaint
									}
									return btn.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.TextButton(&a.wid.clearDlgClear, label)
									btn.Color = a.ui.p.Error
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
