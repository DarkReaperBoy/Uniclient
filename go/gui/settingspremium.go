package gui

import (
	"fmt"

	"gioui.org/font"
	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/cores"
	"uniclient/engine"
)

func currencyExponent(cur string) int {
	switch cur {
	case "JPY", "KRW", "VND", "CLP", "DJF", "GNF", "PYG", "UGX":
		return 0
	case "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND":
		return 3
	}
	return 2
}

func formatPremiumPrice(cur string, amount int64) string {
	exp := currencyExponent(cur)
	if exp == 0 {
		return fmt.Sprintf("%d %s", amount, cur)
	}
	div := int64(1)
	for i := 0; i < exp; i++ {
		div *= 10
	}
	whole := amount / div
	frac := amount % div
	if frac == 0 {
		return fmt.Sprintf("%d %s", whole, cur)
	}
	return fmt.Sprintf("%d.%0*d %s", whole, exp, frac, cur)
}

func premiumPlanLabel(months int) string {
	if months == 1 {
		return "1 month"
	}
	return itoa(months) + " months"
}

func premiumPlanSubtitle(p cores.PremiumPlanOption) string {
	return formatPremiumPrice(p.Currency, p.Amount)
}

type premiumLimitRow struct {
	label   string
	free    int
	premium int
}

func premiumLimitRows(limits map[string]int) []premiumLimitRow {
	return []premiumLimitRow{
		{"Chat folders", limits["free_limit"], limits["premium_limit"]},
		{"Chats per folder", limits["chats_per_folder_free"], limits["chats_per_folder_premium"]},
		{"Shared folders", limits["shared_folders_free"], limits["shared_folders_premium"]},
		{"Links per folder", limits["links_per_folder_free"], limits["links_per_folder_premium"]},
	}
}

type premiumPageState struct {
	accountID string
	loading   bool
	loaded    bool
	err       string

	promo  *cores.PremiumPromo
	limits map[string]int
}

var (
	premiumOpenBtn  widget.Clickable
	premiumBackBtn  widget.Clickable
	premiumReloadBt widget.Clickable
	premiumSubBtns  []widget.Clickable
	premiumAcctBtns []widget.Clickable

	noAdsRevert map[string]bool
)

func (a *App) updatePremiumPage(fn func(st *premiumPageState) bool) *premiumPageState {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.premiumPage == nil {
		return nil
	}
	next := *a.premiumPage
	if !fn(&next) {
		return nil
	}
	a.premiumPage = &next
	return &next
}

func (a *App) openPremiumPage(accountID string) {
	a.mu.Lock()
	a.premiumPage = &premiumPageState{accountID: accountID, loading: true}
	a.profileEdit = nil
	a.stickerMgr = nil
	a.folderMgr = nil
	a.businessPage = nil
	a.starsPage = nil
	a.mu.Unlock()
	go a.loadPremiumPage(accountID)
	a.invalidate()
}

func (a *App) closePremiumPage() {
	a.mu.Lock()
	a.premiumPage = nil
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) loadPremiumPage(accountID string) {
	promo, errP := a.eng.GetPremiumPromo(accountID)
	limits, errL := a.eng.GetAllFolderLimits(accountID)
	a.updatePremiumPage(func(n *premiumPageState) bool {
		if n.accountID != accountID {
			return false
		}
		n.loading = false
		if errP != nil {
			n.err = errP.Error()
		} else {
			n.err = ""
			n.loaded = true
			n.promo = promo
		}
		if errL == nil && limits != nil {
			n.limits = limits
		}
		return true
	})
	a.invalidate()
}

func (a *App) reloadPremiumPage() {
	acc := ""
	a.updatePremiumPage(func(n *premiumPageState) bool {
		acc = n.accountID
		n.loading = true
		return true
	})
	if acc != "" {
		go a.loadPremiumPage(acc)
	}
}

func (a *App) openPremiumSubscribe(p cores.PremiumPlanOption) {
	if p.BotURL == "" {
		a.setToast("No payment link for this plan")
		return
	}
	go a.openLinkExternal(p.BotURL)
}

