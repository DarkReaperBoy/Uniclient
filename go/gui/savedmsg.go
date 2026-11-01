package gui

import (
	"image"
	"image/color"
	"log"

	"gioui.org/layout"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

func savedRowAccounts(accs []engine.AccountInfo, caps map[string]bool) []string {
	var out []string
	for _, acc := range accs {
		if caps[acc.ID] {
			out = append(out, acc.ID)
		}
	}
	return out
}

func isSavedMessagesChat(accountID, chatID string, saved map[string]string) bool {
	return saved[accountID] != "" && saved[accountID] == chatID
}

func savedRowSubtitle(id string, accs []engine.AccountInfo, capable int) string {
	if capable <= 1 {
		return ""
	}
	for _, acc := range accs {
		if acc.ID == id {
			if acc.DisplayName != "" {
				return acc.DisplayName
			}
			return acc.ID
		}
	}
	return id
}

func buildForwardCandidates(chats []engine.ChatInfo, src engine.CachedMessage, savedChatID string) []engine.ChatInfo {
	var out []engine.ChatInfo
	if savedChatID != "" {
		out = append(out, engine.ChatInfo{
			AccountID: src.AccountID,
			ChatID:    savedChatID,
			Title:     "Saved Messages",
		})
	}
	for _, c := range chats {
		if c.AccountID != src.AccountID || c.ChatID == src.ChatID {
			continue
		}
		if savedChatID != "" && c.ChatID == savedChatID {
			continue
		}
		out = append(out, c)
	}
	return out
}

func savedTargetAccount(f frame) string {
	scope := f.acctFilter
	for _, id := range f.savedMsgAccts {
		if scope == "" || id == scope {
			return id
		}
	}
	return ""
}

var savedMsgBtns []widget.Clickable

func (a *App) layoutSavedRow(gtx layout.Context, f frame) layout.Dimensions {
	if f.search != "" || f.archiveView || len(f.savedMsgAccts) == 0 {
		return layout.Dimensions{}
	}
	for len(savedMsgBtns) < len(f.savedMsgAccts) {
		savedMsgBtns = append(savedMsgBtns, widget.Clickable{})
	}
	return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		rows := make([]layout.FlexChild, 0, len(f.savedMsgAccts))
		for i, accID := range f.savedMsgAccts {
			i, accID := i, accID
			rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := &savedMsgBtns[i]
				if btn.Clicked(gtx) {
					a.openSavedMessages(accID)
				}
				bl := material.ButtonLayout(a.ui.Theme, btn)
				bl.Background = a.ui.p.Surface
				bl.CornerRadius = 0
				return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4), Left: unit.Dp(4), Right: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return drawBookmarkAvatar(gtx, a.ui, unit.Dp(38))
								})
							}),
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										lbl := a.ui.Label(unit.Sp(14), "Saved Messages")
										lbl.MaxLines = 1
										return lbl.Layout(gtx)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										sub := savedRowSubtitle(accID, f.accounts, len(f.savedMsgAccts))
										if sub == "" {
											return layout.Dimensions{}
										}
										return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
											lbl := a.ui.Dim(unit.Sp(11), sub)
											lbl.MaxLines = 1
											return lbl.Layout(gtx)
										})
									}),
								)
							}),
						)
					})
				})
			}))
		}
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
	})
}

func (a *App) openSavedMessages(accountID string) {
	go func() {
		chatID, err := a.eng.OpenSavedMessages(accountID)
		if err != nil {
			log.Printf("gui: saved messages: %v", err)
			a.setToast("Saved Messages unavailable: " + err.Error())
			return
		}
		a.openChat(chatKey{AccountID: accountID, ChatID: chatID}, "Saved Messages")
		a.refreshChats()
	}()
}

func (a *App) ensureForwardSavedChat(src engine.CachedMessage) {
	if !a.savedCap[src.AccountID] {
		return
	}
	go func() {
		if _, err := a.eng.OpenSavedMessages(src.AccountID); err != nil {
			return
		}
		a.refreshChats()
	}()
}

func drawBookmarkAvatar(gtx layout.Context, u *UI, sizeDp unit.Dp) layout.Dimensions {
	size := gtx.Dp(sizeDp)
	paint.FillShape(gtx.Ops, u.p.Accent, avatarShapeClip(gtx.Ops, size, u.avatarRadiusPx(size)))
	if iconActionBookmark != nil {
		ic := size * 52 / 100
		gtx.Constraints = layout.Exact(image.Pt(size, size))
		layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			gtx.Constraints = layout.Exact(image.Pt(ic, ic))
			return iconActionBookmark.Layout(gtx, color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF})
		})
	}
	return layout.Dimensions{Size: image.Pt(size, size)}
}
