package gui

import (
	"image"
	"strings"

	"gioui.org/io/event"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/cores"
)

// Saved Messages sublists (slice 197, tdesktop 5.16 parity): the saved
// chat gains a header button that opens the sublists pane (the right
// sidebar — one row per dialog the user saved messages from, "All
// messages" on top, pinned first), and picking a sublist scopes the
// message view to it (bar under the header: back → the whole saved
// chat; the page reads the messages cache filtered by saved_peer, fed
// by messages.getSavedHistory on first open and the live update stream
// after). Sending while scoped keeps the plain self-chat target
// (tdesktop: a new note lands in "My Notes", not the filtered peer).

// savedScopeState: the open sublist/tag scope (nil = the whole saved
// chat). A tag scope (tag != "") pages through the server-side
// reaction-tag search; a sublist scope through the saved_peer cache
// filter.
type savedScopeState struct {
	peerID string // the sublist peer (the saved_peer filter value)
	title  string // display title (bar + window title)
	tag    string // reaction-tag emoji (non-empty = tag scope, peerID "")
}

// sortSavedSublists: pinned rows first (in the SERVER pin order —
// slice 204: reorder must be visible, and messages.getSavedDialogs
// returns the pin order), then the unpinned tail by last activity
// (newest first). Pure — locked by tests.
func sortSavedSublists(lists []cores.SavedSublistInfo) []cores.SavedSublistInfo {
	pinned := make([]cores.SavedSublistInfo, 0, len(lists))
	tail := make([]cores.SavedSublistInfo, 0, len(lists))
	for _, l := range lists {
		if l.IsPinned {
			pinned = append(pinned, l)
		} else {
			tail = append(tail, l)
		}
	}
	sortSavedByTimeDesc(tail)
	return append(pinned, tail...)
}

// sortSavedByTimeDesc is a tiny stable insertion sort (small n).
// Pure.
func sortSavedByTimeDesc(rows []cores.SavedSublistInfo) {
	for i := 1; i < len(rows); i++ {
		for j := i; j > 0 && rows[j].LastMsgTime > rows[j-1].LastMsgTime; j-- {
			rows[j], rows[j-1] = rows[j-1], rows[j]
		}
	}
}

// savedScopeBarTitle: "Saved from <name>" (generic when unknown).
// Pure — locked by tests.
func savedScopeBarTitle(title string) string {
	title = strings.TrimSpace(title)
	if title == "" {
		return "Saved messages"
	}
	return "Saved from " + title
}

// savedSublistRowTitle: the row title with the honest fallback.
// Pure — locked by tests.
func savedSublistRowTitle(l cores.SavedSublistInfo) string {
	if t := strings.TrimSpace(l.PeerName); t != "" {
		return t
	}
	return "Saved messages"
}

// savedSublistPreview: the top message's text, trimmed for the row.
// Pure — locked by tests.
func savedSublistPreview(l cores.SavedSublistInfo) string {
	p := strings.TrimSpace(l.LastMsgText)
	if len(p) > 58 {
		p = p[:58] + "…"
	}
	return p
}

// savedTagBarTitle: the open tag scope's bar title — "Tag · <title>"
// (the emoji alone when the tag has no name). Pure — locked by tests.
func savedTagBarTitle(emoji, title string) string {
	title = strings.TrimSpace(title)
	if title == "" {
		return "Tag " + emoji
	}
	return "Tag " + emoji + " · " + title
}

// savedTagRowLabel: one tag row's title — the tag's name, else the bare
// emoji. Pure — locked by tests.
func savedTagRowLabel(tg cores.SavedReactionTagInfo) string {
	if tg.Title != "" {
		return tg.Title
	}
	if tg.Emoji != "" {
		return tg.Emoji
	}
	return "tag"
}

// tagsSectionVisible: the Lists pane shows the Tags section only for
// premium accounts with tags on the server (honest gating — dead UI
// banned, §1.10). Pure — locked by tests.
func tagsSectionVisible(accountPremium bool, tags []cores.SavedReactionTagInfo) bool {
	return accountPremium && len(tags) > 0
}

// savedScopeFor returns the open saved-sublist scope when the selected
// chat is the saved chat it belongs to (nil = none).
func (a *App) savedScopeFor(k *chatKey) *savedScopeState {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.savedScope == nil || k == nil || a.selected == nil {
		return nil
	}
	if a.selected.String() != k.String() {
		return nil
	}
	return a.savedScope
}