func (a *App) layoutPremiumPage(gtx layout.Context, f frame) layout.Dimensions {
	st := f.premiumPage
	if st == nil {
		return layout.Dimensions{}
	}
	if premiumBackBtn.Clicked(gtx) {
		a.closePremiumPage()
	}
	if premiumReloadBt.Clicked(gtx) {
		a.reloadPremiumPage()
	}

	var children []layout.FlexChild

	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.IconButton(&premiumBackBtn, iconNavigationBack, "Back")
					return btn.Layout(gtx)
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(17), "Telegram Premium")
					lbl.Font.Weight = font.SemiBold
					return lbl.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.IconButton(&premiumReloadBt, iconActionSchedule, "Reload")
					return btn.Layout(gtx)
				}),
			)
		})
	}))

	if len(f.accounts) > 1 {
		growClickables(&premiumAcctBtns, len(f.accounts))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, a.premiumAcctChips(gtx, f, st)...)
			})
		}))
	}

	if st.loading && !st.loaded {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.loadingNote(gtx)
		}))
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
	}
	if st.err != "" {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(13), st.err)
			return lbl.Layout(gtx)
		}))
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
	}

	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.premiumStatusCard(gtx, f, st)
	}))

	if serverPremium(f, st.accountID) {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.premiumNoAdsRow(gtx, st)
		}))
	}

	if st.promo != nil {
		growClickables(&premiumSubBtns, len(st.promo.Options))
		for i, p := range st.promo.Options {
			i, p := i, p
			if premiumSubBtns[i].Clicked(gtx) {
				a.openPremiumSubscribe(p)
			}
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.premiumPlanRow(gtx, p, &premiumSubBtns[i])
			}))
		}
	}

	if st.limits != nil {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.subHeader(gtx, "Limits with Premium")
		}))
		for _, row := range premiumLimitRows(st.limits) {
			row := row
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.premiumLimitRowLayout(gtx, row)
			}))
		}
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func (a *App) premiumStatusCard(gtx layout.Context, f frame, st *premiumPageState) layout.Dimensions {
	premium := false
	for _, acc := range f.accounts {
		if acc.ID == st.accountID {
			premium = acc.IsPremium
			break
		}
	}
	localOn := f.cfg.LocalPremium[st.accountID]
	if localOn {
		premium = true
	}
	localPremBtn := settingsSwitch("local_premium:" + st.accountID)
	if !settingsSynced["local_premium:"+st.accountID] {
		localPremBtn.Value = localOn
		settingsSynced["local_premium:"+st.accountID] = true
	}
	localPremPrev := localPremBtn.Value
	dims := layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(12)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return iconToggleStar.Layout(gtx, a.ui.p.Accent)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						lines := []layout.FlexChild{
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), "Subscription")
								return lbl.Layout(gtx)
							}),
						}
						if premium {
							state := "Active on this account"
							if localOn {
								state = "Active locally (Ayu) — server perks need a subscription"
							}
							lines = append(lines, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), state)
								lbl.Color = a.ui.p.Accent
								return lbl.Layout(gtx)
							}))
						} else if st.promo != nil && st.promo.StatusText != "" {
							lines = append(lines, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), st.promo.StatusText)
								return lbl.Layout(gtx)
							}))
						}
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx, lines...)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if !premium {
							return layout.Dimensions{}
						}
						badge := "Active"
						if localOn {
							badge = "Active (local)"
						}
						return roundedFill(gtx, a.ui.p.AccentDim, 10, func(gtx layout.Context) layout.Dimensions {
							return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(12), badge)
								lbl.Color = a.ui.p.Accent
								return lbl.Layout(gtx)
							})
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							b := material.Switch(a.ui.Theme, localPremBtn, "Local premium")
							b.Color.Enabled = a.ui.p.Accent
							return b.Layout(gtx)
						})
					}),
				)
			})
		})
	})
	if localPremBtn.Value != localPremPrev {
		go func() {
			if err := a.eng.SetLocalPremium(st.accountID, localPremBtn.Value); err != nil {
				a.setToast("Local premium: " + err.Error())
				return
			}
			a.refreshConfig()
			a.refreshAccounts()
		}()
	}
	return dims
}

