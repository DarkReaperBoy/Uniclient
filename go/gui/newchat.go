package gui

import (
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// New group / channel creation (AyuGram parity, matrix #300): the drawer's
// "New group" / "New channel" actions. Name (+ description for channels,
// with a megagroup switch) → engine.CreateGroup / CreateChannel /
// CreateMegagroup; the created chat opens on success.

// newChatDlg: open dialog state (nil when closed).
type newChatDlg struct {
	kind       int // 0 = group, 1 = channel
	accountID  string
	supergroup bool // channel only: create a megagroup
	busy       bool // creation in flight

	// group member picker (slice 25): cached contacts + selected user IDs
	members      map[string]bool
	contacts     []engine.ContactInfo
	contactsLoad bool
}

var (
	newDlgCancel widget.Clickable
	newDlgCreate widget.Clickable
	newDlgMega   widget.Bool
	newDlgNameEd widget.Editor
	newDlgDescEd widget.Editor

	newDlgMemberRows []widget.Clickable // group member picker
	newDlgMemberList widget.List
)

func init() {
	newDlgMemberList.Axis = layout.Vertical
}

// openNewChat opens the creation dialog for kind on an account.
func (a *App) openNewChat(kind int, accountID string) {
	if accountID == "" {
		a.setToast("Connect an account first")
		return
	}
	a.mu.Lock()
	a.newDlg = &newChatDlg{kind: kind, accountID: accountID, members: make(map[string]bool)}
	a.mu.Unlock()
	newDlgNameEd.SetText("")
	newDlgDescEd.SetText("")
	newDlgMega.Value = false
	a.invalidate()
	if kind == 0 {
		go func() {
			list, err := a.eng.GetContacts(accountID)
			a.mu.Lock()
			if a.newDlg == nil || a.newDlg.accountID != accountID {
				a.mu.Unlock()
				return
			}
			if err == nil {
				sortContacts(list)
				a.newDlg.contacts = list
			}
			a.newDlg.contactsLoad = true
			a.mu.Unlock()
			a.invalidate()
		}()
	}
}

// closeNewChat dismisses the dialog.
func (a *App) closeNewChat() {
	a.mu.Lock()
	if a.newDlg == nil {
		a.mu.Unlock()
		return
	}
	if a.newDlg.busy {
		a.mu.Unlock() // don't abandon an in-flight creation
		return
	}
	a.newDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// submitNewChat performs the creation and schedules the chat to open (the
// engine emits chat events too; the pending-open keeps it 1:1 with Ayu,
// which drops you straight into the new conversation).
func (a *App) submitNewChat() {
	a.mu.Lock()
	if a.newDlg == nil {
		a.mu.Unlock()
		return
	}
	d := *a.newDlg
	busy := d.busy
	var members []string
	if d.kind == 0 && len(d.members) > 0 {
		for id, on := range d.members {
			if on {
				members = append(members, id)
			}
		}
	}
	a.newDlg.busy = true
	a.mu.Unlock()
	if busy {
		return
	}
	name := strings.TrimSpace(newDlgNameEd.Text())
	desc := strings.TrimSpace(newDlgDescEd.Text())
	if name == "" {
		a.setToast("Enter a name")
		a.mu.Lock()
		a.newDlg.busy = false
		a.mu.Unlock()
		return
	}
	go func() {
		var info *engine.ChatInfo
		var err error
		switch {
		case d.kind == 0:
			info, err = a.eng.CreateGroup(d.accountID, name, members)
		case d.supergroup:
			info, err = a.eng.CreateMegagroup(d.accountID, name, desc, false, 0)
		default:
			info, err = a.eng.CreateChannel(d.accountID, name, desc)
		}
		a.mu.Lock()
		if a.newDlg != nil {
			a.newDlg.busy = false
		}
		if err != nil {
			a.newDlgErr = err.Error()
			a.mu.Unlock()
			a.setToast("Create: " + err.Error())
			return
		}
		a.newDlgErr = ""
		a.newDlg = nil
		// Open the created chat on the GUI goroutine (next frame).
		a.pendingOpen = &chatKey{AccountID: info.AccountID, ChatID: info.ChatID}
		a.pendingTitle = info.Title
		a.mu.Unlock()
		a.setToast("Created " + name)
		a.invalidate()
	}()
}

// layoutNewChatDialog renders the centered creation card over a scrim
// (content pane; the sidebar stays interactive like the folder dialog).
func (a *App) layoutNewChatDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.newDlg
	if newDlgCancel.Clicked(gtx) {
		a.closeNewChat()
	}
	if newDlgCreate.Clicked(gtx) {
		a.submitNewChat()
	}

	title, createLabel := "New group", "Create group"
	descHint := ""
	if d.kind == 1 {
		title, createLabel = "New channel", "Create channel"
		descHint = "Description (optional)"
	}
	if d.busy {
		createLabel = "Creating…"
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(360))
		if gtx.Constraints.Max.Y > gtx.Dp(unit.Dp(440)) {
			gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(440))
		}
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.H3(title)
						return lbl.Layout(gtx)
					}),
					// Group member picker (slice 25).
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if d.kind != 0 {
							return layout.Dimensions{}
						}
						return a.newDlgMemberPicker(gtx, f)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
								return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									ed := a.ui.Editor(&newDlgNameEd, "Name")
									return ed.Layout(gtx)
								})
							})
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if d.kind == 0 {
							return layout.Dimensions{}
						}
						return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
								return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									ed := a.ui.Editor(&newDlgDescEd, descHint)
									return ed.Layout(gtx)
								})
							})
						})
					}),
					// Megagroup switch (channels).
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if d.kind == 0 {
							return layout.Dimensions{}
						}
						prev := newDlgMega.Value
						dims := layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(13), "Supergroup (megagroup)")
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								tg := material.Switch(a.ui.Theme, &newDlgMega, "")
								tg.Color.Enabled = a.ui.p.Accent
								tg.Color.Disabled = a.ui.p.SurfaceHi
								tg.Color.Track = a.ui.p.SurfaceHi
								return tg.Layout(gtx)
							}),
						)
						if newDlgMega.Value != prev {
							a.mu.Lock()
							if a.newDlg != nil {
								a.newDlg.supergroup = newDlgMega.Value
							}
							a.mu.Unlock()
							a.invalidate()
						}
						return dims
					}),
					// Error line (last failure).
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if f.newDlgErr == "" {
							return layout.Dimensions{}
						}
						return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(12), f.newDlgErr)
							lbl.Color = a.ui.p.Error
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.TextButton(&newDlgCancel, "Cancel")
									if d.busy {
										btn.Color = a.ui.p.TextFaint
									}
									return btn.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.PrimaryButton(&newDlgCreate, createLabel)
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

