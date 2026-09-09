package gui

// Ayu shadow ban (matrix row 240, slice 91): per-chat local ignore list.
// The message context menu gains "Shadow-ban sender" / "Unshadow-ban
// sender"; the header ⋮ menu gains "Shadow-banned users…" — a dialog
// listing this chat's bans with per-row Unban. Banned senders' messages
// are hidden locally only (engine shadow_bans table, GetMessages SQL
// exclusion); nothing is deleted server-side and the sender is never
// told.

import (
	"image"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget"

	"uniclient/engine"
)

// shadowDlgState is the open shadow-ban manager (nil when closed).
type shadowDlgState struct {
	chat   chatKey
	bans   []engine.ShadowBan
	loaded bool
}

var (
	shadowDlgClose  widget.Clickable
	shadowDlgUnban  []widget.Clickable // per-row unban buttons
	shadowDlgKeyTag = new(struct{})
)

// openShadowDialog opens the manager for a chat and loads its bans.
func (a *App) openShadowDialog(k chatKey) {
	a.mu.Lock()
	a.shadowDlg = &shadowDlgState{chat: k}
	a.mu.Unlock()
	a.reloadShadowBans(k)
	a.invalidate()
}

// closeShadowDialog dismisses the manager.
func (a *App) closeShadowDialog() {
	a.mu.Lock()
	a.shadowDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// reloadShadowBans re-reads the ban list (after a mutation).
func (a *App) reloadShadowBans(k chatKey) {
	go func() {
		bans := a.eng.ListShadowBans(k.AccountID, k.ChatID)
		a.mu.Lock()
		if a.shadowDlg != nil && a.shadowDlg.chat == k {
			a.shadowDlg.bans = bans
			a.shadowDlg.loaded = true
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// toggleShadowBan (un)bans the message's sender and refreshes the chat.
func (a *App) toggleShadowBan(m engine.CachedMessage, ban bool) {
	go func() {
		if err := a.eng.ShadowBanSender(m.AccountID, m.ChatID, m.SenderID, m.SenderName, ban); err != nil {
			a.setToast("Shadow ban: " + err.Error())
			return
		}
		go a.refreshMessages()
		a.mu.Lock()
		k := a.msgFor
		a.mu.Unlock()
		if k != nil {
			a.reloadShadowBans(*k)
		}
		if ban {
			a.setToast("Sender shadow-banned in this chat")
		} else {
			a.setToast("Sender unshadow-banned")
		}
	}()
}

// shadowBanRowName (pure, testable): display name for one ban row.
func shadowBanRowName(b engine.ShadowBan) string {
	if b.SenderName != "" {
		return b.SenderName
	}
	if b.SenderID != "" {
		return "user " + b.SenderID
	}
	return "someone"
}

// shadowBanMenuGate (pure): when the context menu offers the shadow-ban
// action — a foreign sender row with the ban state resolved (nil state
// hides the item until openMenu's lookup lands).
func shadowBanMenuGate(m engine.CachedMessage, stateKnown bool) bool {
	return m.SenderID != "" && !m.IsOutgoing && !m.IsService && stateKnown
}

// layoutShadowDialog renders the per-chat ban manager (chat-view overlay,
// like the reactors dialog).
func (a *App) layoutShadowDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.shadowDlg
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, shadowDlgKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeShadowDialog()
		}
	}
	if shadowDlgClose.Clicked(gtx) {
		a.closeShadowDialog()
	}
	growClickables(&shadowDlgUnban, len(d.bans))
	for i := range shadowDlgUnban {
		if shadowDlgUnban[i].Clicked(gtx) && i < len(d.bans) {
			ban := d.bans[i]
			k := d.chat
			go func() {
				if err := a.eng.ShadowBanSender(k.AccountID, k.ChatID, ban.SenderID, ban.SenderName, false); err != nil {
					a.setToast("Unban failed: " + err.Error())
					return
				}
				go a.refreshMessages()
				a.reloadShadowBans(k)
			}()
		}
	}

	paintScrimRect(gtx)

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(340))
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(420))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(14)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.H3("Shadow-banned users")
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								btn := a.ui.IconButton(&shadowDlgClose, iconContentClear, "Close")
								btn.Color = a.ui.p.TextDim
								return btn.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(12), "Their messages are hidden in this chat only — locally, never server-side.")
							lbl.Color = a.ui.p.TextFaint
							return lbl.Layout(gtx)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						if !d.loaded {
							return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return a.loadingNote(gtx)
							})
						}
						if len(d.bans) == 0 {
							return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(13), "Nobody is shadow-banned here")
								lbl.Color = a.ui.p.TextFaint
								return lbl.Layout(gtx)
							})
						}
						rows := make([]layout.FlexChild, 0, len(d.bans))
						for i, b := range d.bans {
							rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return a.shadowBanRow(gtx, b, &shadowDlgUnban[i])
							}))
						}
						return layout.Flex{Axis: layout.Vertical, Spacing: layout.Spacing(4)}.Layout(gtx, rows...)
					}),
				)
			})
		})
	})
}

// shadowBanRow: name + Unban.
func (a *App) shadowBanRow(gtx layout.Context, b engine.ShadowBan, unban *widget.Clickable) layout.Dimensions {
	return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
		return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(13), shadowBanRowName(b))
					lbl.MaxLines = 1
					return lbl.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					bl := a.ui.TextButton(unban, "Unban")
					bl.Color = a.ui.p.Accent
					return bl.Layout(gtx)
				}),
			)
		})
	})
}
