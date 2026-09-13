package gui

import (
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"

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

// sortSavedSublists: pinned rows first, then by last activity (newest
// first) — tdesktop's saved-dialogs order. Pure — locked by tests.
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
	sortSavedByTimeDesc(pinned)
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
	lists := sortSavedSublists(f.savedLists)
	for len(a.wid.savedListRowBtns) < len(lists)+1 {
		a.wid.savedListRowBtns = append(a.wid.savedListRowBtns, widget.Clickable{})
	}
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
	// "All messages" row + one row per sublist.
	for idx := 0; idx <= len(lists); idx++ {
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.savedSublistRow(gtx, f, lists, idx)
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
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
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
