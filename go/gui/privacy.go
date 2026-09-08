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

// Privacy scope editor (AyuGram parity, matrix "Privacy & security"):
// the Privacy & Security settings page gains a "Privacy" block listing
// AyuGram's rows (last seen, phone number, profile photo, calls, P2P,
// forwards, group invites, voice messages, bio, birthday) with the live
// server-side scope as the row value. Tapping a row opens this small
// picker (modeled on the auto-delete dialog) offering Everybody / My
// contacts / Close friends (where supported) / Nobody; the engine's
// SetPrivacyScope persists it server-side. Per-user exceptions
// ("always allow" / "never allow" lists) are a later slice.

// privacyKeyLabels are the display rows, in AyuGram order.
var privacyKeyLabels = []struct {
	key   string
	label string
}{
	{"last_seen", "Last seen & online"},
	{"phone_number", "Phone number"},
	{"profile_photo", "Profile photo"},
	{"calls", "Who can call me"},
	{"p2p", "P2P calls"},
	{"forwards", "Forwarded messages"},
	{"group_invites", "Groups & channels"},
	{"voice_messages", "Voice messages"},
	{"about", "Bio"},
	{"birthday", "Birthday"},
}

// privacyScopeLabel renders a scope for display (row values, toasts).
func privacyScopeLabel(scope string) string {
	switch scope {
	case "everybody":
		return "Everybody"
	case "contacts":
		return "My contacts"
	case "close_friends":
		return "Close friends"
	case "nobody":
		return "Nobody"
	}
	return "—"
}

// privacyScopeChoices is the picker's option list for one key.
func privacyScopeChoices(key string) []string {
	choices := []string{"everybody", "contacts"}
	if engine.PrivacyScopeCloseFriends(key) {
		choices = append(choices, "close_friends")
	}
	return append(choices, "nobody")
}

// privacyDlgState is the open scope picker.
type privacyDlgState struct {
	accountID string
	key       string
}

var (
	privacyDlgCancelBtn widget.Clickable
	privacyDlgRowBtns   []widget.Clickable
	privacyDlgKeyTag    = new(struct{})
)

// openPrivacyDialog opens the scope picker for one privacy key.
func (a *App) openPrivacyDialog(accountID, key string) {
	a.mu.Lock()
	a.privacyDlg = &privacyDlgState{accountID: accountID, key: key}
	a.mu.Unlock()
	a.invalidate()
}

// closePrivacyDialog dismisses it.
func (a *App) closePrivacyDialog() {
	a.mu.Lock()
	a.privacyDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// applyPrivacyScope persists the chosen scope (async + toast) and refreshes
// the cached scopes for the row.
func (a *App) applyPrivacyScope(accountID, key, scope string) {
	go func() {
		if err := a.eng.SetPrivacyScope(accountID, key, scope); err != nil {
			a.setToast("Privacy: " + err.Error())
			return
		}
		a.setToast(privacyKeyTitle(key) + ": " + privacyScopeLabel(scope))
		a.mu.Lock()
		if a.privacyScopes[accountID] == nil {
			a.privacyScopes[accountID] = map[string]string{}
		}
		a.privacyScopes[accountID][key] = scope
		a.mu.Unlock()
		a.invalidate()
	}()
}

// privacyKeyTitle resolves a key's row label for toasts.
func privacyKeyTitle(key string) string {
	for _, r := range privacyKeyLabels {
		if r.key == key {
			return r.label
		}
	}
	return key
}

// layoutPrivacyScopeDialog renders the scope picker (content-pane
// replacement, like the other settings/header dialogs).
func (a *App) layoutPrivacyScopeDialog(gtx layout.Context, f frame) layout.Dimensions {
	st := f.privacyDlg
	choices := privacyScopeChoices(st.key)
	growClickables(&privacyDlgRowBtns, len(choices))

	// Esc closes (self-handled).
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, privacyDlgKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closePrivacyDialog()
		}
	}
	if privacyDlgCancelBtn.Clicked(gtx) {
		a.closePrivacyDialog()
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(320))
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(340))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.H3(privacyKeyTitle(st.key))
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(12), "Who can see this")
						lbl.Color = a.ui.p.TextFaint
						return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(10)}.Layout(gtx, lbl.Layout)
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						children := make([]layout.FlexChild, 0, len(choices))
						for i, scope := range choices {
							i, scope := i, scope
							children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								btn := &privacyDlgRowBtns[i]
								if btn.Clicked(gtx) {
									accountID, key := st.accountID, st.key
									a.closePrivacyDialog()
									a.applyPrivacyScope(accountID, key, scope)
								}
								bl := material.ButtonLayout(a.ui.Theme, btn)
								bl.Background = a.ui.p.SurfaceHi
								bl.CornerRadius = 10
								return layout.Inset{Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
										return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
											lbl := a.ui.Label(unit.Sp(14), privacyScopeLabel(scope))
											return lbl.Layout(gtx)
										})
									})
								})
							}))
						}
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						bl := material.Button(a.ui.Theme, &privacyDlgCancelBtn, "Cancel")
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
