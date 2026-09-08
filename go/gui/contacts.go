package gui

import (
	"image"
	"image/color"
	"strings"

	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Contacts screen (AyuGram parity, matrix #299): the account's contact
// book with search, per-contact jump-to-chat, and the add-contact dialog.
// Data comes from engine.GetContacts; adding goes through engine.AddContact.

var (
	contactsBackBtn widget.Clickable
	contactsAddBtn  widget.Clickable
	contactsRows    []widget.Clickable
	contactsSearch  widget.Editor
	contactsList    widget.List

	// add-contact dialog
	addDlgCancel widget.Clickable
	addDlgSave   widget.Clickable
	addPhoneEd   widget.Editor
	addFirstEd   widget.Editor
	addLastEd    widget.Editor
)

func init() {
	contactsList.Axis = layout.Vertical
}

// contactMatches reports whether a contact matches the (case-insensitive)
// query across display name, username, and phone.
func contactMatches(c engine.ContactInfo, q string) bool {
	q = strings.ToLower(strings.TrimSpace(q))
	if q == "" {
		return true
	}
	if strings.Contains(strings.ToLower(c.DisplayName), q) {
		return true
	}
	if strings.Contains(strings.ToLower(c.Username), q) {
		return true
	}
	if strings.Contains(strings.ToLower(c.Phone), q) {
		return true
	}
	return false
}

// contactSubtitle: username / phone, else a hint.
func contactSubtitle(c engine.ContactInfo) string {
	if c.Username != "" {
		return "@" + c.Username
	}
	if c.Phone != "" {
		return c.Phone
	}
	return ""
}

// contactBadge: the small status text on the row.
func contactBadge(c engine.ContactInfo) string {
	if c.IsBot {
		return "bot"
	}
	if c.IsOnline {
		return "online"
	}
	return ""
}

// sortContacts orders by display name (case-insensitive, stable).
func sortContacts(list []engine.ContactInfo) {
	for i := 1; i < len(list); i++ {
		for j := i; j > 0; j-- {
			a, b := list[j-1], list[j]
			an, bn := strings.ToLower(a.DisplayName), strings.ToLower(b.DisplayName)
			if an <= bn {
				break
			}
			list[j-1], list[j] = b, a
		}
	}
}

// openContacts shows the contacts screen for an account and loads the list.
func (a *App) openContacts(accountID string) {
	a.mu.Lock()
	a.contactsOpen = true
	a.contactsFor = accountID
	a.contacts = nil
	a.contactsLoad = true
	a.addDlgOpen = false
	a.mu.Unlock()
	contactsSearch.SetText("")
	addPhoneEd.SetText("")
	addFirstEd.SetText("")
	addLastEd.SetText("")
	a.invalidate()
	go func() {
		list, err := a.eng.GetContacts(accountID)
		a.mu.Lock()
		if err != nil {
			a.contacts = nil
		} else {
			sortContacts(list)
			a.contacts = list
		}
		a.contactsLoad = false
		a.mu.Unlock()
		if err != nil {
			a.setToast("Contacts: " + err.Error())
			return
		}
		a.invalidate()
	}()
}

// closeContacts dismisses the contacts screen (and its dialog).
func (a *App) closeContacts() {
	a.mu.Lock()
	a.contactsOpen = false
	a.addDlgOpen = false
	a.mu.Unlock()
	a.invalidate()
}

// contactChat finds the DM chat row for a contact (Telegram peers: a user's
// DM chat is keyed by the user ID).
func contactChat(chats []engine.ChatInfo, accountID, userID string) (engine.ChatInfo, bool) {
	for _, c := range chats {
		if c.AccountID == accountID && c.ChatID == userID && c.Type == engine.ChatTypeDMVal {
			return c, true
		}
	}
	return engine.ChatInfo{}, false
}

// submitAddContact adds a contact by phone (async, engine.AddContact).
func (a *App) submitAddContact() {
	phone := strings.TrimSpace(addPhoneEd.Text())
	first := strings.TrimSpace(addFirstEd.Text())
	last := strings.TrimSpace(addLastEd.Text())
	if phone == "" || first == "" {
		a.setToast("Enter a phone number and a first name")
		return
	}
	a.mu.Lock()
	acc := a.contactsFor
	busy := a.addDlgBusy
	a.addDlgBusy = true
	a.mu.Unlock()
	if busy {
		return
	}
	go func() {
		_, err := a.eng.AddContact(acc, phone, first, last, "")
		a.mu.Lock()
		a.addDlgBusy = false
		a.mu.Unlock()
		if err != nil {
			a.setToast("Add contact: " + err.Error())
			return
		}
		a.setToast("Contact added")
		// Reload the list on success.
		acc2 := acc
		go func() {
			list, err := a.eng.GetContacts(acc2)
			a.mu.Lock()
			if err == nil {
				sortContacts(list)
				a.contacts = list
			}
			a.mu.Unlock()
			a.invalidate()
		}()
		a.mu.Lock()
		a.addDlgOpen = false
		a.mu.Unlock()
		a.invalidate()
	}()
}

// layoutContacts renders the contacts screen: header (back / title / add),
// search field, and the contact rows (or loading/empty states). The
// add-contact dialog overlays as a centered card.
func (a *App) layoutContacts(gtx layout.Context, f frame) layout.Dimensions {
	if contactsBackBtn.Clicked(gtx) {
		a.closeContacts()
	}
	if contactsAddBtn.Clicked(gtx) {
		a.mu.Lock()
		a.addDlgOpen = true
		a.mu.Unlock()
		a.invalidate()
	}

	// Visible (filtered) rows.
	visible := make([]engine.ContactInfo, 0, len(f.contacts))
	q := contactsSearch.Text()
	for _, c := range f.contacts {
		if contactMatches(c, q) {
			visible = append(visible, c)
		}
	}
	growClickables(&contactsRows, len(visible))

	// Row clicks → open the DM.
	for i, c := range visible {
		i, c := i, c
		if contactsRows[i].Clicked(gtx) {
			if chat, ok := contactChat(f.chats, f.contactsFor, c.UserID); ok {
				a.openChat(chatKey{AccountID: chat.AccountID, ChatID: chat.ChatID}, chat.Title)
			} else {
				a.setToast("No conversation with " + c.DisplayName + " yet")
			}
		}
	}

	return layout.Stack{}.Layout(gtx,
		layout.Stacked(func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.contactsHeader(gtx, f)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.ui.Divider(gtx)
				}),
				// Search field.
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return insetAll(gtx, unit.Dp(8), unit.Dp(12), 6, unit.Dp(12), func(gtx layout.Context) layout.Dimensions {
						return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
							return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								ed := a.ui.Editor(&contactsSearch, "Search contacts")
								return ed.Layout(gtx)
							})
						})
					})
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					return a.contactsBody(gtx, f, visible)
				}),
			)
		}),
		// Add-contact dialog (centered card over a scrim).
		layout.Expanded(func(gtx layout.Context) layout.Dimensions {
			if !f.addDlgOpen {
				return layout.Dimensions{}
			}
			return a.addContactDialog(gtx, f)
		}),
	)
}

