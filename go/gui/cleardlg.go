package gui

import (
	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Clear-history confirm dialog (slice 190, tdesktop's "Clear history?" box
// reached from the chat-row context menu): destructive action behind a
// centered confirm card, with the "Also delete for everyone" revoke
// checkbox offered where Telegram's deleteHistory semantics allow it
// (private chats always; groups/channels for admins). The chat stays in
// the list — that is the difference from Delete chat.

// clearDlgState: open dialog (nil when closed).
type clearDlgState struct {
	chat engine.ChatInfo
	busy bool
}

// clearDialogTitle (pure, testable). tdesktop: "Clear history?".
func clearDialogTitle(title string) string {
	_ = title // the box is generic in tdesktop; chat context is the pane behind it
	return "Clear history?"
}

// clearDialogHint (pure, testable).
func clearDialogHint(revokeAvailable bool) string {
	if revokeAvailable {
		return "This can't be undone."
	}
	return "This can't be undone. Messages stay on the other side."
}

// canRevokeClearHistory (pure, testable): DMs (incl. Saved Messages)
// always offer the both-sides wipe; groups/channels only for admins.
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

// openClearDialog shows the confirm for a chat-row Clear history.
func (a *App) openClearDialog(chat engine.ChatInfo) {
	a.mu.Lock()
	a.clearDlg = &clearDlgState{chat: chat}
	a.chatMenu = nil
	a.mu.Unlock()
	a.wid.clearDlgChk.Value = false
	a.invalidate()
}

// closeClearDialog dismisses (blocked while clearing).
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

// submitClearDialog performs the clear (async): server-side + local wipe
// through engine.ClearHistory, then reloads the open view and chat list so
// the empty state is honest immediately (§1.10 — no stale rows).
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
		// Reload whatever surface shows this chat so the wipe is visible
		// (the message window reloads only when the cleared chat is open).
		a.mu.Lock()
		sel := a.selected
		a.mu.Unlock()
		if sel != nil && sel.AccountID == d.chat.AccountID && sel.ChatID == d.chat.ChatID {
			a.refreshMessages()
		}
		a.refreshChats()
	}()
}

// layoutClearDialog renders the centered confirm card over the chat pane.
func (a *App) layoutClearDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.clearDlg
	if a.wid.clearDlgCancel.Clicked(gtx) {
		a.closeClearDialog()
	}
	if a.wid.clearDlgClear.Clicked(gtx) {
		a.submitClearDialog()
	}

	// Scrim.
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
