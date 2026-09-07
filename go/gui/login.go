package gui

import (
	"fmt"
	"image"

	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Login widgets.
var (
	loginInput     widget.Editor
	loginSubmitBtn widget.Clickable
	loginBackBtn   widget.Clickable
	loginCancelBtn widget.Clickable
	platformBtns   []widget.Clickable
	welcomeDemoBtn widget.Clickable
	welcomeAddBtn  widget.Clickable
	pickerCloseBtn widget.Clickable
	authQR         *image.RGBA
	authQRFor      string
)

func init() {
	loginInput.SingleLine = true
}

// layoutWelcome: first-run screen — big title, demo CTA, add-account CTA.
func (a *App) layoutWelcome(gtx layout.Context, f frame) layout.Dimensions {
	if welcomeDemoBtn.Clicked(gtx) {
		a.addAccount("demo")
	}
	if welcomeAddBtn.Clicked(gtx) {
		a.mu.Lock()
		a.showPicker = true
		a.mu.Unlock()
		a.invalidate()
	}

	if f.showPicker {
		return a.layoutPicker(gtx, f, true)
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		maxW := gtx.Dp(unit.Dp(460))
		if gtx.Constraints.Max.X > maxW {
			gtx.Constraints.Max.X = maxW
		}
		return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return a.ui.Avatar(gtx, "Uniclient", unit.Dp(84), dotNone)
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.ui.H1("Uniclient").Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(28)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(15), "One messenger for every network — pure Go, native, yours.")
					return lbl.Layout(gtx)
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Bottom: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.PrimaryButton(&welcomeDemoBtn, "Try the demo")
					btn.CornerRadius = 12
					btn.Inset.Top, btn.Inset.Bottom = 14, 14
					return btn.Layout(gtx)
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.TextButton(&welcomeAddBtn, "Add an account")
				return btn.Layout(gtx)
			}),
		)
	})
}

// layoutLogin: backend picker + auth flow. Used in the content pane while
// f.auth != nil (login in progress) or f.showPicker.
func (a *App) layoutLogin(gtx layout.Context, f frame) layout.Dimensions {
	if pickerCloseBtn.Clicked(gtx) {
		a.mu.Lock()
		a.showPicker = false
		a.mu.Unlock()
		a.invalidate()
	}

	if f.auth != nil {
		return a.layoutAuthFlow(gtx, f)
	}
	return a.layoutPicker(gtx, f, false)
}

// layoutPicker: grid of backend cards with per-backend description.
func (a *App) layoutPicker(gtx layout.Context, f frame, welcome bool) layout.Dimensions {
	for len(platformBtns) < len(platforms) {
		platformBtns = append(platformBtns, widget.Clickable{})
	}
	for i := range platforms {
		if platformBtns[i].Clicked(gtx) {
			a.mu.Lock()
			a.showPicker = false
			a.mu.Unlock()
			a.addAccount(platforms[i].ID)
		}
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		maxW := gtx.Dp(unit.Dp(560))
		if gtx.Constraints.Max.X > maxW {
			gtx.Constraints.Max.X = maxW
		}
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Bottom: unit.Dp(18)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							return a.ui.H2("Add an account").Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							if welcome {
								return layout.Dimensions{}
							}
							btn := a.ui.IconButton(&pickerCloseBtn, iconContentClear, "Close")
							return btn.Layout(gtx)
						}),
					)
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				// 2-column grid of platform cards.
				cols := 2
				if gtx.Constraints.Max.X < gtx.Dp(unit.Dp(480)) {
					cols = 1
				}
				rows := (len(platforms) + cols - 1) / cols
				var rowList widget.List
				rowList.Axis = layout.Vertical
				return material.List(a.ui.Theme, &rowList).Layout(gtx, rows, func(gtx layout.Context, r int) layout.Dimensions {
					return gridRow(gtx, cols, func(col int) layout.Widget {
						i := r*cols + col
						return func(gtx layout.Context) layout.Dimensions {
							if i >= len(platforms) {
								return layout.Dimensions{}
							}
							return layout.UniformInset(unit.Dp(4)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return a.platformCard(gtx, &platformBtns[i], platforms[i])
							})
						}
					})
				})
			}),
		)
	})
}

// gridRow lays out up to cols cells with equal width for a single row.
func gridRow(gtx layout.Context, cols int, cell func(col int) layout.Widget) layout.Dimensions {
	var children []layout.FlexChild
	for c := 0; c < cols; c++ {
		c := c
		children = append(children, layout.Flexed(1, cell(c)))
	}
	return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, children...)
}

