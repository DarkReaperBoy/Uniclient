package gui

// Member context menu (AyuGram parity slice 106): the profile panel's
// member rows open an admin menu (tap on desktop/mobile — AyuGram uses
// right-click/long-press; a tap is the honest mobile-friendly equivalent
// for rows that had no other click behavior). Actions dispatch the real
// engine member-admin calls (Promote/Demote/Restrict/Ban/Unban/Remove)
// and refresh the panel. Owners and self are untouchable; non-admin
// viewers get no menu at all — never dead UI (§1.10).

import (
	"image"

	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// memberMenuState is the open member menu (nil when closed).
type memberMenuState struct {
	chat   engine.ChatInfo
	member engine.MemberInfo
	pos    image.Point
}

// memberMenuItems derives the admin actions for one member (pure).
// Gated on the viewer's admin rights (chat.IsAdmin/IsCreator); the owner
// role and self rows get nothing (the engine would refuse anyway — the
// GUI never offers a dead action).
func memberMenuItems(m engine.MemberInfo, chat engine.ChatInfo, selfID string) []chatMenuAction {
	if !chat.IsAdmin && !chat.IsCreator {
		return nil
	}
	if m.UserID == "" || (selfID != "" && m.UserID == selfID) {
		return nil
	}
	switch m.Role {
	case "owner", "creator":
		return nil
	case "admin":
		return []chatMenuAction{
			{"Demote to member", "demote"},
			{"Restrict", "restrict"},
			{"Ban", "ban"},
			{"Remove from chat", "remove"},
		}
	case "banned":
		return []chatMenuAction{
			{"Unban", "unban"},
		}
	case "restricted":
		return []chatMenuAction{
			{"Restrict", "restrict"},
			{"Ban", "ban"},
			{"Remove from chat", "remove"},
		}
	default: // member
		return []chatMenuAction{
			{"Promote to admin", "promote"},
			{"Restrict", "restrict"},
			{"Ban", "ban"},
			{"Remove from chat", "remove"},
		}
	}
}

// member menu button pool.
var memberMenuBtns []widget.Clickable

// openMemberMenu opens the member menu at pos (profile-panel coords).
func (a *App) openMemberMenu(chat engine.ChatInfo, m engine.MemberInfo, pos image.Point) {
	a.mu.Lock()
	a.memberMenu = &memberMenuState{chat: chat, member: m, pos: pos}
	a.mu.Unlock()
	a.invalidate()
}

// closeMemberMenu dismisses it.
func (a *App) closeMemberMenu() {
	a.mu.Lock()
	a.memberMenu = nil
	a.mu.Unlock()
	a.invalidate()
}

// dispatchMemberMenu runs one admin action and refreshes the panel.
func (a *App) dispatchMemberMenu(st *memberMenuState, action string) {
	a.closeMemberMenu()
	if st == nil {
		return
	}
	chat, m := st.chat, st.member
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
			go a.loadPanel(k) // refresh the member list
		}
	}()
}

// memberDisplayName renders a member's display name with an honest
// fallback.
func memberDisplayName(m engine.MemberInfo) string {
	if m.DisplayName != "" {
		return m.DisplayName
	}
	if m.Username != "" {
		return m.Username
	}
	return "user " + m.UserID
}

// ── layout ────────────────────────────────────────────────────────────────

// layoutMemberMenu draws the member popup menu, clamped to its pane.
func (a *App) layoutMemberMenu(gtx layout.Context, f frame) layout.Dimensions {
	m := f.memberMenu
	items := memberMenuItems(m.member, m.chat, selfIDOf(f, m.chat.AccountID))
	if len(items) == 0 {
		a.closeMemberMenu() // stale state — the viewer's rights changed
		return layout.Dimensions{}
	}
	growClickables(&memberMenuBtns, len(items))

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
					btn := &memberMenuBtns[i]
					if btn.Clicked(gtx) {
						st := *m
						a.dispatchMemberMenu(&st, items[i].action)
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

// memberMenuRow renders one row (destructive rows tinted).
func memberMenuRow(gtx layout.Context, a *App, btn *widget.Clickable, item chatMenuAction, rowH int) layout.Dimensions {
	bl := material.ButtonLayout(a.ui.Theme, btn)
	bl.Background = a.ui.p.Surface
	bl.CornerRadius = 8
	return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.UniformInset(unit.Dp(9)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Label(unit.Sp(14), item.label)
			switch item.action {
			case "ban", "remove":
				lbl.Color = a.ui.p.Error
			default:
				lbl.Color = a.ui.p.Text
			}
			return lbl.Layout(gtx)
		})
	})
}

// selfIDOf resolves the account's self user ID.
func selfIDOf(f frame, accountID string) string {
	return accountByID(f, accountID).SelfUserID
}

// panelChatOf resolves the open profile panel's chat (slice 106).
func panelChatOf(f frame) (engine.ChatInfo, bool) {
	for _, c := range f.chats {
		if c.AccountID == f.panelChat.AccountID && c.ChatID == f.panelChat.ChatID {
			return c, true
		}
	}
	return engine.ChatInfo{}, false
}

// memberRowBtn pools member-row clickables by user ID.
var memberRowBtns = map[string]*widget.Clickable{}

func memberRowBtn(userID string) *widget.Clickable {
	if btn, ok := memberRowBtns[userID]; ok {
		return btn
	}
	btn := new(widget.Clickable)
	memberRowBtns[userID] = btn
	if len(memberRowBtns) > 512 {
		memberRowBtns = map[string]*widget.Clickable{userID: btn}
	}
	return btn
}
