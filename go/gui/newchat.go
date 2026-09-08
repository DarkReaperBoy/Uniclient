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
}

var (
	newDlgCancel widget.Clickable
	newDlgCreate widget.Clickable
	newDlgMega   widget.Bool
	newDlgNameEd widget.Editor
	newDlgDescEd widget.Editor
)

// openNewChat opens the creation dialog for kind on an account.
func (a *App) openNewChat(kind int, accountID string) {
	if accountID == "" {
		a.setToast("Connect an account first")
		return
	}
	a.mu.Lock()
	a.newDlg = &newChatDlg{kind: kind, accountID: accountID}
	a.mu.Unlock()
	newDlgNameEd.SetText("")
	newDlgDescEd.SetText("")
	newDlgMega.Value = false
	a.invalidate()
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
			info, err = a.eng.CreateGroup(d.accountID, name, nil)
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
