package gui

import (
	"image"
	"strings"

	"gioui.org/font"
	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/cores"
)

const (
	stickerMgrTabStickers = iota
	stickerMgrTabEmoji
)

type stickerMgrState struct {
	accountID string
	tab       int
	loaded    bool
	loading   bool
	err       string

	packs    []cores.StickerPackSummary
	featured []cores.StickerPackSummary

	emojiSets    []cores.EmojiSetSummary
	emojiLoaded  bool
	emojiLoading bool
	emojiErr     string

	searchQ   string
	searchRes []cores.StickerPackSummary
	searching bool
	searchFor string
}

var (
	stickerMgrBackBtn   widget.Clickable
	stickerMgrReloadBtn widget.Clickable
	stickerMgrOpenBtn   widget.Clickable
	stickerMgrSearchEd  widget.Editor

	stickerMgrTabBtns      []widget.Clickable
	stickerMgrUpBtns       []widget.Clickable
	stickerMgrDownBtns     []widget.Clickable
	stickerMgrArchBtns     []widget.Clickable
	stickerMgrDelBtns      []widget.Clickable
	stickerMgrUnarchBtns   []widget.Clickable
	stickerMgrArchDelBtns  []widget.Clickable
	stickerMgrAddBtns      []widget.Clickable
	stickerMgrEmojiDelBtns []widget.Clickable
	stickerMgrAcctBtns     []widget.Clickable
)

func init() {
	stickerMgrSearchEd.SingleLine = true
}

func stickerMgrSplit(packs []cores.StickerPackSummary) (installed, archived []cores.StickerPackSummary) {
	for _, p := range packs {
		if p.Archived {
			archived = append(archived, p)
		} else {
			installed = append(installed, p)
		}
	}
	return installed, archived
}

func stickerMgrMoveOrder(ids []int64, i, delta int) []int64 {
	out := make([]int64, len(ids))
	copy(out, ids)
	j := i + delta
	if i < 0 || i >= len(out) || j < 0 || j >= len(out) || delta == 0 {
		return out
	}
	out[i], out[j] = out[j], out[i]
	return out
}

func stickerMgrSetOrder(packs []cores.StickerPackSummary) []int64 {
	ids := make([]int64, 0, len(packs))
	for _, p := range packs {
		ids = append(ids, p.SetID)
	}
	return ids
}

func stickerMgrRowSubtitle(p cores.StickerPackSummary) string {
	n := p.Count
	plural := "s"
	if n == 1 {
		plural = ""
	}
	line := itoa(n) + " sticker" + plural
	var kinds []string
	if p.Animated {
		kinds = append(kinds, "animated")
	}
	if p.Video {
		kinds = append(kinds, "video")
	}
	if p.Masks {
		kinds = append(kinds, "masks")
	}
	if p.Official {
		kinds = append(kinds, "official")
	}
	if len(kinds) > 0 {
		line += " · " + strings.Join(kinds, " · ")
	}
	return line
}

func stickerMgrEmojiSubtitle(s cores.EmojiSetSummary) string {
	line := itoa(s.Count) + " emoji"
	if s.Premium {
		line += " · premium"
	}
	return line
}

func stickerMgrFilter(packs []cores.StickerPackSummary, q string) []cores.StickerPackSummary {
	q = strings.TrimSpace(strings.ToLower(q))
	if q == "" {
		return packs
	}
	var out []cores.StickerPackSummary
	for _, p := range packs {
		if strings.Contains(strings.ToLower(p.Title), q) ||
			strings.Contains(strings.ToLower(p.ShortName), q) {
			out = append(out, p)
		}
	}
	return out
}

func stickerMgrFeaturedVisible(featured, known []cores.StickerPackSummary) []cores.StickerPackSummary {
	knownIDs := make(map[int64]bool, len(known))
	for _, p := range known {
		knownIDs[p.SetID] = true
	}
	var out []cores.StickerPackSummary
	for _, p := range featured {
		if !knownIDs[p.SetID] {
			out = append(out, p)
		}
	}
	return out
}

func stickerMgrSearchMerge(results, known []cores.StickerPackSummary) []cores.StickerPackSummary {
	return stickerMgrFeaturedVisible(results, known)
}

func (a *App) updateStickerMgr(fn func(st *stickerMgrState) bool) *stickerMgrState {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.stickerMgr == nil {
		return nil
	}
	next := *a.stickerMgr
	if !fn(&next) {
		return nil
	}
	a.stickerMgr = &next
	return &next
}

