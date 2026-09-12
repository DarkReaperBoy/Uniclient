package gui

// settingsstars.go — slice 144: the Telegram Stars page (tdesktop's
// Stars box). The account's own balance, the full transaction history
// with filter tabs and load-more paging, refund/pending/failed chips.
// Everything is engine-backed (payments.getStarsTransactions with
// Peer=self); cores without stars hide the section honestly (§1.10).

import (
	"time"

	"gioui.org/font"
	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/cores"
)

// ── pure helpers (unit-tested) ─────────────────────────────────────────────

// formatStars renders a signed nanostar amount as a trimmed decimal —
// whole stars without a separator, fractional parts with trailing zeros
// trimmed. Pure.
func formatStars(nano int64) string {
	neg := nano < 0
	if neg {
		nano = -nano
	}
	whole := nano / 1_000_000_000
	frac := nano % 1_000_000_000
	out := ""
	if frac == 0 {
		out = itoa(int(whole))
	} else {
		fs := ""
		for i := 0; i < 9; i++ {
			d := frac / 100_000_000
			frac = (frac % 100_000_000) * 10
			fs += itoa(int(d))
			if frac == 0 {
				break
			}
		}
		for len(fs) > 0 && fs[len(fs)-1] == '0' {
			fs = fs[:len(fs)-1]
		}
		out = itoa(int(whole)) + "." + fs
	}
	if neg {
		return "-" + out
	}
	return out
}

// starsTxnAmountLabel: the row's amount — incoming with +, spending
// with -. Pure.
func starsTxnAmountLabel(txn cores.StarsTxn) string {
	s := formatStars(txn.NanoStars)
	if txn.NanoStars > 0 {
		return "+" + s
	}
	return s
}

// starsTxnTitle: the row's title — the bought product's title first,
// then the counterparty's name, then the honest fallback. Pure.
func starsTxnTitle(txn cores.StarsTxn) string {
	if txn.Title != "" {
		return txn.Title
	}
	if txn.PeerTitle != "" {
		return txn.PeerTitle
	}
	return "Stars"
}

// starsTxnStatusChip: the state chip — Failed beats Pending beats
// Refunded; plain transactions have none. Pure.
func starsTxnStatusChip(txn cores.StarsTxn) string {
	switch {
	case txn.Failed:
		return "Failed"
	case txn.Pending:
		return "Pending"
	case txn.Refund:
		return "Refunded"
	}
	return ""
}

// starsFilterTab is one history filter tab.
type starsFilterTab struct {
	label  string
	filter string // wire filter: "" | "in" | "out"
}

// starsFilterTabs: All / Incoming / Outgoing (tdesktop's tabs). Pure.
func starsFilterTabs() []starsFilterTab {
	return []starsFilterTab{
		{"All", ""},
		{"Incoming", "in"},
		{"Outgoing", "out"},
	}
}

// ── state ──────────────────────────────────────────────────────────────────

// starsPageState is the open Stars sub-page.
type starsPageState struct {
	accountID string
	filter    string
	loading   bool
	loaded    bool
	err       string

	status    *cores.StarsStatus
	nextPage  string // next_offset of the loaded page
	appending bool   // a load-more is in flight
}

var (
	starsOpenBtn   widget.Clickable // Settings → Main entry card
	starsBackBtn   widget.Clickable
	starsReloadBtn widget.Clickable
	starsMoreBtn   widget.Clickable
	starsTabBtns   []widget.Clickable
	starsAcctBtns  []widget.Clickable
)

// openStarsPage starts the page for an account and loads its data.
func (a *App) openStarsPage(accountID string) {
	a.mu.Lock()
	a.starsPage = &starsPageState{accountID: accountID, loading: true}
	a.profileEdit = nil // one sub-page at a time (settings shell)
	a.stickerMgr = nil
	a.folderMgr = nil
	a.businessPage = nil
	a.premiumPage = nil
	a.mu.Unlock()
	go a.loadStarsPage(accountID, "", false)
	a.invalidate()
}

// closeStarsPage dismisses the page.
func (a *App) closeStarsPage() {
	a.mu.Lock()
	a.starsPage = nil
	a.mu.Unlock()
	a.invalidate()
}