// toggleSavedLists opens/closes the sublists pane (and loads the list).
func (a *App) toggleSavedLists(k chatKey) {
	a.mu.Lock()
	open := !a.savedListOpen
	a.savedListOpen = open
	a.mu.Unlock()
	if open {
		a.loadSavedSublists(k)
	}
	a.invalidate()
}

// loadSavedSublists fetches the account's sublists (and, for premium
// accounts, the reaction tags) through the engine (async — the pane
// shows an honest loading state meanwhile).
func (a *App) loadSavedSublists(k chatKey) {
	go func() {
		lists, _, err := a.eng.GetSavedSublists(k.AccountID, 100, 0, 0, false)
		a.mu.Lock()
		if err != nil {
			a.savedListsErr = err.Error()
			a.savedListsLoaded = false
		} else {
			a.savedLists = lists
			a.savedListsLoaded = true
			a.savedListsErr = ""
		}
		a.mu.Unlock()
		a.invalidate()
		// Reaction tags (slice 199): premium surface, fetched separately so
		// a tag-list failure never blocks the sublists.
		go func() {
			tags, err := a.eng.GetSavedReactionTags(k.AccountID, "")
			a.mu.Lock()
			if err == nil {
				a.savedTags = tags
				a.savedTagsLoaded = true
			} else {
				a.savedTags = nil
				a.savedTagsLoaded = false
			}
			a.mu.Unlock()
			a.invalidate()
		}()
	}()
}

// openSavedTag scopes the saved chat's view to one reaction tag (the
// server-side tag search — premium).
func (a *App) openSavedTag(emoji, title string) {
	a.mu.Lock()
	k := a.selected
	a.savedScope = &savedScopeState{title: title, tag: emoji}
	a.savedListOpen = false
	a.messages = nil
	a.loadingMsgs = true
	a.olderDone = false
	a.loadingOlder = false
	a.mu.Unlock()
	a.invalidate()
	if k == nil {
		return
	}
	go func() {
		msgs, err := a.eng.SearchSavedMessagesByReaction(k.AccountID, k.ChatID, "", []string{emoji}, 0, 100)
		if err != nil {
			a.setToast("Tag search: " + err.Error())
			return
		}
		for i, j := 0, len(msgs)-1; i < j; i, j = i+1, j-1 {
			msgs[i], msgs[j] = msgs[j], msgs[i]
		}
		a.mu.Lock()
		if sc := a.savedScope; sc != nil && sc.tag == emoji && a.selected != nil && *a.selected == *k {
			a.messages = msgs
			a.loadingMsgs = false
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// openSavedSublist scopes the saved chat's view to one sublist.
func (a *App) openSavedSublist(peerID, title string) {
	a.mu.Lock()
	k := a.selected
	a.savedScope = &savedScopeState{peerID: peerID, title: title}
	a.savedListOpen = false
	a.messages = nil
	a.loadingMsgs = true
	a.olderDone = false
	a.loadingOlder = false
	a.mu.Unlock()
	a.invalidate()
	if k == nil {
		return
	}
	go func() {
		msgs, err := a.eng.GetSavedSublistMessages(k.AccountID, k.ChatID, peerID, 0, 100)
		if err != nil {
			return
		}
		for i, j := 0, len(msgs)-1; i < j; i, j = i+1, j-1 {
			msgs[i], msgs[j] = msgs[j], msgs[i]
		}
		a.mu.Lock()
		if s := a.savedScope; s != nil && s.peerID == peerID && a.selected != nil && *a.selected == *k {
			a.messages = msgs
			a.loadingMsgs = false
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// closeSavedSublist returns to the whole saved-chat view.
func (a *App) closeSavedSublist() {
	a.mu.Lock()
	k := a.selected
	a.savedScope = nil
	a.messages = nil
	a.loadingMsgs = true
	a.mu.Unlock()
	a.invalidate()
	if k == nil {
		return
	}
	go a.refreshMessages()
}

// layoutSavedScopeBar: the open sublist's identity strip under the
// header (back → the whole saved chat).
func (a *App) layoutSavedScopeBar(gtx layout.Context, f frame) layout.Dimensions {
	if a.wid.savedBackBtn.Clicked(gtx) {
		a.closeSavedSublist()
	}
	title := "Saved messages"
	if s := f.savedScope; s != nil {
		if s.tag != "" {
			title = savedTagBarTitle(s.tag, s.title)
		} else {
			title = savedScopeBarTitle(s.title)
		}
	}
	return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4), Left: unit.Dp(8), Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.IconButton(&a.wid.savedBackBtn, iconNavigationBack, "Back to Saved Messages")
				btn.Color = a.ui.p.TextDim
				return btn.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Left: unit.Dp(4), Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return iconActionBookmark.Layout(gtx, a.ui.p.TextDim)
				})
			}),
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Label(unit.Sp(14), title)
				lbl.MaxLines = 1
				return lbl.Layout(gtx)
			}),
		)
	})
}