func (a *App) openStickerMgr(accountID string) {
	a.mu.Lock()
	a.stickerMgr = &stickerMgrState{accountID: accountID, loading: true}
	a.profileEdit = nil
	a.folderMgr = nil
	a.businessPage = nil
	a.premiumPage = nil
	a.starsPage = nil
	a.mu.Unlock()
	stickerMgrSearchEd.SetText("")
	go a.loadStickerMgr(accountID)
	a.invalidate()
}

func (a *App) closeStickerMgr() {
	a.mu.Lock()
	a.stickerMgr = nil
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) loadStickerMgr(accountID string) {
	packs, errP := a.eng.GetStickerSetSummaries(accountID)
	featured, errF := a.eng.GetFeaturedStickerPacks(accountID)
	a.updateStickerMgr(func(n *stickerMgrState) bool {
		if n.accountID != accountID {
			return false
		}
		n.loading = false
		if errP != nil {
			n.err = errP.Error()
		} else {
			n.err = ""
			n.packs = packs
			n.loaded = true
		}
		if errF == nil {
			n.featured = featured
		}
		return true
	})
	a.invalidate()
}

func (a *App) loadStickerMgrEmoji(accountID string) {
	sets, err := a.eng.GetInstalledEmojiSets(accountID)
	a.updateStickerMgr(func(n *stickerMgrState) bool {
		if n.accountID != accountID {
			return false
		}
		n.emojiLoading = false
		if err != nil {
			n.emojiErr = err.Error()
		} else {
			n.emojiErr = ""
			n.emojiSets = sets
			n.emojiLoaded = true
		}
		return true
	})
	a.invalidate()
}

func (a *App) reloadStickerMgr() {
	accountID := ""
	tab := 0
	a.updateStickerMgr(func(n *stickerMgrState) bool {
		accountID = n.accountID
		tab = n.tab
		n.loading = true
		n.searchRes = nil
		n.searching = false
		return true
	})
	if accountID == "" {
		return
	}
	go a.loadStickerMgr(accountID)
	if tab == stickerMgrTabEmoji {
		go a.loadStickerMgrEmoji(accountID)
	}
}

func (a *App) onStickerMgrSearchChanged(q string, accountID string) {
	q = strings.TrimSpace(q)
	key := accountID + "|" + q
	long := len([]rune(q)) >= 2
	if a.updateStickerMgr(func(n *stickerMgrState) bool {
		if n.accountID != accountID {
			return false
		}
		n.searchQ = q
		n.searchFor = key
		n.searching = long
		if !long {
			n.searchRes = nil
		}
		return true
	}) == nil {
		return
	}
	if !long {
		a.invalidate()
		return
	}
	go func() {
		results, err := a.eng.SearchStickerSets(accountID, q)
		if err != nil {
			results = nil
		}
		a.updateStickerMgr(func(n *stickerMgrState) bool {
			if n.searchFor != key {
				return false
			}
			n.searchRes = results
			n.searching = false
			return true
		})
		a.invalidate()
	}()
	a.invalidate()
}

func (a *App) stickerMgrAct(accountID string, do func() error) {
	go func() {
		if err := do(); err != nil {
			a.setToast("Stickers: " + err.Error())
		}
		a.reloadStickerMgr()
	}()
}

func (a *App) stickerMgrMove(accountID string, installed []cores.StickerPackSummary, i, delta int) {
	order := stickerMgrMoveOrder(stickerMgrSetOrder(installed), i, delta)
	a.stickerMgrAct(accountID, func() error {
		return a.eng.ReorderStickerSets(accountID, order)
	})
}

func (a *App) stickerMgrArchive(accountID string, p cores.StickerPackSummary, archived bool) {
	a.stickerMgrAct(accountID, func() error {
		return a.eng.ArchiveStickerSet(accountID, p.SetID, p.AccessHash, archived)
	})
}

func (a *App) stickerMgrDelete(accountID string, p cores.StickerPackSummary) {
	a.stickerMgrAct(accountID, func() error {
		return a.eng.UninstallStickerSet(accountID, p.SetID, p.AccessHash)
	})
}

func (a *App) stickerMgrInstall(accountID string, p cores.StickerPackSummary) {
	a.stickerMgrAct(accountID, func() error {
		return a.eng.InstallStickerSet(accountID, p.SetID, p.AccessHash)
	})
}

