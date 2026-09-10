package gui

import (
	"image"
	"strings"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Add-members dialog (AyuGram peer menu, slice 79): opened from the chat
// header ⋮ menu for groups/channels — lists the account's contacts with
// a search filter and multi-select check circles; "Add" dispatches
// engine.AddMembers (one call, all selected), then refreshes the info
// panel's member list when it is open.

// addMemDlgState is the open add-members dialog (nil when closed).
type addMemDlgState struct {
	accountID string
	chatID    string
	contacts  []engine.ContactInfo
	loaded    bool
	err       string
	sel       map[string]bool // user id → selected
}

var (
	addMemCloseBtn widget.Clickable
	addMemAddBtn   widget.Clickable
	addMemRowBtns  []widget.Clickable
	addMemSearchEd widget.Editor
	addMemList     widget.List
	addMemKeyTag   = new(struct{})
)

func init() {
	addMemSearchEd.SingleLine = true
	addMemList.Axis = layout.Vertical
}

// addMemFilter narrows contacts by a case-insensitive substring match on
// display name, username, or phone. Pure — locked by tests.
func addMemFilter(contacts []engine.ContactInfo, q string) []engine.ContactInfo {
	q = strings.TrimSpace(strings.ToLower(q))
	if q == "" {
		return contacts
	}
	var out []engine.ContactInfo
	for _, c := range contacts {
		if strings.Contains(strings.ToLower(c.DisplayName), q) ||
			strings.Contains(strings.ToLower(c.Username), q) ||
			strings.Contains(c.Phone, q) {
			out = append(out, c)
		}
	}
	return out
}

// ── state transitions ─────────────────────────────────────────────────────

// openAddMemberDialog opens the picker for a group chat (async contact load).
func (a *App) openAddMemberDialog(c engine.ChatInfo) {
	a.mu.Lock()
	st := &addMemDlgState{accountID: c.AccountID, chatID: c.ChatID, sel: make(map[string]bool)}
	a.addMemDlg = st
	a.mu.Unlock()
	a.invalidate()
	go func() {
		contacts, err := a.eng.GetContacts(c.AccountID)
		a.mu.Lock()
		if a.addMemDlg != st {
			a.mu.Unlock()
			return
		}
		if err != nil {
			st.err = err.Error()
		} else {
			st.contacts, st.loaded = contacts, true
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// closeAddMemberDialog dismisses the picker.
func (a *App) closeAddMemberDialog() {
	a.mu.Lock()
	a.addMemDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// addMembersFromDialog adds every selected contact to the chat (async),
// then refreshes the open panel's member list.
func (a *App) addMembersFromDialog() {
	a.mu.Lock()
	st := a.addMemDlg
	if st == nil {
		a.mu.Unlock()
		return
	}
	var ids []string
	for id, on := range st.sel {
		if on {
			ids = append(ids, id)
		}
	}
	a.addMemDlg = nil
	k := chatKey{AccountID: st.accountID, ChatID: st.chatID}
	a.mu.Unlock()
	a.invalidate()
	if len(ids) == 0 {
		return
	}
	go func() {
		if err := a.eng.AddMembers(k.AccountID, k.ChatID, ids); err != nil {
			a.setToast("Add members failed: " + err.Error())
			return
		}
		a.setToast("Added " + itoa(len(ids)) + " member" + pluralS(len(ids)))
		// Refresh the info panel (member list) when it is open for this chat.
		a.mu.Lock()
		panelOpen := a.panelOpen && a.panelChat == k
		a.mu.Unlock()
		if panelOpen {
			a.loadPanel(k)
		}
	}()
}

// pluralS returns "s" for counts != 1. Pure.
func pluralS(n int) string {
	if n == 1 {
		return ""
	}
	return "s"
}

// ── layout ────────────────────────────────────────────────────────────────

// layoutAddMemberDialog renders the picker card.
func (a *App) layoutAddMemberDialog(gtx layout.Context, f frame) layout.Dimensions {
	st := f.addMemDlg

	// Esc closes (self-handled).
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, addMemKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeAddMemberDialog()
		}
	}

	if addMemCloseBtn.Clicked(gtx) {
		a.closeAddMemberDialog()
	}
	selCount := 0
	for _, on := range st.sel {
		if on {
			selCount++
		}
	}
	if addMemAddBtn.Clicked(gtx) && selCount > 0 {
		a.addMembersFromDialog()
	}

	shown := addMemFilter(st.contacts, addMemSearchEd.Text())
	growClickables(&addMemRowBtns, len(shown))

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(360))
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(460))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					// title + selected count
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.H3("Add Members")
								return lbl.Layout(gtx)
							}),
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								return layout.Dimensions{}
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								if selCount == 0 {
									return layout.Dimensions{}
								}
								lbl := a.ui.Label(unit.Sp(12), itoa(selCount)+" selected")
								lbl.Color = a.ui.p.Accent
								return lbl.Layout(gtx)
							}),
						)
					}),
					// search filter
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							for {
								ev, ok := addMemSearchEd.Update(gtx)
								if !ok {
									break
								}
								if _, is := ev.(widget.ChangeEvent); is {
									a.invalidate()
								}
							}
							ed := a.ui.Editor(&addMemSearchEd, "Search contacts")
							return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
								return layout.UniformInset(unit.Dp(6)).Layout(gtx, ed.Layout)
							})
						})
					}),
					// contact list
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.addMemContactList(gtx, f, st, shown)
						})
					}),
					// action row
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									bl := material.Button(a.ui.Theme, &addMemAddBtn, "Add")
									bl.Background = a.ui.p.Accent
									if selCount == 0 {
										bl.Background = a.ui.p.SurfaceHi
									}
									bl.CornerRadius = 10
									return bl.Layout(gtx)
								}),
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									return layout.Dimensions{}
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									bl := material.Button(a.ui.Theme, &addMemCloseBtn, "Close")
									bl.Background = a.ui.p.SurfaceHi
									bl.Color = a.ui.p.Text
									bl.CornerRadius = 10
									return bl.Layout(gtx)
								}),
							)
						})
					}),
				)
			})
		})
	})
}