// layoutSavedListsPane renders the sublists sidebar column (the right
// pane while savedListOpen): "All messages" + one row per sublist, the
// honest loading/empty/error states below the title.
func (a *App) layoutSavedListsPane(gtx layout.Context, f frame) layout.Dimensions {
	// Slice 204: secondary-press routing (row context menu).
	a.processSavedListsEvents(gtx, f)
	lists := sortSavedSublists(f.savedLists)
	for len(a.wid.savedListRowBtns) < len(lists)+1 {
		a.wid.savedListRowBtns = append(a.wid.savedListRowBtns, widget.Clickable{})
	}
	a.savedListRowBounds = a.savedListRowBounds[:0]
	rows := make([]layout.FlexChild, 0, len(lists)+3)
	rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(6), Left: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.H3("Lists")
			return lbl.Layout(gtx)
		})
	}))
	if f.savedListsErr != "" {
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(16), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(13), "Couldn't load lists: "+f.savedListsErr)
				lbl.MaxLines = 2
				return lbl.Layout(gtx)
			})
		}))
	} else if !f.savedListsLoaded {
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(16)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(13), "Loading lists…")
					return lbl.Layout(gtx)
				})
			})
		}))
	} else if len(lists) == 0 {
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(16), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(13), "No lists yet — forward a message to Saved Messages to create one")
					lbl.MaxLines = 2
					return lbl.Layout(gtx)
				})
			})
		}))
	}
	// "All messages" row + one row per sublist (bounds tracked for the
	// row context menu — display rows 1..n map to lists[0..n-1]).
	for idx := 0; idx <= len(lists); idx++ {
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			dims := a.savedSublistRow(gtx, f, lists, idx)
			if idx > 0 {
				a.savedListRowBounds = append(a.savedListRowBounds, image.Rectangle{Max: dims.Size})
			}
			return dims
		}))
	}
	// Reaction tags (slice 199): the premium tag rows under their own
	// header — picking one scopes the view to the tagged messages.
	if f.selected != nil && tagsSectionVisible(accountByID(f, f.selected.AccountID).IsPremium, f.savedTags) {
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(10), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(12), "Tags")
						lbl.Color = a.ui.p.Accent
						return lbl.Layout(gtx)
					}),
				)
			})
		}))
		for i := range f.savedTags {
			i := i
			rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.savedTagRow(gtx, f, i)
			}))
		}
	}
	var menuDims layout.Dimensions
	if f.savedSublistMenu != nil {
		dims := layout.Stack{}.Layout(gtx,
			layout.Expanded(func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
			}),
			layout.Stacked(func(gtx layout.Context) layout.Dimensions {
				return a.layoutSavedSublistMenu(gtx, f)
			}),
		)
		menuDims = dims
	} else {
		menuDims = layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
	}
	return menuDims
}

// savedSublistRow renders one pane row: idx 0 = "All messages", else
// the (idx-1)th sublist (pinned glyph, title, preview).
func (a *App) savedSublistRow(gtx layout.Context, f frame, lists []cores.SavedSublistInfo, idx int) layout.Dimensions {
	btn := &a.wid.savedListRowBtns[idx]
	title, preview, pinned := "All messages", "every saved message", false
	if idx > 0 && idx-1 < len(lists) {
		l := lists[idx-1]
		title, preview, pinned = savedSublistRowTitle(l), savedSublistPreview(l), l.IsPinned
	}
	if btn.Clicked(gtx) {
		if idx == 0 {
			a.closeSavedSublist()
		} else {
			a.openSavedSublist(lists[idx-1].PeerID, savedSublistRowTitle(lists[idx-1]))
		}
		return layout.Dimensions{}
	}
	return layout.Inset{Left: unit.Dp(10), Right: unit.Dp(10), Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(10), Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							if idx == 0 {
								return drawBookmarkAvatar(gtx, a.ui, unit.Dp(40))
							}
							return a.ui.Avatar(gtx, title, unit.Dp(40), dotNone)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
									layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
										lbl := a.ui.Label(unit.Sp(14), title)
										lbl.MaxLines = 1
										return lbl.Layout(gtx)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										if !pinned {
											return layout.Dimensions{}
										}
										return layout.Inset{Left: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
											gtx.Constraints.Max.X = gtx.Dp(unit.Dp(14))
											gtx.Constraints.Min.X = gtx.Constraints.Max.X
											return iconActionBookmark.Layout(gtx, a.ui.p.Accent)
										})
									}),
								)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Dim(unit.Sp(11), preview)
									lbl.MaxLines = 1
									return lbl.Layout(gtx)
								})
							}),
						)
					}),
				)
			})
		})
	})
}