func (a *App) layoutStickerMgr(gtx layout.Context, f frame) layout.Dimensions {
	st := f.stickerMgr
	if st == nil {
		return layout.Dimensions{}
	}
	if stickerMgrBackBtn.Clicked(gtx) {
		a.closeStickerMgr()
	}
	if stickerMgrReloadBtn.Clicked(gtx) {
		a.reloadStickerMgr()
	}

	var children []layout.FlexChild

	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.IconButton(&stickerMgrBackBtn, iconNavigationBack, "Back")
					return btn.Layout(gtx)
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(17), "Stickers and Emoji")
					lbl.Font.Weight = font.SemiBold
					return lbl.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.IconButton(&stickerMgrReloadBtn, iconActionSchedule, "Reload")
					return btn.Layout(gtx)
				}),
			)
		})
	}))

	if len(f.accounts) > 1 {
		growClickables(&stickerMgrAcctBtns, len(f.accounts))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, a.acctChipsFlexChildren(gtx, f, st)...)
			})
		}))
	}

	growClickables(&stickerMgrTabBtns, 2)
	for i := range [...]string{"Stickers", "Emoji"} {
		if stickerMgrTabBtns[i].Clicked(gtx) {
			a.setStickerMgrTab(i)
		}
	}
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
				a.mgrTabChild(gtx, 0, "Stickers", st.tab == stickerMgrTabStickers),
				a.mgrTabChild(gtx, 1, "Emoji", st.tab == stickerMgrTabEmoji),
			)
		})
	}))

	if st.tab == stickerMgrTabEmoji {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.layoutStickerMgrEmoji(gtx, st)
		}))
	} else {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.layoutStickerMgrStickers(gtx, f, st)
		}))
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func (a *App) setStickerMgrTab(tab int) {
	needEmoji := false
	accountID := ""
	changed := false
	a.updateStickerMgr(func(n *stickerMgrState) bool {
		changed = n.tab != tab
		n.tab = tab
		needEmoji = tab == stickerMgrTabEmoji && !n.emojiLoaded && !n.emojiLoading
		if needEmoji {
			n.emojiLoading = true
			n.emojiErr = ""
		}
		accountID = n.accountID
		return true
	})
	if needEmoji {
		go a.loadStickerMgrEmoji(accountID)
	}
	if changed {
		a.invalidate()
	}
}

func (a *App) acctChipsFlexChildren(gtx layout.Context, f frame, st *stickerMgrState) []layout.FlexChild {
	var children []layout.FlexChild
	for i, acc := range f.accounts {
		i, acc := i, acc
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if stickerMgrAcctBtns[i].Clicked(gtx) && acc.ID != st.accountID {
				a.openStickerMgr(acc.ID)
			}
			active := acc.ID == st.accountID
			bg := a.ui.p.SurfaceHi
			txtCol := a.ui.p.TextDim
			if active {
				bg = a.ui.p.AccentDim
				txtCol = a.ui.p.Accent
			}
			return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				bl := material.ButtonLayout(a.ui.Theme, &stickerMgrAcctBtns[i])
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

func (a *App) mgrTabChild(gtx layout.Context, idx int, label string, active bool) layout.FlexChild {
	return layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		bg := a.ui.p.SurfaceHi
		txtCol := a.ui.p.TextDim
		if active {
			bg = a.ui.p.AccentDim
			txtCol = a.ui.p.Accent
		}
		return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			bl := material.ButtonLayout(a.ui.Theme, &stickerMgrTabBtns[idx])
			bl.Background = bg
			bl.CornerRadius = 16
			return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(13), label)
					lbl.Color = txtCol
					return lbl.Layout(gtx)
				})
			})
		})
	})
}

