package gui

// Groups in common (AyuGram parity slice 107): the DM profile panel's
// shared-groups section — engine.GetCommonChats rows with member counts,
// tap opens the chat when it is in the loaded list (honest toast when
// not). The section hides entirely for chats without common groups.

import (
	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/cores"
	"uniclient/engine"
)

// commonGroupRow is one rendered shared-group row.
type commonGroupRow struct {
	id    string
	title string
	sub   string
}

// commonGroupsGate: the section shows on DM profiles only.
func commonGroupsGate(chat engine.ChatInfo) bool {
	return chat.Type == engine.ChatTypeDMVal
}

// commonMemberLabel renders the member count line ("" for unknown).
func commonMemberLabel(n int) string {
	switch {
	case n <= 0:
		return ""
	case n == 1:
		return "1 member"
	default:
		return itoa(n) + " members"
	}
}

// commonGroupRows maps engine dialogs to rows (pure).
func commonGroupRows(ds []cores.Dialog) []commonGroupRow {
	rows := make([]commonGroupRow, 0, len(ds))
	for _, d := range ds {
		title := d.Title
		if title == "" {
			title = "Group"
		}
		rows = append(rows, commonGroupRow{
			id:    d.ID,
			title: title,
			sub:   commonMemberLabel(d.MemberCount),
		})
	}
	return rows
}

// commonGroupBtns pools the row clickables by dialog ID.
var commonGroupBtns = map[string]*widget.Clickable{}

func commonGroupBtn(id string) *widget.Clickable {
	if btn, ok := commonGroupBtns[id]; ok {
		return btn
	}
	btn := new(widget.Clickable)
	commonGroupBtns[id] = btn
	if len(commonGroupBtns) > 128 {
		commonGroupBtns = map[string]*widget.Clickable{id: btn}
	}
	return btn
}

// loadCommonChats fetches the shared groups for a DM peer (slice 107).
func (a *App) loadCommonChats(k chatKey) {
	go func() {
		ds, err := a.eng.GetCommonChats(k.AccountID, k.ChatID, 30)
		a.mu.Lock()
		if a.panelChat == k {
			if err != nil {
				a.commonChats = nil
			} else {
				a.commonChats = ds
			}
			a.commonLoaded = true
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// layoutCommonGroups renders the section (hidden when empty/unloaded).
func (a *App) layoutCommonGroups(gtx layout.Context, f frame, k chatKey) layout.Dimensions {
	if !f.commonLoaded || len(f.commonChats) == 0 {
		return layout.Dimensions{}
	}
	rows := commonGroupRows(f.commonChats)
	var children []layout.FlexChild
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Groups in common ("+itoa(len(rows))+")")
	}))
	for _, r := range rows {
		r := r
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if btn := commonGroupBtn(r.id); btn.Clicked(gtx) {
				a.openCommonGroup(f, k.AccountID, r.id)
			}
			return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				mbl := material.ButtonLayout(a.ui.Theme, commonGroupBtn(r.id))
				mbl.Background = a.ui.p.Surface
				mbl.CornerRadius = 8
				return mbl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return a.ui.Avatar(gtx, r.title, unit.Dp(32), dotNone)
								})
							}),
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										if f.cfg.Streamer {
											return a.masked(gtx, a.ui.Label(unit.Sp(14), r.title).Layout)
										}
										return a.ui.Label(unit.Sp(14), r.title).Layout(gtx)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										if r.sub == "" {
											return layout.Dimensions{}
										}
										lbl := a.ui.Dim(unit.Sp(11), r.sub)
										lbl.Color = a.ui.p.TextDim
										return lbl.Layout(gtx)
									}),
								)
							}),
						)
					})
				})
			})
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// openCommonGroup opens a shared group chat (or toasts honestly when the
// chat is not in the loaded list).
func (a *App) openCommonGroup(f frame, accountID, chatID string) {
	for _, c := range f.chats {
		if c.AccountID == accountID && c.ChatID == chatID {
			a.openChat(chatKey{AccountID: accountID, ChatID: chatID}, c.Title)
			return
		}
	}
	a.setToast("Group not in your chat list")
}