// savedTagRow renders one reaction-tag row: the emoji glyph, the tag
// name, and the count. Picking it scopes the view to the tagged
// messages (the server-side tag search).
func (a *App) savedTagRow(gtx layout.Context, f frame, idx int) layout.Dimensions {
	for len(a.wid.savedTagRowBtns) < len(f.savedTags) {
		a.wid.savedTagRowBtns = append(a.wid.savedTagRowBtns, widget.Clickable{})
	}
	tg := f.savedTags[idx]
	btn := &a.wid.savedTagRowBtns[idx]
	if btn.Clicked(gtx) {
		a.openSavedTag(tg.Emoji, savedTagRowLabel(tg))
		return layout.Dimensions{}
	}
	return layout.Inset{Left: unit.Dp(10), Right: unit.Dp(10), Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6), Left: unit.Dp(10), Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(18), tg.Emoji)
							return lbl.Layout(gtx)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(14), savedTagRowLabel(tg))
						lbl.MaxLines = 1
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if tg.Count <= 0 {
							return layout.Dimensions{}
						}
						return unreadBadge(gtx, a.ui, tg.Count, false)
					}),
				)
			})
		})
	})
}

// savedHeaderBtn renders the saved chat's "Lists" header button (the
// pane toggle — bookmark glyph; accent while the pane is open).
func (a *App) savedHeaderBtn(gtx layout.Context, f frame, k chatKey) layout.Dimensions {
	if a.wid.savedListBtn.Clicked(gtx) {
		a.toggleSavedLists(k)
	}
	return layout.Inset{Left: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		btn := a.ui.IconButton(&a.wid.savedListBtn, iconActionBookmark, "Saved lists")
		btn.Color = a.ui.p.TextDim
		if f.savedListOpen {
			btn.Color = a.ui.p.Accent
		}
		return btn.Layout(gtx)
	})
}

// ---- slice 204: row context menu (pin toggle / move / delete) ----

// savedListsPaneTag is the pointer-interest tag for the Lists pane
// (row context menu routing).
var savedListsPaneTag = new(struct{})

// savedSublistMenuTarget is the open row context menu (display-list row
// index + anchor point, callsbox-style).
type savedSublistMenuTarget struct {
	row int
	pos image.Point
}

// savedDelDlgState is the open delete-confirm dialog (nil when closed).
type savedDelDlgState struct {
	list cores.SavedSublistInfo
	busy bool
}

// savedSublistMenuActions (pure): the row menu entries. Pinned rows get
// the move entries bounded by the pinned-block edges; every row gets
// the pin toggle and the destructive delete.
func savedSublistMenuActions(pinned, canUp, canDown bool) []string {
	out := make([]string, 0, 4)
	if pinned {
		out = append(out, "Unpin")
		if canUp {
			out = append(out, "Move up")
		}
		if canDown {
			out = append(out, "Move down")
		}
	} else {
		out = append(out, "Pin")
	}
	return append(out, "Delete messages")
}

// savedSublistMovePeers (pure): the new pinned order after moving the
// row at display index row by delta (±1) within the pinned block.
// Edge moves (or unpinned rows) are no-ops — the input order returns.
func savedSublistMovePeers(lists []cores.SavedSublistInfo, row, delta int) []string {
	peers := make([]string, 0, len(lists))
	for _, l := range lists {
		if l.IsPinned {
			peers = append(peers, l.PeerID)
		}
	}
	pIdx := -1
	np := 0
	for i, l := range lists {
		if l.IsPinned {
			if i == row {
				pIdx = np
			}
			np++
		}
	}
	if pIdx < 0 || delta == 0 {
		return peers
	}
	target := pIdx + delta
	if target < 0 || target >= len(peers) {
		return peers
	}
	peers[pIdx], peers[target] = peers[target], peers[pIdx]
	return peers
}