// loadStarsPage fetches one page of history (append keeps the loaded
// rows and adds the next page).
func (a *App) loadStarsPage(accountID, offset string, appendMode bool) {
	filter := ""
	a.mu.Lock()
	if st := a.starsPage; st != nil && st.accountID == accountID {
		filter = st.filter
		if appendMode {
			st.appending = true
		}
	}
	a.mu.Unlock()
	status, err := a.eng.GetMyStars(accountID, offset, filter)
	a.mu.Lock()
	st := a.starsPage
	if st == nil || st.accountID != accountID {
		a.mu.Unlock()
		return
	}
	if appendMode {
		st.appending = false
	} else {
		st.loading = false
	}
	if err != nil {
		if !appendMode {
			st.err = err.Error()
		}
		a.mu.Unlock()
		a.invalidate()
		return
	}
	st.err = ""
	st.loaded = true
	if status != nil {
		if appendMode && st.status != nil {
			st.status.Txns = append(st.status.Txns, status.Txns...)
			st.status.NextOffset = status.NextOffset
		} else {
			st.status = status
		}
		st.nextPage = status.NextOffset
	} else {
		if !appendMode {
			st.status = nil
		}
		st.nextPage = ""
	}
	a.mu.Unlock()
	a.invalidate()
}

// setStarsFilter switches the history filter and reloads the first page.
func (a *App) setStarsFilter(filter string) {
	a.mu.Lock()
	st := a.starsPage
	if st == nil || st.filter == filter {
		a.mu.Unlock()
		return
	}
	st.filter = filter
	st.loading = true
	st.status = nil
	st.nextPage = ""
	acc := st.accountID
	a.mu.Unlock()
	go a.loadStarsPage(acc, "", false)
	a.invalidate()
}

// reloadStarsPage re-pulls the first page.
func (a *App) reloadStarsPage() {
	a.mu.Lock()
	acc := ""
	filter := ""
	if st := a.starsPage; st != nil {
		acc = st.accountID
		filter = st.filter
		st.loading = true
		_ = filter
	}
	a.mu.Unlock()
	if acc != "" {
		go a.loadStarsPage(acc, "", false)
	}
}

// loadMoreStars fetches the next page when one exists.
func (a *App) loadMoreStars() {
	a.mu.Lock()
	st := a.starsPage
	if st == nil || st.nextPage == "" || st.appending {
		a.mu.Unlock()
		return
	}
	acc, off := st.accountID, st.nextPage
	a.mu.Unlock()
	go a.loadStarsPage(acc, off, true)
}

// ── layout ─────────────────────────────────────────────────────────────────