// platformCard: one backend card (avatar, title, desc).
func (a *App) platformCard(gtx layout.Context, btn *widget.Clickable, p platformMeta) layout.Dimensions {
	hovered := btn.Hovered()
	bg := a.ui.p.Surface
	if hovered {
		bg = a.ui.p.SurfaceHi
	}
	return roundedFill(gtx, bg, 12, func(gtx layout.Context) layout.Dimensions {
		return material.ButtonLayout(a.ui.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			gtx.Constraints.Min.Y = gtx.Dp(unit.Dp(84))
			return layout.UniformInset(unit.Dp(14)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.ui.Avatar(gtx, p.Title, unit.Dp(44), dotNone)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return a.ui.H3(p.Title).Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(12), p.Desc)
								return lbl.Layout(gtx)
							}),
						)
					}),
				)
			})
		})
	})
}

// layoutAuthFlow: renders the engine auth state machine.
func (a *App) layoutAuthFlow(gtx layout.Context, f frame) layout.Dimensions {
	st := f.auth
	if st == nil {
		return a.layoutPicker(gtx, f, false)
	}

	// editor events
	for {
		ev, ok := loginInput.Update(gtx)
		if !ok {
			break
		}
		if se, isSubmit := ev.(widget.SubmitEvent); isSubmit {
			if txt := se.Text; txt != "" {
				loginInput.SetText("")
				a.submitAuth(txt)
			}
		}
	}
	if loginSubmitBtn.Clicked(gtx) {
		if txt := loginInput.Text(); txt != "" {
			loginInput.SetText("")
			a.submitAuth(txt)
		}
	}
	if loginBackBtn.Clicked(gtx) {
		a.authBack()
	}
	if loginCancelBtn.Clicked(gtx) {
		a.authCancel()
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		maxW := gtx.Dp(unit.Dp(420))
		if gtx.Constraints.Max.X > maxW {
			gtx.Constraints.Max.X = maxW
		}
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			// header: platform + step
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Bottom: unit.Dp(16)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return a.ui.Avatar(gtx, platformTitle(st.Platform), unit.Dp(40), dotNone)
							})
						}),
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return a.ui.H2(platformTitle(st.Platform)).Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Dim(unit.Sp(13), authStepTitle(st))
									return lbl.Layout(gtx)
								}),
							)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							// busy indicator
							if busy := f.connecting[f.authAcct]; busy || st.State == "" {
								ld := material.Loader(a.ui.Theme)
								ld.Color = a.ui.p.Accent
								return ld.Layout(gtx)
							}
							return layout.Dimensions{}
						}),
					)
				})
			}),
			// card with prompt + input / options
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.authCard(gtx, f, st)
			}),
			// nav row
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.TextButton(&loginBackBtn, "Back")
							return btn.Layout(gtx)
						}),
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							return layout.Dimensions{}
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.TextButton(&loginCancelBtn, "Cancel")
							btn.Color = a.ui.p.Error
							return btn.Layout(gtx)
						}),
					)
				})
			}),
		)
	})
}

func authStepTitle(st *engine.AuthState) string {
	switch st.State {
	case engine.AuthStateChoose:
		return "How do you want to log in?"
	case engine.AuthStateInput:
		return st.Label
	case engine.AuthStateOTP:
		if st.SentTo != "" {
			return "Code sent to " + st.SentTo
		}
		return "Enter the login code"
	case engine.AuthState2FA:
		return "Two-factor password"
	case engine.AuthStateQR:
		return "Scan the QR code"
	case engine.AuthStateSignUp:
		return "Create your account"
	case engine.AuthStateEmail:
		return "Enter your email"
	case engine.AuthStateReady:
		return "Logged in as " + st.DisplayName
	case engine.AuthStateError:
		return "Something went wrong"
	}
	return "Logging in…"
}

// authCard: state-driven card body.
func (a *App) authCard(gtx layout.Context, f frame, st *engine.AuthState) layout.Dimensions {
	return roundedFill(gtx, a.ui.p.Surface, 14, func(gtx layout.Context) layout.Dimensions {
		return layout.UniformInset(unit.Dp(18)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			switch st.State {
			case engine.AuthStateChoose:
				return a.authChoose(gtx, f, st)
			case engine.AuthStateReady:
				return a.authReady(gtx, st)
			case engine.AuthStateError:
				return a.authError(gtx, st)
			case engine.AuthStateQR:
				return a.authQRView(gtx, f, st)
			default:
				return a.authInput(gtx, f, st)
			}
		})
	})
}

