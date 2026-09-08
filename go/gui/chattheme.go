package gui

import (
	"image"
	"image/color"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/cores"
	"uniclient/engine"
)

// Per-chat themes (AyuGram parity, matrix "Chat background"): the DM
// header ⋮ menu gains "Change colors…" which opens this picker. It lists
// the account's server-side chat themes (engine.GetChatThemes — emoticon
// + gradient colors) as large emoticon chips plus a "Reset" option;
// picking one calls engine.SetChatTheme so both parties see the theme in
// the real clients, and a toast confirms. The in-app bubble re-tint that
// follows is a later slice (the server state changes immediately).

// chatThemeDlgState is the open per-chat theme picker.
type chatThemeDlgState struct {
	accountID string
	chatID    string
	title     string
}

var (
	chatThemeDlgCancelBtn widget.Clickable
	chatThemeResetBtn     widget.Clickable
	chatThemeChipBtns     []widget.Clickable
	chatThemeDlgKeyTag    = new(struct{})
)

// openChatThemeDialog opens the picker and loads the account's themes.
func (a *App) openChatThemeDialog(c engine.ChatInfo) {
	a.mu.Lock()
	a.themeDlg = &chatThemeDlgState{accountID: c.AccountID, chatID: c.ChatID, title: c.Title}
	a.chatThemes, a.chatThemesFor, a.chatThemesOn = nil, "", false
	a.mu.Unlock()
	go a.loadChatThemes(c.AccountID)
	a.invalidate()
}

// loadChatThemes fetches the account's chat themes (async).
func (a *App) loadChatThemes(accountID string) {
	themes, err := a.eng.GetChatThemes(accountID)
	if err != nil {
		themes = nil
	}
	a.mu.Lock()
	if a.themeDlg != nil && a.themeDlg.accountID == accountID {
		a.chatThemes, a.chatThemesOn = themes, true
	}
	a.mu.Unlock()
	a.invalidate()
}

// closeChatThemeDialog dismisses it.
func (a *App) closeChatThemeDialog() {
	a.mu.Lock()
	a.themeDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// applyChatTheme sets the chat's theme emoticon ("" resets, slice 65).
func (a *App) applyChatTheme(accountID, chatID, emoticon, title string) {
	go func() {
		if err := a.eng.SetChatTheme(accountID, chatID, emoticon); err != nil {
			a.setToast("Change colors failed: " + err.Error())
			return
		}
		if emoticon == "" {
			a.setToast("Chat colors reset in " + title)
		} else {
			a.setToast("Chat colors " + emoticon + " in " + title)
		}
	}()
}

// chatThemeSwatch picks a surface color for a theme chip: the theme's
// first message color (Telegram 0xAARRGGBB ints) when present, else the
// fallback surface.
func chatThemeSwatch(th cores.ChatThemeInfo, fallback color.NRGBA) color.NRGBA {
	if len(th.MessageColors) == 0 {
		return fallback
	}
	argb := th.MessageColors[0]
	return color.NRGBA{
		R: uint8((argb >> 16) & 0xFF),
		G: uint8((argb >> 8) & 0xFF),
		B: uint8(argb & 0xFF),
		A: 255,
	}
}

// layoutChatThemeDialog renders the per-chat theme picker (content-pane
// replacement, like the other header dialogs).
func (a *App) layoutChatThemeDialog(gtx layout.Context, f frame) layout.Dimensions {
	st := f.themeDlg
	themes := f.chatThemes
	if f.chatThemesFor != st.accountID {
		themes = nil
	}
	growClickables(&chatThemeChipBtns, len(themes))

	// Esc closes (self-handled).
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, chatThemeDlgKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeChatThemeDialog()
		}
	}
	if chatThemeDlgCancelBtn.Clicked(gtx) {
		a.closeChatThemeDialog()
	}
	if chatThemeResetBtn.Clicked(gtx) {
		accountID, chatID, title := st.accountID, st.chatID, st.title
		a.closeChatThemeDialog()
		a.applyChatTheme(accountID, chatID, "", title)
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(340))
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(360))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.H3("Change colors")
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(12), "Applies to "+st.title+" for both sides")
						lbl.Color = a.ui.p.TextFaint
						return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(10)}.Layout(gtx, lbl.Layout)
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						if !f.chatThemesOn {
							return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(13), "Loading themes…")
								lbl.Color = a.ui.p.TextFaint
								return lbl.Layout(gtx)
							})
						}
						if len(themes) == 0 {
							return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(13), "No chat themes available for this account")
								lbl.Color = a.ui.p.TextFaint
								return lbl.Layout(gtx)
							})
						}
						// Wrap chips into rows of four.
						perRow := 4
						rows := (len(themes) + perRow - 1) / perRow
						var rowChildren []layout.FlexChild
						for r := 0; r < rows; r++ {
							r := r
							rowChildren = append(rowChildren, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								var cells []layout.FlexChild
								for i := r * perRow; i < (r+1)*perRow && i < len(themes); i++ {
									i := i
									th := themes[i]
									cells = append(cells, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										btn := &chatThemeChipBtns[i]
										if btn.Clicked(gtx) {
											accountID, chatID, emoticon, title := st.accountID, st.chatID, th.Emoticon, st.title
											a.closeChatThemeDialog()
											a.applyChatTheme(accountID, chatID, emoticon, title)
										}
										return a.layoutChatThemeChip(gtx, btn, th)
									}))
								}
								return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, cells...)
								})
							}))
						}
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rowChildren...)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								bl := material.Button(a.ui.Theme, &chatThemeResetBtn, "Reset")
								bl.Background = a.ui.p.SurfaceHi
								bl.Color = a.ui.p.Text
								bl.CornerRadius = 10
								return bl.Layout(gtx)
							}),
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								return layout.Dimensions{}
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								bl := material.Button(a.ui.Theme, &chatThemeDlgCancelBtn, "Cancel")
								bl.Background = a.ui.p.SurfaceHi
								bl.Color = a.ui.p.Text
								bl.CornerRadius = 10
								return bl.Layout(gtx)
							}),
						)
					}),
				)
			})
		})
	})
}

// layoutChatThemeChip renders one theme: a large emoticon over a
// gradient-ish surface built from the theme's message colors.
func (a *App) layoutChatThemeChip(gtx layout.Context, btn *widget.Clickable, th cores.ChatThemeInfo) layout.Dimensions {
	sz := gtx.Dp(unit.Dp(56))
	gtx.Constraints.Max = image.Pt(sz, sz)
	gtx.Constraints.Min = image.Pt(sz, sz)
	bl := material.ButtonLayout(a.ui.Theme, btn)
	bl.Background = chatThemeSwatch(th, a.ui.p.SurfaceHi)
	bl.CornerRadius = 14
	return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(24), th.Emoticon)
				return lbl.Layout(gtx)
			})
		})
	})
}
