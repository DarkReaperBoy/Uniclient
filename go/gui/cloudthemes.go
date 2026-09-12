package gui

import (
	"image"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget/material"

	"uniclient/cores"
)

// Cloud themes (AyuGram parity, matrix "Appearance"): the Appearance page
// gains a "Cloud themes" section listing the account's server-side themes
// (engine.GetCloudThemes — title/slug, creator badge). Tapping asks for
// confirmation, then engine.InstallCloudTheme saves the choice
// server-side (other Telegram clients pick it up) and the theme's accent
// color is applied to this GUI through the standard accent pipeline —
// an honest partial: full .attheme parsing is out of scope here.

// cloudThemeDlgState is the open install-confirmation dialog.
type cloudThemeDlgState struct {
	accountID string
	theme     cores.CloudThemeInfo
}

var (
	cloudThemeDlgKeyTag = new(struct{})
)

// argbToHex converts a Telegram 0xAARRGGBB color to "#RRGGBB" (" " for
// unset/zero).
func argbToHex(argb int) string {
	if argb == 0 {
		return ""
	}
	const hexdigits = "0123456789ABCDEF"
	r := (argb >> 16) & 0xFF
	g := (argb >> 8) & 0xFF
	b := argb & 0xFF
	return string([]byte{
		'#',
		hexdigits[(r>>4)&0xF], hexdigits[r&0xF],
		hexdigits[(g>>4)&0xF], hexdigits[g&0xF],
		hexdigits[(b>>4)&0xF], hexdigits[b&0xF],
	})
}

// loadCloudThemes reads the first account's server-side theme list (once
// per session, slice 66).
func (a *App) loadCloudThemes() {
	a.mu.Lock()
	if a.cloudThemesOn {
		a.mu.Unlock()
		return
	}
	a.mu.Unlock()
	for _, acc := range a.eng.ListAccounts() {
		themes, err := a.eng.GetCloudThemes(acc.ID)
		if err == nil && len(themes) > 0 {
			a.mu.Lock()
			a.cloudThemes, a.cloudThemesFor, a.cloudThemeAcct, a.cloudThemesOn = themes, accountName(acc), acc.ID, true
			a.mu.Unlock()
			a.invalidate()
			return
		}
	}
	a.mu.Lock()
	a.cloudThemesOn = true // none anywhere; don't retry every open
	a.mu.Unlock()
}

// openCloudThemeDialog asks to install one theme (slice 66).
func (a *App) openCloudThemeDialog(accountID string, th cores.CloudThemeInfo) {
	a.mu.Lock()
	a.cloudDlg = &cloudThemeDlgState{accountID: accountID, theme: th}
	a.mu.Unlock()
	a.invalidate()
}

// closeCloudThemeDialog dismisses it.
func (a *App) closeCloudThemeDialog() {
	a.mu.Lock()
	a.cloudDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// applyCloudTheme installs the theme server-side and applies its accent
// color here (slice 66).
func (a *App) applyCloudTheme(accountID string, th cores.CloudThemeInfo) {
	go func() {
		if err := a.eng.InstallCloudTheme(accountID, th.ID, th.IsDark); err != nil {
			a.setToast("Install theme failed: " + err.Error())
			return
		}
		a.setToast("Theme installed: " + th.Title)
	}()
	if hex := argbToHex(th.AccentColor); hex != "" {
		a.applyAccent(hex)
	}
}

// layoutCloudThemeSection renders the Appearance page's cloud-theme rows
// (slice 66).
func (a *App) layoutCloudThemeSection(gtx layout.Context, f frame) layout.Dimensions {
	growClickables(&a.wid.cloudThemeRowBtns, len(f.cloudThemes))
	var children []layout.FlexChild
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Cloud themes")
	}))
	if !f.cloudThemesOn {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.loadingNote(gtx)
		}))
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
	}
	if len(f.cloudThemes) == 0 {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.loadingNote(gtx) // quiet "none" hint, same dim style
		}))
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
	}
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.subHeader(gtx, "From "+f.cloudThemesFor)
	}))
	for i, th := range f.cloudThemes {
		i, th := i, th
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			btn := &a.wid.cloudThemeRowBtns[i]
			if btn.Clicked(gtx) {
				a.openCloudThemeDialog(f.cloudThemeAcct, th)
			}
			bl := material.ButtonLayout(a.ui.Theme, btn)
			bl.Background = a.ui.p.Surface
			bl.CornerRadius = 10
			return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									sz := gtx.Dp(unit.Dp(22))
									gtx.Constraints.Max = image.Pt(sz, sz)
									gtx.Constraints.Min = image.Pt(sz, sz)
									c, ok := parseAccentHex(argbToHex(th.AccentColor))
									if !ok {
										c = a.ui.p.SurfaceHi
									}
									cl := clip.UniformRRect(image.Rectangle{Max: image.Pt(sz, sz)}, 6).Push(gtx.Ops)
									paint.FillShape(gtx.Ops, c, clip.UniformRRect(image.Rectangle{Max: image.Pt(sz, sz)}, 6).Op(gtx.Ops))
									cl.Pop()
									return layout.Dimensions{Size: image.Pt(sz, sz)}
								})
							}),
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										lbl := a.ui.Label(unit.Sp(14), th.Title)
										return lbl.Layout(gtx)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										sub := "t.me/addtheme/" + th.Slug
										if th.IsCreator {
											sub += " · your theme"
										}
										lbl := a.ui.Dim(unit.Sp(11), sub)
										lbl.Color = a.ui.p.TextFaint
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

// layoutCloudThemeDialog renders the install confirmation (content-pane
// replacement, like the other settings dialogs).
func (a *App) layoutCloudThemeDialog(gtx layout.Context, f frame) layout.Dimensions {
	st := f.cloudDlg

	// Esc closes (self-handled).
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, cloudThemeDlgKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeCloudThemeDialog()
		}
	}
	if a.wid.cloudThemeDlgCancelBtn.Clicked(gtx) {
		a.closeCloudThemeDialog()
	}
	if a.wid.cloudThemeDlgInstallBtn.Clicked(gtx) {
		accountID, th := st.accountID, st.theme
		a.closeCloudThemeDialog()
		a.applyCloudTheme(accountID, th)
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(320))
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(240))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.H3("Install theme?")
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(12), "\""+st.theme.Title+"\" installs to your account; its accent color applies here.")
						lbl.Color = a.ui.p.TextFaint
						return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(12)}.Layout(gtx, lbl.Layout)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								bl := material.Button(a.ui.Theme, &a.wid.cloudThemeDlgInstallBtn, "Install")
								bl.Background = a.ui.p.Accent
								bl.Color = rgb(0x0D1821)
								bl.CornerRadius = 10
								return bl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									bl := material.Button(a.ui.Theme, &a.wid.cloudThemeDlgCancelBtn, "Cancel")
									bl.Background = a.ui.p.SurfaceHi
									bl.Color = a.ui.p.Text
									bl.CornerRadius = 10
									return bl.Layout(gtx)
								})
							}),
						)
					}),
				)
			})
		})
	})
}