// authChoose: list of options as buttons.
func (a *App) authChoose(gtx layout.Context, f frame, st *engine.AuthState) layout.Dimensions {
	for len(authOptBtns) < len(st.Options) {
		authOptBtns = append(authOptBtns, widget.Clickable{})
	}
	for i := range st.Options {
		if authOptBtns[i].Clicked(gtx) {
			a.submitAuth(st.Options[i].ID)
		}
	}
	var children []layout.FlexChild
	for i, opt := range st.Options {
		i, opt := i, opt
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.SurfaceButton(&authOptBtns[i], opt.Label)
				btn.CornerRadius = 10
				btn.Inset.Left = 14
				return btn.Layout(gtx)
			})
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

var authOptBtns []widget.Clickable

// authInput: label + editor + submit.
func (a *App) authInput(gtx layout.Context, f frame, st *engine.AuthState) layout.Dimensions {
	// QR refresh animation for Telegram QR.
	if st.State == engine.AuthStateQR {
		gtx.Execute(op.InvalidateCmd{})
	}

	hint := "Enter " + stringsToLower(st.Label)
	if st.Hint != "" {
		hint = st.Hint
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if st.Label == "" && st.Hint == "" {
				return layout.Dimensions{}
			}
			lbl := a.ui.Dim(unit.Sp(13), st.Hint)
			if lbl.Text == "" {
				lbl = a.ui.Dim(unit.Sp(13), st.Label)
			}
			return lbl.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				if st.FieldType == "password" {
					loginInput.Mask = '*'
				} else {
					loginInput.Mask = 0
				}
				return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						gtx.Constraints.Min.Y = gtx.Dp(unit.Dp(40))
						return a.ui.Editor(&loginInput, hint).Layout(gtx)
					})
				})
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			btn := a.ui.PrimaryButton(&loginSubmitBtn, "Continue")
			return btn.Layout(gtx)
		}),
	)
}

// authQRView renders the QR image if available.
func (a *App) authQRView(gtx layout.Context, f frame, st *engine.AuthState) layout.Dimensions {
	// Render QR from st.QRData if not yet rendered for this token.
	if len(st.QRData) > 0 && (authQR == nil || authQRFor != string(st.QRData)) {
		authQR = renderQR(string(st.QRData))
		authQRFor = string(st.QRData)
	}
	if authQR != nil {
		size := gtx.Dp(unit.Dp(220))
		img := widget.Image{Src: paint.NewImageOp(authQR)}
		img.Fit = widget.Fill
		img.Scale = 1.0 / float32(gtx.Metric.PxPerDp) // 1 image pixel = 1 output pixel
		gtx.Constraints.Min = image.Pt(size, size)
		gtx.Constraints.Max = gtx.Constraints.Min
		return layout.Center.Layout(gtx, img.Layout)
	}
	// Fallback: show the raw data as text (selectable).
	lbl := a.ui.Dim(unit.Sp(12), string(st.QRData))
	return lbl.Layout(gtx)
}

// authReady: success state.
func (a *App) authReady(gtx layout.Context, st *engine.AuthState) layout.Dimensions {
	return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Bottom: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return iconActionDone.Layout(gtx, a.ui.p.Online)
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.H3("Welcome, " + st.DisplayName + "!")
			return lbl.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(13), "Connecting and syncing your chats…")
				return lbl.Layout(gtx)
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				ld := material.Loader(a.ui.Theme)
				ld.Color = a.ui.p.Accent
				return ld.Layout(gtx)
			})
		}),
	)
}

// authError: error state with message.
func (a *App) authError(gtx layout.Context, st *engine.AuthState) layout.Dimensions {
	return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return iconActionDelete.Layout(gtx, a.ui.p.Error)
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Label(unit.Sp(14), st.Message)
			lbl.Color = a.ui.p.Error
			return lbl.Layout(gtx)
		}),
	)
}

func stringsToLower(s string) string {
	b := []byte(s)
	for i := range b {
		if b[i] >= 'A' && b[i] <= 'Z' {
			b[i] += 'a' - 'A'
		}
	}
	return string(b)
}

var _ = fmt.Sprintf
