package gui

// Stickers & Emoji manager (AyuGram parity slice 139): tdesktop's
// Settings → "Stickers and Emoji" — a sub-page of Settings → Main with
// Stickers / Emoji tabs over the account's installed sets. Stickers tab:
// search (server results with Add), Trending (featured, Add), installed
// rows with move-up/move-down (ReorderStickerSets), Archive
// (installStickerSet Archived flag — hides without deleting), Delete
// (uninstall), plus an Archived section with Restore/Delete. Emoji tab:
// installed custom-emoji packs with Delete. Every action reloads the
// listing from the server (honest state, §1.10); unsupported accounts
// show the engine error, never a dead row.

import (
	"image"
	"strings"

	"gioui.org/font"
	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"

	"uniclient/cores"
)

// manager tabs.
const (
	stickerMgrTabStickers = iota
	stickerMgrTabEmoji
)

// stickerMgrState is the open manager page.
type stickerMgrState struct {
	accountID string
	tab       int
	loaded    bool
	loading   bool
	err       string

	packs    []cores.StickerPackSummary // installed + archived rows
	featured []cores.StickerPackSummary

	emojiSets    []cores.EmojiSetSummary
	emojiLoaded  bool
	emojiLoading bool
	emojiErr     string

	searchQ   string
	searchRes []cores.StickerPackSummary
	searching bool
	searchFor string // stale-run key
}

var (
	stickerMgrBackBtn   widget.Clickable
	stickerMgrReloadBtn widget.Clickable
	stickerMgrOpenBtn   widget.Clickable
	stickerMgrSearchEd  widget.Editor
	stickerMgrScroll    widget.List

	stickerMgrTabBtns      []widget.Clickable
	stickerMgrUpBtns       []widget.Clickable // installed: move up
	stickerMgrDownBtns     []widget.Clickable // installed: move down
	stickerMgrArchBtns     []widget.Clickable // installed: archive
	stickerMgrDelBtns      []widget.Clickable // installed: delete
	stickerMgrUnarchBtns   []widget.Clickable // archived: restore
	stickerMgrArchDelBtns  []widget.Clickable // archived: delete
	stickerMgrAddBtns      []widget.Clickable // featured + search: install
	stickerMgrEmojiDelBtns []widget.Clickable
	stickerMgrAcctBtns     []widget.Clickable
)

func init() {
	stickerMgrSearchEd.SingleLine = true
}

// ── pure helpers ────────────────────────────────────────────────────────

// stickerMgrSplit partitions summaries into installed and archived rows,
// order preserved.
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

// stickerMgrMoveOrder returns the set-ID order after moving index i by
// delta (clamped at the edges). Input is not mutated.
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

// stickerMgrSetOrder extracts the set-ID order of a summary list.
func stickerMgrSetOrder(packs []cores.StickerPackSummary) []int64 {
	ids := make([]int64, 0, len(packs))
	for _, p := range packs {
		ids = append(ids, p.SetID)
	}
	return ids
}

// stickerMgrRowSubtitle renders the set's count + kind line.
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

// stickerMgrEmojiSubtitle renders an emoji pack's count line.
func stickerMgrEmojiSubtitle(s cores.EmojiSetSummary) string {
	line := itoa(s.Count) + " emoji"
	if s.Premium {
		line += " · premium"
	}
	return line
}

// stickerMgrFilter filters summaries by a query on title or short name
// (case-insensitive, trimmed).
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

// stickerMgrFeaturedVisible drops featured rows already known (installed
// or archived).
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

// stickerMgrSearchMerge keeps only server-search rows the account doesn't
// already know (dedup against installed + archived).
func stickerMgrSearchMerge(results, known []cores.StickerPackSummary) []cores.StickerPackSummary {
	return stickerMgrFeaturedVisible(results, known)
}

// ── page lifecycle ──────────────────────────────────────────────────────

// openStickerMgr starts the manager for an account and loads its data.
func (a *App) openStickerMgr(accountID string) {
	a.mu.Lock()
	a.stickerMgr = &stickerMgrState{accountID: accountID, loading: true}
	a.profileEdit = nil // one sub-page at a time (settings shell)
	a.mu.Unlock()
	stickerMgrSearchEd.SetText("")
	go a.loadStickerMgr(accountID)
	a.invalidate()
}

// closeStickerMgr dismisses the page.
func (a *App) closeStickerMgr() {
	a.mu.Lock()
	a.stickerMgr = nil
	a.mu.Unlock()
	a.invalidate()
}