// newDlgMemberPicker: contacts with toggle rows (group creation step 2,
// AyuGram member picker). Selected IDs flow into CreateGroup.
func (a *App) newDlgMemberPicker(gtx layout.Context, f frame) layout.Dimensions {
	d := f.newDlg
	contacts := d.contacts
	growClickables(&newDlgMemberRows, len(contacts))
	for i, c := range contacts {
		i, c := i, c
		if newDlgMemberRows[i].Clicked(gtx) {
			a.mu.Lock()
			if a.newDlg != nil {
				if a.newDlg.members[c.UserID] {
					delete(a.newDlg.members, c.UserID)
				} else {
					a.newDlg.members[c.UserID] = true
				}
			}
			a.mu.Unlock()
			a.invalidate()
		}
	}
	var count int
	for _, on := range d.members {
		if on {
			count++
		}
	}

	maxH := gtx.Dp(unit.Dp(180))
	return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Label(unit.Sp(12), "Add members ("+itoa(count)+" selected)")
				lbl.Color = a.ui.p.TextDim
				return lbl.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if !d.contactsLoad {
					lbl := a.ui.Dim(unit.Sp(12), "Loading contacts…")
					return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, lbl.Layout)
				}
				if len(contacts) == 0 {
					lbl := a.ui.Dim(unit.Sp(12), "No contacts to add")
					return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, lbl.Layout)
				}
				gtx.Constraints.Max.Y = maxH
				return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return newDlgMemberList.Layout(gtx, len(contacts), func(gtx layout.Context, i int) layout.Dimensions {
						c := contacts[i]
						picked := d.members[c.UserID]
						return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return material.ButtonLayout(a.ui.Theme, &newDlgMemberRows[i]).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								bg := a.ui.p.SurfaceHi
								if picked {
									bg = a.ui.p.AccentDim
								}
								return roundedFill(gtx, bg, 8, func(gtx layout.Context) layout.Dimensions {
									return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
										return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
											layout.Rigid(func(gtx layout.Context) layout.Dimensions {
												return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
													if picked {
														return iconNavigationCheck.Layout(gtx, a.ui.p.Accent)
													}
													return a.ui.Avatar(gtx, c.DisplayName, unit.Dp(26), dotNone)
												})
											}),
											layout.Rigid(func(gtx layout.Context) layout.Dimensions {
												lbl := a.ui.Label(unit.Sp(13), c.DisplayName)
												return lbl.Layout(gtx)
											}),
										)
									})
								})
							})
						})
					})
				})
			}),
		)
	})
}
