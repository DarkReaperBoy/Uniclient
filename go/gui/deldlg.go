package gui

import (
	"image"
	"image/color"

	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Delete dialog (AyuGram parity, matrix #155): "Delete message?" with the
// "also delete for everyone" revoke checkbox. Offered for single-message
// (context menu) and bulk (selection mode) deletes. The checkbox appears
// when a message is outgoing or the account administers the chat.

// delDlgState: open dialog (nil when closed).
type delDlgState struct {
	msgs   []engine.CachedMessage
	chat   engine.ChatInfo
	revoke bool
	busy   bool
}

var (
	delDlgCancel widget.Clickable
	delDlgDelete widget.Clickable
	delDlgChk    widget.Bool
)

// chatOf finds the ChatInfo for a message's chat (zero value if unknown).
func chatOf(f frame, m engine.CachedMessage) engine.ChatInfo {
	for _, c := range f.chats {
		if c.AccountID == m.AccountID && c.ChatID == m.ChatID {
			return c
		}
	}
	return engine.ChatInfo{}
}

// canRevokeForAll: any outgoing message, or admin in this chat.
func canRevokeForAll(msgs []engine.CachedMessage, chat engine.ChatInfo) bool {
	if chat.IsAdmin || chat.IsCreator {
		return true
	}
	for _, m := range msgs {
		if m.IsOutgoing {
			return true
		}
	}
	return false
}

// openDeleteDialog shows the confirm for one (menu) or more (selection)
// messages.
func (a *App) openDeleteDialog(msgs []engine.CachedMessage, chat engine.ChatInfo) {
	if len(msgs) == 0 {
		return
	}
	a.mu.Lock()
	a.delDlg = &delDlgState{msgs: msgs, chat: chat}
	a.menu = nil
	a.mu.Unlock()
	delDlgChk.Value = false
	a.invalidate()
}

// closeDeleteDialog dismisses (blocked while deleting).
func (a *App) closeDeleteDialog() {
	a.mu.Lock()
	if a.delDlg == nil {
		a.mu.Unlock()
		return
	}
	if a.delDlg.busy {
		a.mu.Unlock()
		return
	}
	a.delDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// submitDeleteDialog performs the deletes (async); revoke is only applied
// where the sender allows it.
func (a *App) submitDeleteDialog() {
	a.mu.Lock()
	if a.delDlg == nil || a.delDlg.busy {
		a.mu.Unlock()
		return
	}
	d := *a.delDlg
	d.revoke = delDlgChk.Value
	a.delDlg.busy = true
	a.mu.Unlock()

	go func() {
		var lastErr error
		okCount := 0
		for _, m := range d.msgs {
			revoke := d.revoke && (m.IsOutgoing || d.chat.IsAdmin || d.chat.IsCreator)
			if err := a.eng.DeleteMessage(m.AccountID, m.ChatID, m.MsgID, revoke); err != nil {
				lastErr = err
				continue
			}
			okCount++
		}
		a.mu.Lock()
		a.delDlg = nil
		a.mu.Unlock()
		a.invalidate()
		if lastErr != nil {
			a.setToast("Delete failed: " + lastErr.Error())
		}
		_ = okCount
	}()
}

// deleteDialogTitle + hint (pure, testable).
func deleteDialogTitle(n int) string {
	if n == 1 {
		return "Delete message?"
	}
	return "Delete " + itoa(n) + " messages?"
}

func deleteDialogHint(revokeAvailable bool) string {
	if revokeAvailable {
		return "This can't be undone."
	}
	return "This can't be undone. The message stays on the other side."
}

// layoutDeleteDialog renders the centered confirm card over the chat pane.
func (a *App) layoutDeleteDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.delDlg
	if delDlgCancel.Clicked(gtx) {
		a.closeDeleteDialog()
	}
	if delDlgDelete.Clicked(gtx) {
		a.submitDeleteDialog()
	}

	// Scrim.
	paintScrimRect(gtx)

	title := deleteDialogTitle(len(d.msgs))
	showChk := canRevokeForAll(d.msgs, d.chat)
	label := "Delete"
	if d.busy {
		label = "Deleting…"
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
							lbl := a.ui.Dim(unit.Sp(13), deleteDialogHint(showChk))
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if !showChk {
							return layout.Dimensions{}
						}
						return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							chk := material.CheckBox(a.ui.Theme, &delDlgChk, "Also delete for everyone")
							chk.Color = a.ui.p.Accent
							return chk.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.TextButton(&delDlgCancel, "Cancel")
									if d.busy {
										btn.Color = a.ui.p.TextFaint
									}
									return btn.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.TextButton(&delDlgDelete, label)
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

// paintScrimRect fills a translucent scrim over the whole pane.
func paintScrimRect(gtx layout.Context) {
	paint.FillShape(gtx.Ops, color.NRGBA{R: 0, G: 0, B: 0, A: 0x66},
		clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Op())
}
