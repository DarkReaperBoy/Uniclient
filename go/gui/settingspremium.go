package gui

// settingspremium.go — slice 143: the Telegram Premium settings page
// (tdesktop's Premium box). Subscription status (the server's own
// sentence from help.getPremiumPromo + the account's premium badge),
// the purchasable plans with Subscribe through the payment deep link,
// and the free-vs-premium limits comparison. Everything is
// engine-backed; cores without premium support hide the section
// honestly (§1.10).

import (
        "fmt"

        "gioui.org/font"
        "gioui.org/layout"
        "gioui.org/unit"
        "gioui.org/widget"

        "uniclient/cores"
        "uniclient/engine"
)

// ── pure helpers (unit-tested) ─────────────────────────────────────────────

// currencyExponent returns the number of smallest-unit digits for an
// ISO 4217 code (the Telegram currencies table): 2 for the vast
// majority, 0 for the zero-decimal currencies, 3 for the triple ones.
// Unknown codes take the majority rule. Pure.
func currencyExponent(cur string) int {
        switch cur {
        case "JPY", "KRW", "VND", "CLP", "DJF", "GNF", "PYG", "UGX":
                return 0
        case "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND":
                return 3
        }
        return 2
}

// formatPremiumPrice renders a wire amount (smallest units) as a human
// price with the currency code — whole units without decimals, fractional
// amounts with the currency's full decimal count (2 for USD/EUR, 3 for
// BHD, none for JPY). Pure.
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

// premiumPlanLabel: the plan row's duration label. Pure.
func premiumPlanLabel(months int) string {
        if months == 1 {
                return "1 month"
        }
        return itoa(months) + " months"
}

// premiumPlanSubtitle: the plan row's price line. Pure.
func premiumPlanSubtitle(p cores.PremiumPlanOption) string {
        return formatPremiumPrice(p.Currency, p.Amount)
}

// premiumLimitRow is one free-vs-premium limits comparison row.
type premiumLimitRow struct {
        label   string
        free    int
        premium int
}

// premiumLimitRows builds the limits comparison from the engine's
// folder-limits map — known keys in a fixed display order, unknown keys
// skipped, missing keys zero-valued. Pure.
func premiumLimitRows(limits map[string]int) []premiumLimitRow {
        return []premiumLimitRow{
                {"Chat folders", limits["free_limit"], limits["premium_limit"]},
                {"Chats per folder", limits["chats_per_folder_free"], limits["chats_per_folder_premium"]},
                {"Shared folders", limits["shared_folders_free"], limits["shared_folders_premium"]},
                {"Links per folder", limits["links_per_folder_free"], limits["links_per_folder_premium"]},
        }
}

// ── state ──────────────────────────────────────────────────────────────────

// premiumPageState is the open Premium sub-page.
type premiumPageState struct {
        accountID string
        loading   bool
        loaded    bool
        err       string

        promo  *cores.PremiumPromo
        limits map[string]int
}

var (
        premiumOpenBtn  widget.Clickable // Settings → Main entry card
        premiumBackBtn  widget.Clickable
        premiumReloadBt widget.Clickable
        premiumSubBtns  []widget.Clickable // plan subscribe buttons
        premiumAcctBtns []widget.Clickable
)

// openPremiumPage starts the page for an account and loads its data.
func (a *App) openPremiumPage(accountID string) {
        a.mu.Lock()
        a.premiumPage = &premiumPageState{accountID: accountID, loading: true}
        a.profileEdit = nil // one sub-page at a time (settings shell)
        a.stickerMgr = nil
        a.folderMgr = nil
        a.mu.Unlock()
        go a.loadPremiumPage(accountID)
        a.invalidate()
}

// closePremiumPage dismisses the page.
func (a *App) closePremiumPage() {
        a.mu.Lock()
        a.premiumPage = nil
        a.mu.Unlock()
        a.invalidate()
}

// loadPremiumPage fetches the promo + limits.
func (a *App) loadPremiumPage(accountID string) {
        promo, errP := a.eng.GetPremiumPromo(accountID)
        limits, errL := a.eng.GetAllFolderLimits(accountID)
        a.mu.Lock()
        st := a.premiumPage
        if st == nil || st.accountID != accountID {
                a.mu.Unlock()
                return
        }
        st.loading = false
        if errP != nil {
                st.err = errP.Error()
        } else {
                st.err = ""
                st.loaded = true
                st.promo = promo
        }
        if errL == nil && limits != nil {
                st.limits = limits
        }
        a.mu.Unlock()
        a.invalidate()
}

// reloadPremiumPage re-pulls after a mutation or manual reload.
func (a *App) reloadPremiumPage() {
        a.mu.Lock()
        acc := ""
        if st := a.premiumPage; st != nil {
                acc = st.accountID
                st.loading = true
        }
        a.mu.Unlock()
        if acc != "" {
                go a.loadPremiumPage(acc)
        }
}

// openPremiumSubscribe opens a plan's payment deep link through the
// standard external-open pipeline (the browser handles the purchase —
// tdesktop's flow).
func (a *App) openPremiumSubscribe(p cores.PremiumPlanOption) {
        if p.BotURL == "" {
                a.setToast("No payment link for this plan")
                return
        }
        go a.openLinkExternal(p.BotURL)
}

// ── layout ─────────────────────────────────────────────────────────────────

// layoutPremiumPage renders the Premium sub-page inside the settings shell.
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

        // header: back + title + reload
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

        // account switcher chips (multiple accounts only)
        if len(f.accounts) > 1 {
                growClickables(&premiumAcctBtns, len(f.accounts))
                children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
                        return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
                                return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, a.premiumAcctChips(gtx, f, st)...)
                        })
                }))
        }

        // body
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

        // status card
        children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
                return a.premiumStatusCard(gtx, f, st)
        }))

        // plans (the server's own order)
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

        // limits comparison
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

// premiumStatusCard: the account's premium state — Active badge when
// subscribed, the server's status sentence otherwise.
func (a *App) premiumStatusCard(gtx layout.Context, f frame, st *premiumPageState) layout.Dimensions {
        premium := false
        for _, acc := range f.accounts {
                if acc.ID == st.accountID {
                        premium = acc.IsPremium
                        break
                }
        }
        return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
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
                                                        lines = append(lines, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
                                                                lbl := a.ui.Dim(unit.Sp(11), "Active on this account")
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
                                                return roundedFill(gtx, a.ui.p.AccentDim, 10, func(gtx layout.Context) layout.Dimensions {
                                                        return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
                                                                lbl := a.ui.Label(unit.Sp(12), "Active")
                                                                lbl.Color = a.ui.p.Accent
                                                                return lbl.Layout(gtx)
                                                        })
                                                })
                                        }),
                                )
                        })
                })
        })
}

// premiumPlanRow: one subscription option — duration, price, Subscribe
// (the current plan gets a badge instead of a button).
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

// premiumLimitRowLayout: one free-vs-premium comparison row.
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

// premiumAcctChips builds the account chip row for the page.
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
                                return roundedFill(gtx, bg, 14, func(gtx layout.Context) layout.Dimensions {
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

// premiumEntryRow renders the Settings → Main entry card.
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

// premiumEntryVisible: only Telegram-platform accounts have Premium —
// the entry card hides when the account list has none (§1.10).
func premiumEntryVisible(accounts []engine.AccountInfo) bool {
        for _, acc := range accounts {
                if acc.Platform == "telegram" || acc.Platform == "Telegram" {
                        return true
                }
        }
        return false
}