func (a *App) layoutStickerMgrStickers(gtx layout.Context, f frame, st *stickerMgrState) layout.Dimensions {
	installed, archived := stickerMgrSplit(st.packs)

	var children []layout.FlexChild

	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			for {
				ev, ok := stickerMgrSearchEd.Update(gtx)
				if !ok {
					break
				}
				if _, is := ev.(widget.ChangeEvent); is {
					a.onStickerMgrSearchChanged(stickerMgrSearchEd.Text(), st.accountID)
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
							ed := a.ui.Editor(&stickerMgrSearchEd, "Search sticker sets")
							return ed.Layout(gtx)
						}),
					)
				})
			})
		})
	}))

	if st.loading {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.centeredStateLabel(gtx, "Loading…")
		}))
	}
	if st.err != "" {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(13), st.err)
			return lbl.Layout(gtx)
		}))
	}

	visible := stickerMgrSearchMerge(st.searchRes, st.packs)
	if st.searching {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.centeredStateLabel(gtx, "Searching…")
		}))
	}
	if len(visible) > 0 {
		children = append(children, a.mgrSectionTitleChild("Results"))
		children = append(children, a.mgrResultRows(gtx, st, visible)...)
	}

	if !st.searching && len(st.searchQ) == 0 {
		if trending := stickerMgrFeaturedVisible(st.featured, st.packs); len(trending) > 0 {
			children = append(children, a.mgrSectionTitleChild("Trending"))
			children = append(children, a.mgrResultRows(gtx, st, trending)...)
		}
	}

	filtered := stickerMgrFilter(installed, st.searchQ)
	if !st.loading && st.err == "" {
		children = append(children, a.mgrSectionTitleChild("Installed"))
		if len(filtered) == 0 {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.centeredStateLabel(gtx, "No sticker sets")
			}))
		} else {
			growClickables(&stickerMgrUpBtns, len(filtered))
			growClickables(&stickerMgrDownBtns, len(filtered))
			growClickables(&stickerMgrArchBtns, len(filtered))
			growClickables(&stickerMgrDelBtns, len(filtered))
			for i, p := range filtered {
				i, p := i, p
				children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.mgrInstalledRow(gtx, st, p, i, len(filtered), installed)
				}))
			}
		}

		if len(archived) > 0 {
			children = append(children, a.mgrSectionTitleChild("Archived"))
			growClickables(&stickerMgrUnarchBtns, len(archived))
			growClickables(&stickerMgrArchDelBtns, len(archived))
			for i, p := range archived {
				i, p := i, p
				children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.mgrArchivedRow(gtx, st, p, i)
				}))
			}
		}
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func (a *App) layoutStickerMgrEmoji(gtx layout.Context, st *stickerMgrState) layout.Dimensions {
	var children []layout.FlexChild
	if st.emojiLoading {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.centeredStateLabel(gtx, "Loading…")
		}))
	} else if st.emojiErr != "" {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(13), st.emojiErr)
			return lbl.Layout(gtx)
		}))
	} else if len(st.emojiSets) == 0 {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.centeredStateLabel(gtx, "No custom emoji packs")
		}))
	} else {
		children = append(children, a.mgrSectionTitleChild("Emoji packs"))
		growClickables(&stickerMgrEmojiDelBtns, len(st.emojiSets))
		for i, s := range st.emojiSets {
			i, s := i, s
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.mgrEmojiRow(gtx, st, s, i)
			}))
		}
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func (a *App) mgrSectionTitleChild(title string) layout.FlexChild {
	return layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, title)
	})
}

func (a *App) mgrResultRows(gtx layout.Context, st *stickerMgrState, rows []cores.StickerPackSummary) []layout.FlexChild {
	pool := len(rows)
	if len(st.featured) > pool {
		pool = len(st.featured)
	}
	if len(st.searchRes) > pool {
		pool = len(st.searchRes)
	}
	growClickables(&stickerMgrAddBtns, pool)
	var children []layout.FlexChild
	for i, p := range rows {
		i, p := i, p
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.mgrResultRow(gtx, st, p, i)
		}))
	}
	return children
}

func (a *App) mgrResultRow(gtx layout.Context, st *stickerMgrState, p cores.StickerPackSummary, i int) layout.Dimensions {
	if stickerMgrAddBtns[i].Clicked(gtx) {
		a.stickerMgrInstall(st.accountID, p)
	}
	return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.mgrPackThumb(gtx, p)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), p.Title)
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), stickerMgrRowSubtitle(p))
								return lbl.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.IconButton(&stickerMgrAddBtns[i], iconContentAdd, "Add")
						return btn.Layout(gtx)
					}),
				)
			})
		})
	})
}

