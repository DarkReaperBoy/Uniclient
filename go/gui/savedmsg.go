package gui

import (
	"image"
	"image/color"
	"log"

	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Saved Messages surface (slice 116, AyuGram sidebar parity): a pinned
// "Saved Messages" shortcut row above the chat list for every account whose
// core exposes its self user id (engine selfIDer — Telegram today), the
// bookmark avatar on the saved chat wherever it renders, and the saved chat
// pinned first in the forward picker. Sublists/tags remain engine-gated.

// savedRowAccounts returns the account ids that get a shortcut row, in
// account-list order. Pure — unit-tested.
func savedRowAccounts(accs []engine.AccountInfo, caps map[string]bool) []string {
	var out []string
	for _, acc := range accs {
		if caps[acc.ID] {
			out = append(out, acc.ID)
		}
	}
	return out
}

// isSavedMessagesChat reports whether (account, chat) is that account's
// Saved Messages chat. Pure — unit-tested.
func isSavedMessagesChat(accountID, chatID string, saved map[string]string) bool {
	return saved[accountID] != "" && saved[accountID] == chatID
}

// savedRowSubtitle: with multiple capable accounts each row disambiguates
// with the account name; a single row needs none (Telegram shows none).
// Pure — unit-tested.
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

// buildForwardCandidates: same-account chats except the source, with the
// account's Saved Messages chat pinned first (AyuGram/Telegram behavior).
// Pure — unit-tested.
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
			continue // already pinned first
		}
		out = append(out, c)
	}
	return out
}

// savedTargetAccount picks the drawer's Saved Messages target: the scoped
// account when capable, else the first capable account ("" when none).
func savedTargetAccount(f frame) string {
	scope := f.acctFilter
	for _, id := range f.savedMsgAccts {
		if scope == "" || id == scope {
			return id
		}
	}
	return ""
}

// savedMsgBtns pools the shortcut-row clickables.
var savedMsgBtns []widget.Clickable

// layoutSavedRow renders the pinned "Saved Messages" shortcut row(s) above
// the folder tabs (hidden while searching or in the archive view).
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

// openSavedMessages ensures the saved chat exists and navigates to it.
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

// ensureForwardSavedChat makes sure the source account's saved chat exists
// before the picker renders, so it appears as a candidate (AyuGram always
// offers Save to Saved Messages).
func (a *App) ensureForwardSavedChat(src engine.CachedMessage) {
	if !a.savedCap[src.AccountID] {
		return
	}
	go func() {
		if _, err := a.eng.OpenSavedMessages(src.AccountID); err != nil {
			return // the dialog simply lists the other chats
		}
		a.refreshChats()
	}()
}

// drawBookmarkAvatar paints the Saved Messages avatar: accent circle with
// the Material bookmark glyph (Telegram's saved-chat look, drawn from
// shapes — never copied assets).
func drawBookmarkAvatar(gtx layout.Context, u *UI, sizeDp unit.Dp) layout.Dimensions {
	size := gtx.Dp(sizeDp)
	defer clip.Ellipse{Min: image.Pt(0, 0), Max: image.Pt(size, size)}.Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, u.p.Accent)
	if iconActionBookmark != nil {
		ic := size * 52 / 100 // icon ~52% of the circle
		layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			gtx.Constraints = layout.Exact(image.Pt(ic, ic))
			return iconActionBookmark.Layout(gtx, color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF})
		})
	}
	return layout.Dimensions{Size: image.Pt(size, size)}
}