// savedPinnedBlockBounds (pure): how many display rows are pinned, and
// whether the row at index row can move up/down within the block.
func savedPinnedBlockBounds(lists []cores.SavedSublistInfo) (pinned int) {
	for _, l := range lists {
		if l.IsPinned {
			pinned++
		}
	}
	return pinned
}

// processSavedListsEvents registers the pane pointer interest and routes
// secondary presses to the row context menu; any press outside an open
// menu dismisses it (the callsbox pattern).
func (a *App) processSavedListsEvents(gtx layout.Context, f frame) {
	stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
	event.Op(gtx.Ops, savedListsPaneTag)
	stack.Pop()
	for {
		ev, ok := gtx.Source.Event(pointer.Filter{Target: savedListsPaneTag, Kinds: pointer.Press})
		if !ok {
			break
		}
		if pe, is := ev.(pointer.Event); is && pe.Kind == pointer.Press {
			pos := image.Pt(int(pe.Position.X), int(pe.Position.Y))
			if f.savedSublistMenu != nil {
				if !pointInRect(pos, a.savedSublistMenuRect) {
					a.mu.Lock()
					a.savedSublistMenu = nil
					a.mu.Unlock()
					a.invalidate()
				}
				continue
			}
			if pe.Buttons != pointer.ButtonSecondary {
				continue
			}
			idx := -1
			for i, r := range a.savedListRowBounds {
				if pointInRect(pos, r) {
					idx = i
					break
				}
			}
			if idx < 0 || idx >= len(f.savedLists) {
				continue
			}
			a.mu.Lock()
			a.savedSublistMenu = &savedSublistMenuTarget{row: idx, pos: pos}
			a.mu.Unlock()
			a.invalidate()
		}
	}
}

// savedSublistAct runs one row-menu action (async engine call + reload).
func (a *App) savedSublistAct(k chatKey, lists []cores.SavedSublistInfo, row, action int) {
	acc := k.AccountID
	a.mu.Lock()
	if a.selected != nil {
		acc = a.selected.AccountID
	}
	a.mu.Unlock()
	if row < 0 || row >= len(lists) || acc == "" {
		return
	}
	l := lists[row]
	pinnedCount := savedPinnedBlockBounds(lists)
	actions := savedSublistMenuActions(l.IsPinned, row > 0 && row-1 < pinnedCount && pinnedCount > 1,
		row+1 < pinnedCount)
	if action < 0 || action >= len(actions) {
		return
	}
	switch actions[action] {
	case "Pin", "Unpin":
		go func() {
			_ = a.eng.ToggleSavedSublistPin(acc, l.PeerID, !l.IsPinned)
			a.loadSavedSublists(chatKey{AccountID: acc, ChatID: k.ChatID})
		}()
	case "Move up", "Move down":
		delta := 1
		if actions[action] == "Move up" {
			delta = -1
		}
		peers := savedSublistMovePeers(lists, row, delta)
		go func() {
			_ = a.eng.ReorderSavedSublists(acc, peers)
			a.loadSavedSublists(chatKey{AccountID: acc, ChatID: k.ChatID})
		}()
	case "Delete messages":
		a.mu.Lock()
		a.savedDelDlg = &savedDelDlgState{list: l}
		a.savedSublistMenu = nil
		a.mu.Unlock()
		a.invalidate()
	}
}

// submitSavedDelete confirms the delete dialog: engine call (the
// messages.deleteSavedHistory + local cache purge), reload, and if the
// open scope IS the deleted sublist, back out to the whole saved chat.
func (a *App) submitSavedDelete(k chatKey) {
	d := a.savedDelDlg
	if d == nil || d.busy {
		return
	}
	a.mu.Lock()
	a.savedDelDlg.busy = true
	a.mu.Unlock()
	a.invalidate()
	acc := k.AccountID
	a.mu.Lock()
	if a.selected != nil {
		acc = a.selected.AccountID
	}
	a.mu.Unlock()
	go func() {
		err := a.eng.DeleteSavedSublistHistory(acc, d.list.PeerID)
		a.mu.Lock()
		if err != nil {
			a.savedDelDlg.busy = false
		} else {
			a.savedDelDlg = nil
			if a.savedScope != nil && a.savedScope.peerID == d.list.PeerID {
				a.savedScope = nil
			}
		}
		a.mu.Unlock()
		a.loadSavedSublists(chatKey{AccountID: acc, ChatID: k.ChatID})
		a.invalidate()
	}()
}

