package gui

import (
	"image"

	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Chat-header "..." menu (AyuGram peer menu, matrix §3 P0): mute toggle,
// view profile, clear history, block/unblock (DMs), leave (groups/channels)
// or delete (DMs) — every row dispatches a real engine call; destructive
// actions ask first. Rendered as a popup anchored under the header's ⋮,
// dismissed by any outside press.

// headerMenuTarget is the open header menu + its confirm state.
type headerMenuTarget struct {
	chat    engine.ChatInfo
	pos     image.Point
	confirm string // "" | "clear" | "leave" | "delete"
}

// header menu button pool.
var ()

// headerMenuConfirmText maps a confirm id to its dialog copy.
func headerMenuConfirmText(id string) (title, hint string) {
	switch id {
	case "clear":
		return "Clear history?", "The chat's cached history will be cleared."
	case "leave":
		return "Leave chat?", "You will stop receiving messages in this chat."
	case "delete":
		return "Delete chat?", "The chat will be removed from your list."
	}
	return "", ""
}

// headerMenuItems derives the peer-menu rows (pure, tested).
func headerMenuItems(c engine.ChatInfo, blockedKnown, blocked, transOn bool) []chatMenuAction {
	var items []chatMenuAction
	if c.IsMuted {
		items = append(items, chatMenuAction{"Unmute", "unmute"})
	} else {
		items = append(items, chatMenuAction{"Mute notifications", "mute"})
	}
	items = append(items, chatMenuAction{"View profile", "profile"})
	items = append(items, chatMenuAction{"Search", "search"})
	// Chat-wide translate bar (slice 150): state-aware label.
	if transOn {
		items = append(items, chatMenuAction{"Hide translations", "transoff"})
	} else {
		items = append(items, chatMenuAction{"Translate to…", "transon"})
	}
	items = append(items, chatMenuAction{"Notification sound…", "notifsound"})
	if c.Type == engine.ChatTypeGroupVal || c.Type == engine.ChatTypeTopicVal || c.Type == engine.ChatTypeChanVal {
		items = append(items, chatMenuAction{"Add members", "addmember"})
	}
	items = append(items, chatMenuAction{"Scheduled messages", "scheduled"})
	items = append(items, chatMenuAction{"Auto-delete…", "autodelete"})
	items = append(items, chatMenuAction{"Shadow-banned users…", "shadowbans"})
	items = append(items, chatMenuAction{"View deleted messages…", "viewdeleted"})
	items = append(items, chatMenuAction{"Clear deleted messages", "cleardeleted"})
	if c.Type == engine.ChatTypeDMVal {
		items = append(items, chatMenuAction{"Change colors…", "theme"})
		if blockedKnown && blocked {
			items = append(items, chatMenuAction{"Unblock user", "unblock"})
		} else {
			items = append(items, chatMenuAction{"Block user", "block"})
		}
		items = append(items, chatMenuAction{"Clear history", "clear"})
		items = append(items, chatMenuAction{"Delete chat", "delete"})
		return items
	}
	items = append(items, chatMenuAction{"Clear history", "clear"})
	if c.Type == engine.ChatTypeGroupVal || c.Type == engine.ChatTypeChanVal {
		items = append(items, chatMenuAction{"Leave chat", "leave"})
	}
	return items
}

// ── state transitions ─────────────────────────────────────────────────────

// openTtlDialogNow opens the auto-delete picker from the header menu
// (the open chat's frame snapshot is read under the lock).
func (a *App) openTtlDialogNow(c engine.ChatInfo) {
	a.mu.Lock()
	a.ttlDlg = &ttlDlgState{accountID: c.AccountID, chatID: c.ChatID, title: c.Title}
	a.mu.Unlock()
	a.invalidate()
}

// openHeaderMenu opens the peer menu at pos (chat pane coords).
func (a *App) openHeaderMenu(c engine.ChatInfo, pos image.Point) {
	a.mu.Lock()
	a.headerMenu = &headerMenuTarget{chat: c, pos: pos}
	a.mu.Unlock()
	a.invalidate()
}

// closeHeaderMenu dismisses it.
func (a *App) closeHeaderMenu() {
	a.mu.Lock()
	a.headerMenu = nil
	a.mu.Unlock()
	a.invalidate()
}

// dispatchHeaderMenu runs one action (async where needed).
func (a *App) dispatchHeaderMenu(c engine.ChatInfo, action string) {
	a.mu.Lock()
	if m := a.headerMenu; m != nil {
		m.confirm = ""
	}
	a.mu.Unlock()
	switch action {
	case "profile":
		a.closeHeaderMenu()
		a.openPanel()
	case "search":
		a.closeHeaderMenu()
		a.toggleInChatSearch()
	case "notifsound":
		a.closeHeaderMenu()
		a.openSoundPickerChat(c.AccountID, c.ChatID)
	case "transon", "transoff":
		a.closeHeaderMenu()
		a.toggleChatTranslate(chatKey{AccountID: c.AccountID, ChatID: c.ChatID})
	case "addmember":
		a.closeHeaderMenu()
		a.openAddMemberDialog(c)
	case "viewdeleted":
		a.closeHeaderMenu()
		a.openDeletedDialog(chatKey{AccountID: c.AccountID, ChatID: c.ChatID})
	case "cleardeleted":
		a.closeHeaderMenu()
		accountID, chatID := c.AccountID, c.ChatID
		go func() {
			n, err := a.eng.ClearDeletedMessages(accountID, chatID)
			if err != nil {
				a.setToast("Clear deleted: " + err.Error())
				return
			}
			if n == 0 {
				a.setToast("No deleted messages")
				return
			}
			a.setToast("Cleared " + itoa(int(n)) + " deleted message" + pluralS(int(n)))
			a.refreshMessages()
		}()
	case "scheduled":
		a.closeHeaderMenu()
		a.openSchedPanel()
	case "shadowbans":
		a.closeHeaderMenu()
		a.openShadowDialog(chatKey{AccountID: c.AccountID, ChatID: c.ChatID})
	case "autodelete":
		a.closeHeaderMenu()
		chat := c
		a.openTtlDialogNow(chat)
	case "theme":
		a.closeHeaderMenu()
		chat := c
		a.openChatThemeDialog(chat)
	case "mute":
		a.closeHeaderMenu()
		go func() {
			if err := a.eng.MuteChat(c.AccountID, c.ChatID, true, 0); err != nil {
				a.setToast("Mute failed: " + err.Error())
			}
		}()
	case "unmute":
		a.closeHeaderMenu()
		go func() {
			if err := a.eng.MuteChat(c.AccountID, c.ChatID, false, 0); err != nil {
				a.setToast("Unmute failed: " + err.Error())
			}
		}()
	case "block":
		a.closeHeaderMenu()
		go func() {
			if err := a.eng.BlockUser(c.AccountID, c.ChatID); err != nil {
				a.setToast("Block failed: " + err.Error())
			} else {
				a.setToast("User blocked")
			}
		}()
	case "unblock":
		a.closeHeaderMenu()
		go func() {
			if err := a.eng.UnblockUser(c.AccountID, c.ChatID); err != nil {
				a.setToast("Unblock failed: " + err.Error())
			} else {
				a.setToast("User unblocked")
			}
		}()
	case "clear", "leave", "delete":
		// Confirm first (dialog while the menu closes).
		a.mu.Lock()
		if m := a.headerMenu; m != nil {
			m.confirm = action
		} else {
			m := &headerMenuTarget{chat: c, confirm: action}
			a.headerMenu = m
		}
		a.mu.Unlock()
		a.invalidate()
	}
}

// runHeaderConfirm executes the confirmed destructive action.
func (a *App) runHeaderConfirm(action string) {
	a.mu.Lock()
	m := a.headerMenu
	a.headerMenu = nil
	a.mu.Unlock()
	if m == nil {
		return
	}
	c := m.chat
	go func() {
		var err error
		switch action {
		case "clear":
			err = a.eng.ClearHistory(c.AccountID, c.ChatID, false)
		case "leave":
			err = a.eng.LeaveChat(c.AccountID, c.ChatID)
		case "delete":
			err = a.eng.DeleteChat(c.AccountID, c.ChatID, false)
		}
		if err != nil {
			a.setToast("Failed: " + err.Error())
			return
		}
		switch action {
		case "clear":
			a.setToast("History cleared")
			a.refreshMessages()
		case "leave", "delete":
			a.setToast("Done")
			a.mu.Lock()
			a.selected = nil
			a.msgFor = nil
			a.mu.Unlock()
			a.refreshChats()
		}
		a.invalidate()
	}()
}

// refreshMessages is state.go's (reloads the open chat's window).

// ── layout ────────────────────────────────────────────────────────────────

// layoutHeaderMenu draws the open peer menu, clamped to the chat pane,
// plus its confirm dialog.
func (a *App) layoutHeaderMenu(gtx layout.Context, f frame) layout.Dimensions {
	m := f.headerMenu
	items := headerMenuItems(m.chat, f.profile != nil, f.profile != nil && f.profile.IsBlocked,
		f.selected != nil && chatTranslateOn(f, f.selected))
	growClickables(&a.wid.headerMenuBtns, len(items))

	menuW := gtx.Dp(unit.Dp(220))
	rowH := gtx.Dp(unit.Dp(36))
	h := gtx.Dp(unit.Dp(8)) + len(items)*rowH + gtx.Dp(unit.Dp(8))

	// Anchor under the ⋮ (top-right), clamped.
	pos := m.pos
	if pos.X+menuW > gtx.Constraints.Max.X {
		pos.X = gtx.Constraints.Max.X - menuW
	}
	if pos.Y+h > gtx.Constraints.Max.Y {
		pos.Y = gtx.Constraints.Max.Y - h
	}
	a.headerMenuRect = image.Rect(pos.X, pos.Y, pos.X+menuW, pos.Y+h)

	var dims layout.Dimensions
	func() {
		defer op.Offset(pos).Push(gtx.Ops).Pop()
		gtx.Constraints = layout.Constraints{Max: image.Pt(menuW, h), Min: image.Pt(menuW, h)}
		dims = roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
			children := make([]layout.FlexChild, 0, len(items)+2)
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Dimensions{Size: image.Pt(menuW, gtx.Dp(unit.Dp(4)))}
				})
			}))
			for i := range items {
				i := i
				children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := &a.wid.headerMenuBtns[i]
					if btn.Clicked(gtx) {
						a.dispatchHeaderMenu(m.chat, items[i].action)
					}
					return headerMenuRow(gtx, a, btn, items[i], rowH)
				}))
			}
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Dimensions{Size: image.Pt(menuW, gtx.Dp(unit.Dp(4)))}
				})
			}))
			layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
			return layout.Dimensions{Size: image.Pt(menuW, h)}
		})
	}()

	if m.confirm != "" {
		a.layoutHeaderConfirm(gtx, f, m.confirm)
	}
	return dims
}