// layoutStarsPage renders the Stars sub-page inside the settings shell.
func (a *App) layoutStarsPage(gtx layout.Context, f frame) layout.Dimensions {
	st := f.starsPage
	if st == nil {
		return layout.Dimensions{}
	}
	if starsBackBtn.Clicked(gtx) {
		a.closeStarsPage()
	}
	if starsReloadBtn.Clicked(gtx) {
		a.reloadStarsPage()
	}
	if starsMoreBtn.Clicked(gtx) {
		a.loadMoreStars()
	}

	var children []layout.FlexChild

	// header: back + title + reload
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.IconButton(&starsBackBtn, iconNavigationBack, "Back")
					return btn.Layout(gtx)
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(17), "Telegram Stars")
					lbl.Font.Weight = font.SemiBold
					return lbl.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.IconButton(&starsReloadBtn, iconActionSchedule, "Reload")
					return btn.Layout(gtx)
				}),
			)
		})
	}))

	// account switcher chips (multiple accounts only)
	if len(f.accounts) > 1 {
		growClickables(&starsAcctBtns, len(f.accounts))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, a.starsAcctChips(gtx, f, st)...)
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

	// balance card
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.starsBalanceCard(gtx, st)
	}))

	// filter tabs (ButtonLayout renders the click area — no dead tabs)
	tabs := starsFilterTabs()
	growClickables(&starsTabBtns, len(tabs))
	for i, tab := range tabs {
		i, tab := i, tab
		if starsTabBtns[i].Clicked(gtx) {
			a.setStarsFilter(tab.filter)
		}
	}
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			var tabChildren []layout.FlexChild
			for i, tab := range tabs {
				i, tab := i, tab
				tabChildren = append(tabChildren, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					active := st.filter == tab.filter
					bg := a.ui.p.SurfaceHi
					txtCol := a.ui.p.TextDim
					if active {
						bg = a.ui.p.AccentDim
						txtCol = a.ui.p.Accent
					}
					return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						bl := material.ButtonLayout(a.ui.Theme, &starsTabBtns[i])
						bl.Background = bg
						bl.CornerRadius = 14
						return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(12), tab.label)
								lbl.Color = txtCol
								return lbl.Layout(gtx)
							})
						})
					})
				}))
			}
			return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, tabChildren...)
		})
	}))

	// transaction rows
	if st.status != nil {
		for _, txn := range st.status.Txns {
			txn := txn
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.starsTxnRow(gtx, txn)
			}))
		}
		if len(st.status.Txns) == 0 {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(13), "No transactions")
				return lbl.Layout(gtx)
			}))
		}
		// load more
		if st.nextPage != "" {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.SurfaceButton(&starsMoreBtn, "Load more")
					return btn.Layout(gtx)
				})
			}))
		}
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// starsBalanceCard: the big balance number.
func (a *App) starsBalanceCard(gtx layout.Context, st *starsPageState) layout.Dimensions {
	balance := "0"
	if st.status != nil {
		balance = formatStars(st.status.BalanceNano)
	}
	return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(14)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return iconToggleStar.Layout(gtx, a.ui.p.Accent)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(22), balance)
						lbl.Font.Weight = font.SemiBold
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(13), "Stars")
							return lbl.Layout(gtx)
						})
					}),
				)
			})
		})
	})
}

// starsTxnRow: one transaction — title/description, status chip, date,
// signed amount.
func (a *App) starsTxnRow(gtx layout.Context, txn cores.StarsTxn) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						lines := []layout.FlexChild{
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), starsTxnTitle(txn))
								return lbl.Layout(gtx)
							}),
						}
						sub := txn.Description
						if sub == "" {
							sub = time.Unix(txn.Date, 0).Format("2 Jan 15:04")
						}
						subLines := sub
						lines = append(lines, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(11), subLines)
							return lbl.Layout(gtx)
						}))
						if chip := starsTxnStatusChip(txn); chip != "" {
							lines = append(lines, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return roundedFill(gtx, a.ui.p.AccentDim, 8, func(gtx layout.Context) layout.Dimensions {
										return layout.UniformInset(unit.Dp(3)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
											lbl := a.ui.Label(unit.Sp(10), chip)
											lbl.Color = a.ui.p.Accent
											return lbl.Layout(gtx)
										})
									})
								})
							}))
						}
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx, lines...)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(14), starsTxnAmountLabel(txn))
							if txn.NanoStars > 0 {
								lbl.Color = a.ui.p.Accent
							}
							return lbl.Layout(gtx)
						})
					}),
				)
			})
		})
	})
}

// starsAcctChips builds the account chip row for the page.
func (a *App) starsAcctChips(gtx layout.Context, f frame, st *starsPageState) []layout.FlexChild {
	var children []layout.FlexChild
	for i, acc := range f.accounts {
		i, acc := i, acc
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if starsAcctBtns[i].Clicked(gtx) && acc.ID != st.accountID {
				a.openStarsPage(acc.ID)
			}
			active := acc.ID == st.accountID
			bg := a.ui.p.SurfaceHi
			txtCol := a.ui.p.TextDim
			if active {
				bg = a.ui.p.AccentDim
				txtCol = a.ui.p.Accent
			}
			return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				bl := material.ButtonLayout(a.ui.Theme, &starsAcctBtns[i])
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

// starsEntryRow renders the Settings → Main entry card.
func (a *App) starsEntryRow(gtx layout.Context, f frame) layout.Dimensions {
	if starsOpenBtn.Clicked(gtx) {
		a.openStarsPage(mgrAccountID(f))
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
								lbl := a.ui.Label(unit.Sp(14), "Telegram Stars")
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), "Balance and transaction history")
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
