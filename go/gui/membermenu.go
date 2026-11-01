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

type memberMenuState struct {
	chat   engine.ChatInfo
	member engine.MemberInfo
	pos    image.Point
}

func memberMenuItems(m engine.MemberInfo, chat engine.ChatInfo, selfID string, separate bool) []chatMenuAction {
	if !chat.IsAdmin && !chat.IsCreator {
		return nil
	}
	if m.UserID == "" || (selfID != "" && m.UserID == selfID) {
		return nil
	}
	admin := func(ids ...string) []chatMenuAction {
		if separate {
			kept := ids[:0]
			for _, id := range ids {
				if id != "restrict" && id != "ban" {
					kept = append(kept, id)
				}
			}
			ids = kept
		}
		out := make([]chatMenuAction, 0, len(ids))
		for _, id := range ids {
			out = append(out, chatMenuAction{memberActionLabel(id), id})
		}
		return out
	}
	switch m.Role {
	case "owner", "creator":
		return nil
	case "admin":
		return admin("demote", "restrict", "ban", "remove")
	case "banned":
		return admin("unban")
	case "restricted":
		return admin("restrict", "ban", "remove")
	default:
		return admin("promote", "restrict", "ban", "remove")
	}
}

func memberActionLabel(id string) string {
	switch id {
	case "demote":
		return "Demote to member"
	case "restrict":
		return "Restrict"
	case "ban":
		return "Ban"
	case "remove":
		return "Remove from chat"
	case "unban":
		return "Unban"
	case "promote":
		return "Promote to admin"
	}
	return id
}

func (a *App) openMemberMenu(chat engine.ChatInfo, m engine.MemberInfo, pos image.Point) {
	a.mu.Lock()
	a.memberMenu = &memberMenuState{chat: chat, member: m, pos: pos}
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) closeMemberMenu() {
	a.mu.Lock()
	a.memberMenu = nil
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) dispatchMemberMenu(st *memberMenuState, action string) {
	a.closeMemberMenu()
	if st == nil {
		return
	}
	chat, m := st.chat, st.member
	switch action {
	case "restrict":
		a.openRestrictDialog(chat, m)
		return
	case "ban":
		a.openBanDialog(chat, m)
		return
	}
	go func() {
		var err error
		var verb string
		switch action {
		case "promote":
			err, verb = a.eng.PromoteAdmin(chat.AccountID, chat.ChatID, m.UserID), "Promoted"
		case "demote":
			err, verb = a.eng.DemoteAdmin(chat.AccountID, chat.ChatID, m.UserID), "Demoted"
		case "restrict":
			err, verb = a.eng.RestrictMember(chat.AccountID, chat.ChatID, m.UserID), "Restricted"
		case "ban":
			err, verb = a.eng.BanMember(chat.AccountID, chat.ChatID, m.UserID), "Banned"
		case "unban":
			err, verb = a.eng.UnbanMember(chat.AccountID, chat.ChatID, m.UserID), "Unbanned"
		case "remove":
			err, verb = a.eng.RemoveMember(chat.AccountID, chat.ChatID, m.UserID), "Removed"
		default:
			return
		}
		if err != nil {
			a.setToast(verb + " failed: " + err.Error())
			return
		}
		a.setToast(verb + " " + memberDisplayName(m))
		a.mu.Lock()
		k := a.panelChat
		a.mu.Unlock()
		if k.AccountID != "" {
			go a.loadPanel(k)
		}
	}()
}

func memberDisplayName(m engine.MemberInfo) string {
	if m.DisplayName != "" {
		return m.DisplayName
	}
	if m.Username != "" {
		return m.Username
	}
	return "user " + m.UserID
}

func (a *App) layoutMemberMenu(gtx layout.Context, f frame) layout.Dimensions {
	m := f.memberMenu
	items := memberMenuItems(m.member, m.chat, selfIDOf(f, m.chat.AccountID), a.isSeparate())
	if len(items) == 0 {
		a.closeMemberMenu()
		return layout.Dimensions{}
	}
	growClickables(&a.wid.memberMenuBtns, len(items))

	menuW := gtx.Dp(unit.Dp(200))
	rowH := gtx.Dp(unit.Dp(36))
	h := gtx.Dp(unit.Dp(8)) + len(items)*rowH + gtx.Dp(unit.Dp(8))

	pos := m.pos
	if pos.X+menuW > gtx.Constraints.Max.X {
		pos.X = gtx.Constraints.Max.X - menuW
	}
	if pos.X < 0 {
		pos.X = 0
	}
	if pos.Y+h > gtx.Constraints.Max.Y {
		pos.Y = gtx.Constraints.Max.Y - h
	}
	if pos.Y < 0 {
		pos.Y = 0
	}

	var dims layout.Dimensions
	func() {
		defer op.Offset(pos).Push(gtx.Ops).Pop()
		gtx.Constraints = layout.Constraints{Max: image.Pt(menuW, h), Min: image.Pt(menuW, h)}
		dims = roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
			children := make([]layout.FlexChild, 0, len(items)+2)
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Dimensions{Size: image.Pt(menuW, gtx.Dp(unit.Dp(4)))}
			}))
			for i := range items {
				i := i
				children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := &a.wid.memberMenuBtns[i]
					if btn.Clicked(gtx) {
						st := *m
						a.dispatchMemberMenu(&st, items[i].id)
					}
					gtx.Constraints.Min.Y = rowH
					return memberMenuRow(gtx, a, btn, items[i], rowH)
				}))
			}
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Dimensions{Size: image.Pt(menuW, gtx.Dp(unit.Dp(4)))}
			}))
			layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
			return layout.Dimensions{Size: image.Pt(menuW, h)}
		})
	}()
	return dims
}

func memberMenuRow(gtx layout.Context, a *App, btn *widget.Clickable, item chatMenuAction, rowH int) layout.Dimensions {
	bl := material.ButtonLayout(a.ui.Theme, btn)
	bl.Background = a.ui.p.Surface
	bl.CornerRadius = 8
	return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.UniformInset(unit.Dp(9)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Label(unit.Sp(14), item.label)
			switch item.id {
			case "ban", "remove":
				lbl.Color = a.ui.p.Error
			default:
				lbl.Color = a.ui.p.Text
			}
			return lbl.Layout(gtx)
		})
	})
}

func selfIDOf(f frame, accountID string) string {
	return accountByID(f, accountID).SelfUserID
}

func panelChatOf(f frame) (engine.ChatInfo, bool) {
	for _, c := range f.chats {
		if c.AccountID == f.panelChat.AccountID && c.ChatID == f.panelChat.ChatID {
			return c, true
		}
	}
	return engine.ChatInfo{}, false
}

func (a *App) memberRowBtn(userID string) *widget.Clickable {
	if btn, ok := a.wid.memberRowBtns[userID]; ok {
		return btn
	}
	btn := new(widget.Clickable)
	a.wid.memberRowBtns[userID] = btn
	if len(a.wid.memberRowBtns) > 512 {
		a.wid.memberRowBtns = map[string]*widget.Clickable{userID: btn}
	}
	return btn
}
