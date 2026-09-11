package gui

// Language settings (slice 140): the Language section in the settings
// rail (tdesktop's position: after Calls). Lists the account's available
// cloud lang-pack languages (engine.GetLanguages over
// langpack.getLanguages for the "tdesktop" pack) with search, official /
// beta / RTL badges; picking one applies it: server-side
// (SetInterfaceLanguage via engine.SetLanguage), client-side (the
// settings-surface strings reloaded through engine.GetLangStrings), and
// persisted (AppConfig.Language). English is the embedded base — missing
// pack keys keep their English labels, exactly how tdesktop falls back.

import (
	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

var (
	langSearchEd widget.Editor
	langRowBtns  []widget.Clickable
	langScroll   widget.List
)

func init() {
	langSearchEd.SingleLine = true
	langScroll.Axis = layout.Vertical
}

// langForAccountID picks the account driving the language surface: the
// active chat's account, else the first telegram-platform account, else
// the first account. Pure over the frame accounts.
func langForAccountID(f frame) string {
	if f.selected != nil {
		return f.selected.AccountID
	}
	for _, acc := range f.accounts {
		if acc.Platform == "telegram" || acc.Platform == "Telegram" {
			return acc.ID
		}
	}
	if len(f.accounts) > 0 {
		return f.accounts[0].ID
	}
	return ""
}

// setPageLanguage renders the Language section: current-language card,
// search field, the language list. Lazy-loads on first entry.
func (a *App) setPageLanguage(gtx layout.Context, f frame) layout.Dimensions {
	acc := langForAccountID(f)
	a.ensureLanguages(acc)

	var children []layout.FlexChild
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, langTr(f.langStrings, "lng_languages", "Language"))
	}))

	// current language card
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			name := languageNameFor(f.langs, f.langCode)
			return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return iconEmojiSmile.Layout(gtx, a.ui.p.Accent)
							})
						}),
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Label(unit.Sp(14), name)
									return lbl.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Dim(unit.Sp(11), "Tap a language below to switch")
									return lbl.Layout(gtx)
								}),
							)
						}),
					)
				})
			})
		})
	}))

	// state rows
	if f.langsFor != "" && !f.langsLoaded && f.langsErr == "" {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.centeredStateLabel(gtx, "Loading…")
		}))
	} else if f.langsErr != "" {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(13), f.langsErr)
			return lbl.Layout(gtx)
		}))
	} else {
		// search field
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				for {
					ev, ok := langSearchEd.Update(gtx)
					if !ok {
						break
					}
					if _, is := ev.(widget.ChangeEvent); is {
						a.invalidate()
					}
				}
				return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return iconActionSearch.Layout(gtx, a.ui.p.TextDim)
								})
							}),
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								ed := a.ui.Editor(&langSearchEd, "Search languages")
								return ed.Layout(gtx)
							}),
						)
					})
				})
			})
		}))

		rows := filterLanguages(f.langs, langSearchEd.Text())
		if len(rows) == 0 {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.centeredStateLabel(gtx, langTr(f.langStrings, "lng_languages_none", "No languages found."))
			}))
		} else {
			growClickables(&langRowBtns, len(rows))
			for i, l := range rows {
				i, l := i, l
				children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.langRow(gtx, f, l, i, acc)
				}))
			}
		}
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// langRow renders one language row; tapping applies the language.
func (a *App) langRow(gtx layout.Context, f frame, l engine.LanguageInfo, i int, acc string) layout.Dimensions {
	active := f.langCode == l.LangCode
	if langRowBtns[i].Clicked(gtx) && !active {
		a.applyLanguage(acc, l.LangCode)
	}
	title, sub := languageRowLabel(l)
	badges := languageBadges(l)
	return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		bg := a.ui.p.Surface
		if active {
			bg = a.ui.p.AccentDim
		}
		// ButtonLayout renders the clickable's event area — a bare
		// roundedFill would leave Clicked() dead (§1.10).
		bl := material.ButtonLayout(a.ui.Theme, &langRowBtns[i])
		bl.Background = bg
		bl.CornerRadius = 10
		return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), title)
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								if sub == "" {
									return layout.Dimensions{}
								}
								lbl := a.ui.Dim(unit.Sp(11), sub)
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								if len(badges) == 0 {
									return layout.Dimensions{}
								}
								return a.badgeChips(gtx, badges)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if active {
							return iconActionDone.Layout(gtx, a.ui.p.Accent)
						}
						return layout.Dimensions{}
					}),
				)
			})
		})
	})
}

// badgeChips renders small badge chips in a row.
func (a *App) badgeChips(gtx layout.Context, badges []string) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, badgeChipChildren(a, badges)...)
	})
}

func badgeChipChildren(a *App, badges []string) []layout.FlexChild {
	var children []layout.FlexChild
	for _, b := range badges {
		b := b
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Right: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return roundedFill(gtx, a.ui.p.SurfaceHi, 8, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(3)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(10), b)
						return lbl.Layout(gtx)
					})
				})
			})
		}))
	}
	return children
}

// ensureLanguages loads the language list once per account scope.
func (a *App) ensureLanguages(accountID string) {
	if accountID == "" {
		return
	}
	a.mu.Lock()
	if a.langsLoaded && a.langsFor == accountID {
		a.mu.Unlock()
		return
	}
	a.langsLoaded = true // in-flight guard
	a.langsFor = accountID
	a.mu.Unlock()
	go func() {
		langs, err := a.eng.GetLanguages(accountID)
		a.mu.Lock()
		if err != nil {
			a.langsLoaded = false // retry on next entry
			a.langsErr = err.Error()
		} else {
			a.langsErr = ""
			a.langs = langs
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// applyLanguage switches the app language: server-side (per-account),
// client-side (settings-surface strings) and persisted. Runs async.
func (a *App) applyLanguage(accountID, code string) {
	if accountID == "" {
		return
	}
	a.mu.Lock()
	a.langCode = code
	a.langApplying = true
	a.mu.Unlock()
	a.invalidate()
	go func() {
		// Server-side pack load for the account (tdesktop semantics).
		srvErr := a.eng.SetLanguage(accountID, code)
		// Client-side: our settings-surface strings. Empty map for en —
		// the embedded baseline IS English.
		override := map[string]string{}
		if code != "" && code != "en" {
			if m, err := a.eng.GetLangStrings(accountID, code, langKeysForSettings()); err == nil {
				override = m
			}
		}
		// Persist the choice (AppConfig.Language).
		cfgErr := a.eng.UpdateConfigFromBridge(&engine.ConfigChanges{Language: code})
		a.mu.Lock()
		a.langStrings = override
		a.langApplying = false
		a.mu.Unlock()
		if srvErr != nil {
			a.setToast("Language: " + srvErr.Error())
		} else if cfgErr != nil {
			a.setToast("Settings: " + cfgErr.Error())
		} else {
			a.setToast("Language set: " + languageNameFor(a.langs, code))
		}
		a.invalidate()
	}()
}