// loadStickerMgr fetches the account's set listing + featured packs.
func (a *App) loadStickerMgr(accountID string) {
	packs, errP := a.eng.GetStickerSetSummaries(accountID)
	featured, errF := a.eng.GetFeaturedStickerPacks(accountID)
	a.mu.Lock()
	st := a.stickerMgr
	if st == nil || st.accountID != accountID {
		a.mu.Unlock()
		return
	}
	st.loading = false
	if errP != nil {
		st.err = errP.Error()
	} else {
		st.err = ""
		st.packs = packs
		st.loaded = true
	}
	if errF == nil {
		st.featured = featured
	}
	a.mu.Unlock()
	a.invalidate()
}

// loadStickerMgrEmoji lazy-loads the emoji tab on first entry.
func (a *App) loadStickerMgrEmoji(accountID string) {
	sets, err := a.eng.GetInstalledEmojiSets(accountID)
	a.mu.Lock()
	st := a.stickerMgr
	if st == nil || st.accountID != accountID {
		a.mu.Unlock()
		return
	}
	st.emojiLoading = false
	if err != nil {
		st.emojiErr = err.Error()
	} else {
		st.emojiErr = ""
		st.emojiSets = sets
		st.emojiLoaded = true
	}
	a.mu.Unlock()
	a.invalidate()
}

// reloadStickerMgr re-runs the current tab's load.
func (a *App) reloadStickerMgr() {
	a.mu.Lock()
	st := a.stickerMgr
	tab := 0
	accountID := ""
	if st != nil {
		accountID = st.accountID
		tab = st.tab
		st.loading = true
		st.searchRes = nil
		st.searching = false
	}
	a.mu.Unlock()
	if accountID == "" {
		return
	}
	go a.loadStickerMgr(accountID)
	if tab == stickerMgrTabEmoji {
		go a.loadStickerMgrEmoji(accountID)
	}
}

// onStickerMgrSearchChanged (GUI goroutine) launches the async server
// search; stale writes dropped by key (in-chat-search pattern).
func (a *App) onStickerMgrSearchChanged(q string, accountID string) {
	q = strings.TrimSpace(q)
	key := accountID + "|" + q
	a.mu.Lock()
	st := a.stickerMgr
	if st == nil || st.accountID != accountID {
		a.mu.Unlock()
		return
	}
	st.searchQ = q
	st.searchFor = key
	st.searching = len([]rune(q)) >= 2
	if len([]rune(q)) < 2 {
		st.searchRes = nil
		st.searching = false
		a.mu.Unlock()
		a.invalidate()
		return
	}
	a.mu.Unlock()
	go func() {
		results, err := a.eng.SearchStickerSets(accountID, q)
		if err != nil {
			results = nil
		}
		a.mu.Lock()
		if st := a.stickerMgr; st != nil && st.searchFor == key {
			st.searchRes = results
			st.searching = false
		}
		a.mu.Unlock()
		a.invalidate()
	}()
	a.invalidate()
}

// ── actions (async, reload on completion) ───────────────────────────────

func (a *App) stickerMgrAct(accountID string, do func() error) {
	go func() {
		if err := do(); err != nil {
			a.setToast("Stickers: " + err.Error())
		}
		a.reloadStickerMgr()
	}()
}

// stickerMgrMove reorders installed sets after moving row i by delta.
func (a *App) stickerMgrMove(accountID string, installed []cores.StickerPackSummary, i, delta int) {
	order := stickerMgrMoveOrder(stickerMgrSetOrder(installed), i, delta)
	a.stickerMgrAct(accountID, func() error {
		return a.eng.ReorderStickerSets(accountID, order)
	})
}

// stickerMgrArchive toggles a set's archived flag.
func (a *App) stickerMgrArchive(accountID string, p cores.StickerPackSummary, archived bool) {
	a.stickerMgrAct(accountID, func() error {
		return a.eng.ArchiveStickerSet(accountID, p.SetID, p.AccessHash, archived)
	})
}

// stickerMgrDelete uninstalls a set.
func (a *App) stickerMgrDelete(accountID string, p cores.StickerPackSummary) {
	a.stickerMgrAct(accountID, func() error {
		return a.eng.UninstallStickerSet(accountID, p.SetID, p.AccessHash)
	})
}