// headerMenuRow renders one row (label; destructive rows tinted).
func headerMenuRow(gtx layout.Context, a *App, btn *widget.Clickable, item chatMenuAction, rowH int) layout.Dimensions {
	bl := material.ButtonLayout(a.ui.Theme, btn)
	bl.Background = a.ui.p.Surface // invisible against the card
	bl.CornerRadius = 8
	gtx.Constraints.Min.Y = rowH
	return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.UniformInset(unit.Dp(9)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Label(unit.Sp(14), item.label)
			switch item.action {
			case "clear", "leave", "delete", "block":
				lbl.Color = a.ui.p.Error
			default:
				lbl.Color = a.ui.p.Text
			}
			return lbl.Layout(gtx)
		})
	})
}

// layoutHeaderConfirm: centered confirmation card for destructive actions.
func (a *App) layoutHeaderConfirm(gtx layout.Context, f frame, action string) {
	title, hint := headerMenuConfirmText(action)
	if a.wid.headerCxlBtn.Clicked(gtx) {
		a.closeHeaderMenu()
	}
	if a.wid.headerOkBtn.Clicked(gtx) {
		a.runHeaderConfirm(action)
	}

	w := gtx.Dp(unit.Dp(280))
	gtx2 := gtx
	gtx2.Constraints.Min = image.Point{}
	layout.Center.Layout(gtx2, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = w
		gtx.Constraints.Min.X = w
		return surfaceBox(gtx, a.ui, a.ui.p.Surface, unit.Dp(12), func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(18)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.H3(title)
						lbl.Color = a.ui.p.Text
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(13), hint)
							lbl.Color = a.ui.p.TextDim
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.TextButton(&a.wid.headerCxlBtn, "Cancel")
									btn.Color = a.ui.p.Text
									return btn.Layout(gtx)
								})
							}),
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								btn := a.ui.PrimaryButton(&a.wid.headerOkBtn, "Confirm")
								btn.Background = a.ui.p.Error
								return btn.Layout(gtx)
							}),
						)
					}),
				)
			})
		})
	})
}