func (a *App) contactsHeader(gtx layout.Context, f frame) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(8), Right: unit.Dp(12)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.IconButton(&contactsBackBtn, iconNavigationBack, "Back")
					btn.Color = a.ui.p.TextDim
					return btn.Layout(gtx)
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.H2("Contacts")
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								sub := a.contactsAccountLabel(f)
								if sub == "" {
									return layout.Dimensions{}
								}
								lbl := a.ui.Dim(unit.Sp(12), sub)
								return lbl.Layout(gtx)
							}),
						)
					})
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.IconButton(&contactsAddBtn, iconContentAdd, "Add contact")
					btn.Color = a.ui.p.Accent
					return btn.Layout(gtx)
				}),
			)
		},
	)
}

// contactsAccountLabel: the account scope label under the title.
func (a *App) contactsAccountLabel(f frame) string {
	for _, acc := range f.accounts {
		if acc.ID == f.contactsFor {
			return accountName(acc) + " (" + platformTitle(acc.Platform) + ")"
		}
	}
	return ""
}

func (a *App) contactsBody(gtx layout.Context, f frame, visible []engine.ContactInfo) layout.Dimensions {
	if f.contactsLoad {
		return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(14), "Loading contacts…")
			return lbl.Layout(gtx)
		})
	}
	if len(visible) == 0 {
		return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.H3("No contacts")
					lbl.Color = a.ui.p.TextFaint
					return lbl.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					msg := "People you know appear here."
					if q := strings.TrimSpace(contactsSearch.Text()); q != "" {
						msg = "Nothing matches “" + q + "”."
					}
					lbl := a.ui.Dim(unit.Sp(13), msg)
					lbl.Color = a.ui.p.TextFaint
					return lbl.Layout(gtx)
				}),
			)
		})
	}
	return layout.UniformInset(unit.Dp(4)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return contactsList.Layout(gtx, len(visible), func(gtx layout.Context, idx int) layout.Dimensions {
			return a.contactRow(gtx, visible[idx], &contactsRows[idx])
		})
	})
}

func (a *App) contactRow(gtx layout.Context, c engine.ContactInfo, btn *widget.Clickable) layout.Dimensions {
	name := c.DisplayName
	if name == "" {
		name = contactSubtitle(c)
	}
	dot := dotNone
	if c.IsOnline {
		dot = dotOnline
	}
	return layout.Inset{Left: unit.Dp(8), Right: unit.Dp(8), Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return material.ButtonLayout(a.ui.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return a.b64Avatar(gtx, name, c.AvatarB64, unit.Dp(40), dot)
							})
						}),
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Label(unit.Sp(14), name)
									return lbl.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									sub := contactSubtitle(c)
									lbl := a.ui.Dim(unit.Sp(12), sub)
									return lbl.Layout(gtx)
								}),
							)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							badge := contactBadge(c)
							if badge == "" {
								return layout.Dimensions{}
							}
							lbl := a.ui.Dim(unit.Sp(11), badge)
							if c.IsOnline {
								lbl.Color = a.ui.p.Accent
							}
							return lbl.Layout(gtx)
						}),
					)
				})
			})
		},
	)
}

// addContactDialog: centered card (phone + names) over a scrim.
func (a *App) addContactDialog(gtx layout.Context, f frame) layout.Dimensions {
	if addDlgCancel.Clicked(gtx) {
		a.mu.Lock()
		a.addDlgOpen = false
		a.mu.Unlock()
		a.invalidate()
	}
	if addDlgSave.Clicked(gtx) {
		a.submitAddContact()
	}

	// Scrim behind the card.
	paint.FillShape(gtx.Ops, color.NRGBA{R: 0, G: 0, B: 0, A: 0x66},
		clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Op())

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(340))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.H3("Add contact")
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.addDlgField(gtx, &addPhoneEd, "Phone number")
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.addDlgField(gtx, &addFirstEd, "First name")
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.addDlgField(gtx, &addLastEd, "Last name (optional)")
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.TextButton(&addDlgCancel, "Cancel")
									return btn.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									label := "Add"
									if f.addDlgBusy {
										label = "Adding…"
									}
									btn := a.ui.PrimaryButton(&addDlgSave, label)
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

func (a *App) addDlgField(gtx layout.Context, ed *widget.Editor, hint string) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				e := a.ui.Editor(ed, hint)
				return e.Layout(gtx)
			})
		})
	})
}