// stickerMgrInstall adds a featured/search result.
func (a *App) stickerMgrInstall(accountID string, p cores.StickerPackSummary) {
	a.stickerMgrAct(accountID, func() error {
		return a.eng.InstallStickerSet(accountID, p.SetID, p.AccessHash)
	})
}

// ── layout ──────────────────────────────────────────────────────────────

// layoutStickerMgr renders the manager sub-page inside the settings shell.
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

	// header: back + title + reload
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

	// account switcher chips (multiple accounts only)
	if len(f.accounts) > 1 {
		growClickables(&stickerMgrAcctBtns, len(f.accounts))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, a.acctChipsFlexChildren(gtx, f, st)...)
			})
		}))
	}

	// tabs
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

	// body
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

// setStickerMgrTab switches tabs, lazily loading the emoji listing.
func (a *App) setStickerMgrTab(tab int) {
	a.mu.Lock()
	st := a.stickerMgr
	changed := st != nil && st.tab != tab
	if st != nil {
		st.tab = tab
		needEmoji := tab == stickerMgrTabEmoji && !st.emojiLoaded && !st.emojiLoading
		if needEmoji {
			st.emojiLoading = true
			st.emojiErr = ""
		}
		accountID := st.accountID
		a.mu.Unlock()
		if needEmoji {
			go a.loadStickerMgrEmoji(accountID)
		}
		if changed {
			a.invalidate()
		}
		return
	}
	a.mu.Unlock()
}

// acctChipsFlexChildren builds the account chip row.
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

// mgrTabChild renders one tab chip.
func (a *App) mgrTabChild(gtx layout.Context, idx int, label string, active bool) layout.FlexChild {
	return layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		bg := a.ui.p.SurfaceHi
		txtCol := a.ui.p.TextDim
		if active {
			bg = a.ui.p.AccentDim
			txtCol = a.ui.p.Accent
		}
		return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return roundedFill(gtx, bg, 16, func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(13), label)
					lbl.Color = txtCol
					return lbl.Layout(gtx)
				})
			})
		})
	})
}

// layoutStickerMgrStickers renders the stickers tab: search field,
// search results, trending, installed, archived.
func (a *App) layoutStickerMgrStickers(gtx layout.Context, f frame, st *stickerMgrState) layout.Dimensions {
	installed, archived := stickerMgrSplit(st.packs)

	var children []layout.FlexChild

	// search field (live server search, 2+ runes)
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

	// state rows
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

	// search results (server hits not already known)
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

	// trending (featured minus known) — hidden while searching
	if !st.searching && len(st.searchQ) == 0 {
		if trending := stickerMgrFeaturedVisible(st.featured, st.packs); len(trending) > 0 {
			children = append(children, a.mgrSectionTitleChild("Trending"))
			children = append(children, a.mgrResultRows(gtx, st, trending)...)
		}
	}

	// installed rows (filtered locally when query present)
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

		// archived rows
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

	// rides the settings shell's scroll list (profileEdit pattern)
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// layoutStickerMgrEmoji renders the emoji tab.
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
	// rides the settings shell's scroll list (profileEdit pattern)
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// mgrSectionTitleChild builds a section heading flex child.
func (a *App) mgrSectionTitleChild(title string) layout.FlexChild {
	return layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, title)
	})
}

// mgrResultRows builds Add-rows for featured/search results.
func (a *App) mgrResultRows(gtx layout.Context, st *stickerMgrState, rows []cores.StickerPackSummary) []layout.FlexChild {
	// clickable pool spans the union of trending + search rows; size by
	// the larger of the two to keep indices stable within one frame.
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

// mgrResultRow renders a featured/search row with an Add button.
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

// mgrInstalledRow renders an installed set row: thumb, title, subtitle,
// move up/down, archive, delete.
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

// mgrArchivedRow renders an archived set row: restore + delete.
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

// mgrEmojiRow renders an installed emoji pack row with Delete.
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

// mgrPackThumb paints the set's thumbnail or a generic emoji tile.
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

// mgrEmojiThumb paints an emoji pack's first sticker thumb or a tile.
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

// stickerMgrEntryRow renders the Settings → Main entry card: tappable row
// opening the manager for the first Telegram-capable account (the manager
// itself offers per-account chips when several accounts exist).
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

// mgrAccountID picks the manager's default account: the active chat's
// account, else the first telegram-platform account, else the first
// account (the page reports platform support honestly).
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