func (a *App) mgrInstalledRow(gtx layout.Context, st *stickerMgrState, p cores.StickerPackSummary, i, n int, installed []cores.StickerPackSummary) layout.Dimensions {
	if i > 0 && stickerMgrUpBtns[i].Clicked(gtx) {
		a.stickerMgrMove(st.accountID, installed, i, -1)
	}
	if i < n-1 && stickerMgrDownBtns[i].Clicked(gtx) {
		a.stickerMgrMove(st.accountID, installed, i, 1)
	}
	if stickerMgrArchBtns[i].Clicked(gtx) {
		a.stickerMgrArchive(st.accountID, p, true)
	}
	if stickerMgrDelBtns[i].Clicked(gtx) {
		a.stickerMgrDelete(st.accountID, p)
	}
	return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.mgrPackThumb(gtx, p)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), p.Title)
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), stickerMgrRowSubtitle(p))
								return lbl.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if i == 0 {
							return layout.Dimensions{}
						}
						btn := a.ui.IconButton(&stickerMgrUpBtns[i], iconMgrUp, "Move up")
						return btn.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if i == n-1 {
							return layout.Dimensions{}
						}
						btn := a.ui.IconButton(&stickerMgrDownBtns[i], iconMgrDown, "Move down")
						return btn.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.IconButton(&stickerMgrArchBtns[i], iconMgrArchive, "Archive")
						return btn.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.IconButton(&stickerMgrDelBtns[i], iconActionDelete, "Delete")
						return btn.Layout(gtx)
					}),
				)
			})
		})
	})
}

func (a *App) mgrArchivedRow(gtx layout.Context, st *stickerMgrState, p cores.StickerPackSummary, i int) layout.Dimensions {
	if stickerMgrUnarchBtns[i].Clicked(gtx) {
		a.stickerMgrArchive(st.accountID, p, false)
	}
	if stickerMgrArchDelBtns[i].Clicked(gtx) {
		a.stickerMgrDelete(st.accountID, p)
	}
	return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.mgrPackThumb(gtx, p)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), p.Title)
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), stickerMgrRowSubtitle(p))
								return lbl.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.IconButton(&stickerMgrUnarchBtns[i], iconMgrUnarchive, "Restore")
						return btn.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.IconButton(&stickerMgrArchDelBtns[i], iconActionDelete, "Delete")
						return btn.Layout(gtx)
					}),
				)
			})
		})
	})
}

func (a *App) mgrEmojiRow(gtx layout.Context, st *stickerMgrState, s cores.EmojiSetSummary, i int) layout.Dimensions {
	if stickerMgrEmojiDelBtns[i].Clicked(gtx) {
		a.stickerMgrDelete(st.accountID, cores.StickerPackSummary{SetID: s.SetID, AccessHash: s.AccessHash})
	}
	return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.mgrEmojiThumb(gtx, s)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), s.Title)
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), stickerMgrEmojiSubtitle(s))
								return lbl.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.IconButton(&stickerMgrEmojiDelBtns[i], iconActionDelete, "Delete")
						return btn.Layout(gtx)
					}),
				)
			})
		})
	})
}

func (a *App) mgrPackThumb(gtx layout.Context, p cores.StickerPackSummary) layout.Dimensions {
	max := gtx.Dp(unit.Dp(44))
	if p.ThumbB64 != "" {
		if img := a.avatarImage("", p.ThumbB64); img != nil {
			return drawImageScaled(gtx, img, max, max, max/8)
		}
		return layout.Dimensions{Size: image.Pt(max, max)}
	}
	lbl := a.ui.Label(unit.Sp(20), "🙂")
	return lbl.Layout(gtx)
}

func (a *App) mgrEmojiThumb(gtx layout.Context, s cores.EmojiSetSummary) layout.Dimensions {
	max := gtx.Dp(unit.Dp(44))
	for _, st := range s.Stickers {
		if st.ThumbB64 != "" {
			if img := a.avatarImage("", st.ThumbB64); img != nil {
				return drawImageScaled(gtx, img, max, max, max/8)
			}
			break
		}
	}
	lbl := a.ui.Label(unit.Sp(20), "😀")
	return lbl.Layout(gtx)
}

func (a *App) stickerMgrEntryRow(gtx layout.Context, f frame) layout.Dimensions {
	if stickerMgrOpenBtn.Clicked(gtx) {
		a.openStickerMgr(mgrAccountID(f))
	}
	return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
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
								lbl := a.ui.Label(unit.Sp(14), "Stickers and Emoji")
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), "Manage installed packs, trending, archived")
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

func mgrAccountID(f frame) string {
	if f.selected != nil {
		return f.selected.AccountID
	}
	for _, acc := range f.accounts {
		if strings.EqualFold(acc.Platform, "telegram") {
			return acc.ID
		}
	}
	if len(f.accounts) > 0 {
		return f.accounts[0].ID
	}
	return ""
}