func (a *App) premiumPlanRow(gtx layout.Context, p cores.PremiumPlanOption, btn *widget.Clickable) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), premiumPlanLabel(p.Months))
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), premiumPlanSubtitle(p))
								return lbl.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if p.Current {
							return roundedFill(gtx, a.ui.p.AccentDim, 10, func(gtx layout.Context) layout.Dimensions {
								return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Label(unit.Sp(12), "Current")
									lbl.Color = a.ui.p.Accent
									return lbl.Layout(gtx)
								})
							})
						}
						b := a.ui.SurfaceButton(btn, "Subscribe")
						return b.Layout(gtx)
					}),
				)
			})
		})
	})
}

func (a *App) premiumLimitRowLayout(gtx layout.Context, row premiumLimitRow) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(14), row.label)
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(13), itoa(row.free))
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(6), Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(13), "→")
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(13), itoa(row.premium))
						lbl.Color = a.ui.p.Accent
						return lbl.Layout(gtx)
					}),
				)
			})
		})
	})
}

func (a *App) premiumAcctChips(gtx layout.Context, f frame, st *premiumPageState) []layout.FlexChild {
	var children []layout.FlexChild
	for i, acc := range f.accounts {
		i, acc := i, acc
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if premiumAcctBtns[i].Clicked(gtx) && acc.ID != st.accountID {
				a.openPremiumPage(acc.ID)
			}
			active := acc.ID == st.accountID
			bg := a.ui.p.SurfaceHi
			txtCol := a.ui.p.TextDim
			if active {
				bg = a.ui.p.AccentDim
				txtCol = a.ui.p.Accent
			}
			return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				bl := material.ButtonLayout(a.ui.Theme, &premiumAcctBtns[i])
				bl.Background = bg
				bl.CornerRadius = 14
				return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(12), accountName(acc))
						lbl.Color = txtCol
						return lbl.Layout(gtx)
					})
				})
			})
		}))
	}
	return children
}

func (a *App) premiumEntryRow(gtx layout.Context, f frame) layout.Dimensions {
	if premiumOpenBtn.Clicked(gtx) {
		a.openPremiumPage(mgrAccountID(f))
	}
	return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return iconToggleStar.Layout(gtx, a.ui.p.Accent)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), "Telegram Premium")
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), "Subscription, plans, limits")
								return lbl.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return iconNavChevronRight.Layout(gtx, a.ui.p.TextDim)
					}),
				)
			})
		})
	})
}

func premiumEntryVisible(accounts []engine.AccountInfo) bool {
	for _, acc := range accounts {
		if acc.Platform == "telegram" || acc.Platform == "Telegram" {
			return true
		}
	}
	return false
}

func serverPremium(f frame, accountID string) bool {
	for _, acc := range f.accounts {
		if acc.ID == accountID {
			return acc.IsPremium
		}
	}
	return false
}

func (a *App) premiumNoAdsRow(gtx layout.Context, st *premiumPageState) layout.Dimensions {
	key := "no_ads:" + st.accountID
	sw := settingsSwitch(key)
	a.mu.Lock()
	if noAdsRevert[key] {
		delete(noAdsRevert, key)
		sw.Value = true
	}
	a.mu.Unlock()
	if !settingsSynced[key] {
		sw.Value = true
		settingsSynced[key] = true
	}
	prev := sw.Value
	dims := layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(12)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return iconToggleStar.Layout(gtx, a.ui.p.Accent)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), "Sponsored messages")
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), "Premium perk — turn off to hide ads in channels and bots")
								lbl.Color = a.ui.p.TextDim
								return lbl.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						tg := material.Switch(a.ui.Theme, sw, "")
						tg.Color.Enabled = a.ui.p.Accent
						tg.Color.Disabled = a.ui.p.SurfaceHi
						tg.Color.Track = a.ui.p.SurfaceHi
						return tg.Layout(gtx)
					}),
				)
			})
		})
	})
	if sw.Value != prev {
		enabled := sw.Value
		acc := st.accountID
		go func() {
			if err := a.eng.ToggleSponsoredMessages(acc, enabled); err != nil {
				a.setToast("Sponsored messages: " + err.Error())
				a.mu.Lock()
				if noAdsRevert == nil {
					noAdsRevert = map[string]bool{}
				}
				noAdsRevert[key] = true
				a.mu.Unlock()
				a.invalidate()
				return
			}
			state := "shown"
			if !enabled {
				state = "hidden"
			}
			a.setToast("Sponsored messages " + state + " for this account")
		}()
	}
	return dims
}