// addMemContactList renders the filtered contacts with check circles.
func (a *App) addMemContactList(gtx layout.Context, f frame, st *addMemDlgState, shown []engine.ContactInfo) layout.Dimensions {
	if st.err != "" && !st.loaded {
		return a.centeredStateLabel(gtx, "Failed to load contacts")
	}
	if !st.loaded {
		return a.centeredStateLabel(gtx, "Loading…")
	}
	if len(st.contacts) == 0 {
		return a.centeredStateLabel(gtx, "No contacts")
	}
	if len(shown) == 0 {
		return a.centeredStateLabel(gtx, "No contacts match")
	}
	lt := material.List(a.ui.Theme, &addMemList)
	return lt.Layout(gtx, len(shown), func(gtx layout.Context, i int) layout.Dimensions {
		c := shown[i]
		if addMemRowBtns[i].Clicked(gtx) {
			a.mu.Lock()
			if st.sel == nil {
				st.sel = make(map[string]bool)
			}
			st.sel[c.UserID] = !st.sel[c.UserID]
			on := st.sel[c.UserID]
			a.mu.Unlock()
			_ = on
			a.invalidate()
		}
		sel := st.sel[c.UserID]
		bl := material.ButtonLayout(a.ui.Theme, &addMemRowBtns[i])
		bl.Background = a.ui.p.SurfaceHi
		if sel {
			bl.Background = withAlpha(a.ui.p.Accent, 0x33)
		}
		bl.CornerRadius = 10
		return layout.Inset{Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return a.streamerB64Avatar(gtx, f, c.DisplayName, c.AvatarB64, unit.Dp(36), dotNone)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										name := c.DisplayName
										if name == "" {
											name = "Contact"
										}
										lbl := a.ui.Label(unit.Sp(14), name)
										if f.cfg.Streamer {
											return a.masked(gtx, lbl.Layout)
										}
										return lbl.Layout(gtx)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										if c.Username == "" {
											return layout.Dimensions{}
										}
										lbl := a.ui.Dim(unit.Sp(12), "@"+c.Username)
										lbl.Color = a.ui.p.TextFaint
										return lbl.Layout(gtx)
									}),
								)
							})
						}),
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							return layout.Dimensions{}
						}),
						// check circle (slice-14 selection style)
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return a.selectionCircle(gtx, sel)
						}),
					)
				})
			})
		})
	})
}
