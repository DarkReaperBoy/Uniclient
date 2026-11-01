package gui

import (
	"image"

	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/unit"

	"uniclient/engine"
)

func nextUnreadIndex(chats []engine.ChatInfo, from int) int {
	n := len(chats)
	if n == 0 {
		return -1
	}
	if from < 0 {
		from = 0
	}
	for k := 0; k < n; k++ {
		i := (from + k) % n
		if chats[i].UnreadCount > 0 || chats[i].UnreadMark {
			return i
		}
	}
	return -1
}

func hasUnreadChats(chats []engine.ChatInfo) bool {
	for _, c := range chats {
		if c.UnreadCount > 0 || c.UnreadMark {
			return true
		}
	}
	return false
}

func (a *App) gotoNextUnread(visible []engine.ChatInfo) {
	from := sidebarChatsList.Position.First + 1
	idx := nextUnreadIndex(visible, from)
	if idx < 0 {
		return
	}
	c := visible[idx]
	sidebarChatsList.Position.First = idx
	sidebarChatsList.Position.Offset = 0
	sidebarChatsList.Position.BeforeEnd = true
	a.openChat(chatKey{c.AccountID, c.ChatID}, c.Title)
}

func (a *App) layoutNextUnreadBtn(gtx layout.Context, f frame, visible []engine.ChatInfo) {
	if f.search != "" || len(f.accounts) == 0 || len(visible) == 0 {
		return
	}
	if !hasUnreadChats(visible) {
		return
	}
	if a.wid.nextUnreadBtn.Clicked(gtx) {
		a.gotoNextUnread(visible)
	}

	btnSz := gtx.Dp(unit.Dp(42))
	paneW, paneH := gtx.Constraints.Max.X, gtx.Constraints.Max.Y
	pos := image.Pt((paneW-btnSz)/2, paneH-btnSz-gtx.Dp(unit.Dp(14)))

	defer op.Offset(pos).Push(gtx.Ops).Pop()
	gtx.Constraints = layout.Constraints{Max: image.Pt(btnSz, btnSz), Min: image.Pt(btnSz, btnSz)}
	bg := a.ui.p.Accent
	if a.wid.nextUnreadBtn.Hovered() {
		bg = a.ui.p.AccentDim
	}
	_ = roundedFill(gtx, bg, 21, func(gtx layout.Context) layout.Dimensions {
		return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			isz := gtx.Dp(unit.Dp(22))
			gtx.Constraints = layout.Constraints{Max: image.Pt(isz, isz), Min: image.Pt(0, 0)}
			if iconNavArrowDown == nil {
				return layout.Dimensions{}
			}
			return iconNavArrowDown.Layout(gtx, a.ui.p.Background)
		})
	})
}