// closeSavedDeleteDialog drops the confirm without acting.
func (a *App) closeSavedDeleteDialog() {
	a.mu.Lock()
	a.savedDelDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// layoutSavedSublistMenu renders the row context menu anchored at the
// press point (callsbox row-menu pattern).
func (a *App) layoutSavedSublistMenu(gtx layout.Context, f frame) layout.Dimensions {
	m := f.savedSublistMenu
	lists := sortSavedSublists(f.savedLists)
	if m.row < 0 || m.row >= len(lists) {
		return layout.Dimensions{}
	}
	l := lists[m.row]
	pinnedCount := savedPinnedBlockBounds(lists)
	actions := savedSublistMenuActions(l.IsPinned,
		m.row > 0 && m.row < pinnedCount && pinnedCount > 1,
		m.row+1 < pinnedCount)
	for len(a.wid.savedSublistMenuRows) < len(actions) {
		a.wid.savedSublistMenuRows = append(a.wid.savedSublistMenuRows, widget.Clickable{})
	}
	menuW := gtx.Dp(unit.Dp(210))
	rowH := gtx.Dp(unit.Dp(36))
	h := gtx.Dp(unit.Dp(8)) + len(actions)*rowH + gtx.Dp(unit.Dp(8))
	pos := m.pos
	if pos.X+menuW > gtx.Constraints.Max.X {
		pos.X = gtx.Constraints.Max.X - menuW
	}
	if pos.Y+h > gtx.Constraints.Max.Y {
		pos.Y = gtx.Constraints.Max.Y - h
	}
	if pos.X < 0 {
		pos.X = 0
	}
	if pos.Y < 0 {
		pos.Y = 0
	}
	a.savedSublistMenuRect = image.Rect(pos.X, pos.Y, pos.X+menuW, pos.Y+h)
	k := chatKey{}
	if f.selected != nil {
		k = *f.selected
	}
	for i := range actions {
		if a.wid.savedSublistMenuRows[i].Clicked(gtx) {
			a.mu.Lock()
			a.savedSublistMenu = nil
			a.mu.Unlock()
			a.savedSublistAct(k, lists, m.row, i)
			return layout.Dimensions{}
		}
	}
	var dims layout.Dimensions
	func() {
		defer op.Offset(pos).Push(gtx.Ops).Pop()
		gtx.Constraints = layout.Constraints{Max: image.Pt(menuW, h), Min: image.Pt(menuW, h)}
		dims = roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
			children := make([]layout.FlexChild, 0, len(actions)+2)
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Dimensions{Size: image.Pt(menuW, gtx.Dp(unit.Dp(4)))}
				})
			}))
			for i, label := range actions {
				i, label := i, label
				children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := &a.wid.savedSublistMenuRows[i]
					gtx.Constraints.Min.Y = rowH
					return material.ButtonLayout(a.ui.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.UniformInset(unit.Dp(9)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(14), label)
							if label == "Delete messages" {
								lbl.Color = a.ui.p.Error
							} else {
								lbl.Color = a.ui.p.Text
							}
							return lbl.Layout(gtx)
						})
					})
				}))
			}
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Dimensions{Size: image.Pt(menuW, gtx.Dp(unit.Dp(4)))}
				})
			}))
			layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
			return layout.Dimensions{Size: image.Pt(menuW, h)}
		})
	}()
	return dims
}

// layoutSavedDeleteDialog: the destructive-action confirm card (the
// slice-190 clear-history box pattern).
func (a *App) layoutSavedDeleteDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.savedDelDlg
	if a.wid.savedDelCancel.Clicked(gtx) {
		a.closeSavedDeleteDialog()
	}
	if a.wid.savedDelOK.Clicked(gtx) {
		k := chatKey{}
		if f.selected != nil {
			k = *f.selected
		}
		a.submitSavedDelete(k)
	}
	paintScrimRect(gtx)
	label := "Delete"
	if d.busy {
		label = "Deleting…"
	}
	title := savedSublistRowTitle(d.list)
	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(320))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.ui.H3("Delete messages?").Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(13), "All messages saved from "+title+" will be deleted. This can't be undone.")
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									btn := material.Button(a.ui.Theme, &a.wid.savedDelCancel, "Cancel")
									btn.Background = a.ui.p.SurfaceHi
									btn.Color = a.ui.p.Text
									return btn.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
										btn := material.Button(a.ui.Theme, &a.wid.savedDelOK, label)
										btn.Background = a.ui.p.Error
										return btn.Layout(gtx)
									})
								}),
							)
						})
					}),
				)
			})
		})
	})
}
