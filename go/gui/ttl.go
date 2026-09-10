package gui

import (
	"image"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Message auto-delete / TTL (AyuGram parity, matrix "Chat menu"):
// the header ⋮ menu gains "Auto-delete…" which opens a small dialog with
// Telegram's period choices (Off / 24 hours / 7 days / 1 month); the
// engine's SetChatTTL persists it server-side and updates the cached
// chat row, and the profile panel shows the active period. Received
// per-message TTL rendering (the countdown) is a later slice.

// ttlChoice is one auto-delete option.
type ttlChoice struct {
	label string
	secs  int
}

var ttlChoices = []ttlChoice{
	{"Off", 0},
	{"24 hours", 24 * 3600},
	{"7 days", 7 * 24 * 3600},
	{"1 month", 30 * 24 * 3600},
}

// ttlLabel renders a TTL period for display (profile rows, toasts).
func ttlLabel(secs int) string {
	switch secs {
	case 0:
		return "Off"
	case 24 * 3600:
		return "24 hours"
	case 7 * 24 * 3600:
		return "7 days"
	case 30 * 24 * 3600:
		return "1 month"
	}
	switch {
	case secs%86400 == 0:
		return itoa(secs/86400) + " days"
	case secs%3600 == 0:
		return itoa(secs/3600) + " hours"
	}
	return itoa(secs) + "s"
}

// ttlDlgState is the open auto-delete dialog.
type ttlDlgState struct {
	accountID string
	chatID    string
	title     string
}

var (
	ttlDlgCancelBtn widget.Clickable
	ttlDlgRowBtns   []widget.Clickable
	ttlDlgKeyTag    = new(struct{})
)

// openTtlDialog opens the auto-delete picker for the open chat.
func (a *App) openTtlDialog(f frame, chat *engine.ChatInfo) {
	if chat == nil {
		return
	}
	a.mu.Lock()
	a.ttlDlg = &ttlDlgState{accountID: chat.AccountID, chatID: chat.ChatID, title: chat.Title}
	a.mu.Unlock()
	a.invalidate()
}

// closeTtlDialog dismisses it.
func (a *App) closeTtlDialog() {
	a.mu.Lock()
	a.ttlDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// applyChatTTL sets the chat's auto-delete period (async + toast).
func (a *App) applyChatTTL(accountID, chatID string, secs int) {
	go func() {
		if err := a.eng.SetChatTTL(accountID, chatID, secs); err != nil {
			a.setToast("Auto-delete failed: " + err.Error())
			return
		}
		a.setToast("Auto-delete: " + ttlLabel(secs))
	}()
}

// layoutTtlDialog renders the period picker (content-pane replacement,
// like the other header dialogs).
func (a *App) layoutTtlDialog(gtx layout.Context, f frame) layout.Dimensions {
	st := f.ttlDlg
	growClickables(&ttlDlgRowBtns, len(ttlChoices))

	// Esc closes (self-handled).
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, ttlDlgKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeTtlDialog()
		}
	}
	if ttlDlgCancelBtn.Clicked(gtx) {
		a.closeTtlDialog()
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(320))
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(300))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.H3("Auto-delete messages")
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(12), "Clears copies of messages in this chat for everyone")
						lbl.Color = a.ui.p.TextFaint
						return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(10)}.Layout(gtx, lbl.Layout)
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						children := make([]layout.FlexChild, 0, len(ttlChoices))
						for i, ch := range ttlChoices {
							i, ch := i, ch
							children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								btn := &ttlDlgRowBtns[i]
								if btn.Clicked(gtx) {
									accountID, chatID, secs := st.accountID, st.chatID, ch.secs
									a.closeTtlDialog()
									a.applyChatTTL(accountID, chatID, secs)
								}
								bl := material.ButtonLayout(a.ui.Theme, btn)
								bl.Background = a.ui.p.SurfaceHi
								bl.CornerRadius = 10
								return layout.Inset{Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
										return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
											lbl := a.ui.Label(unit.Sp(14), ch.label)
											return lbl.Layout(gtx)
										})
									})
								})
							}))
						}
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						bl := material.Button(a.ui.Theme, &ttlDlgCancelBtn, "Cancel")
						bl.Background = a.ui.p.SurfaceHi
						bl.Color = a.ui.p.Text
						bl.CornerRadius = 10
						return bl.Layout(gtx)
					}),
				)
			})
		})
	})
}
