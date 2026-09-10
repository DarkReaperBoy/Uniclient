package gui

import (
	"log"
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Global search (AyuGram parity §1 "Global search", top-gap #12): while the
// sidebar search field has a query, the list shows local chat matches plus
// cross-account message hits (engine SearchMessages, FTS5) and per-account
// server chat results (engine SearchGlobalChats). Tapping a message result
// opens its chat and jumps to it; global results open through the engine's
// cache-then-core fallback. Everything is engine-backed (§1.10).

// sidebar search row kinds.
const (
	sbRowChat = iota
	sbRowHeader
	sbRowMsg
	sbRowGlobal
	sbRowInvite
)

// sbRow is one row of the search-augmented sidebar list.
type sbRow struct {
	kind    int
	chatIdx int                  // sbRowChat: index into visible chats
	listIdx int                  // sbRowMsg/sbRowGlobal: index into that list
	msg     *engine.SearchResult // sbRowMsg
	gchat   *engine.ChatInfo     // sbRowGlobal
	title   string               // sbRowHeader / sbRowInvite (hash)
}

// buildSearchRows builds the sidebar list rows for an active search:
// [Chats header + local matches] [Messages header + message hits]
// [Global header + server chat hits]. Pure — unit-tested.
func buildSearchRows(visible []engine.ChatInfo, msgs []engine.SearchResult, global []engine.ChatInfo, acctFilter string) []sbRow {
	var rows []sbRow
	if len(visible) > 0 {
		rows = append(rows, sbRow{kind: sbRowHeader, title: "Chats"})
		for i := range visible {
			rows = append(rows, sbRow{kind: sbRowChat, chatIdx: i})
		}
	}
	if len(msgs) > 0 {
		rows = append(rows, sbRow{kind: sbRowHeader, title: "Messages"})
		for i := range msgs {
			m := msgs[i]
			rows = append(rows, sbRow{kind: sbRowMsg, msg: &m, listIdx: i})
		}
	}
	if len(global) > 0 {
		rows = append(rows, sbRow{kind: sbRowHeader, title: "Global results"})
		for i := range global {
			g := global[i]
			rows = append(rows, sbRow{kind: sbRowGlobal, gchat: &g, listIdx: i})
		}
	}
	return rows
}

// searchGlobalScope filters global results to the scoped account (results
// arrive per-account; the unified list shows all).
func searchGlobalScope(global []engine.ChatInfo, acctFilter string) []engine.ChatInfo {
	if acctFilter == "" {
		return global
	}
	out := make([]engine.ChatInfo, 0, len(global))
	for _, c := range global {
		if c.AccountID == acctFilter {
			out = append(out, c)
		}
	}
	return out
}

// ── results tabs (AyuGram search-results screen, slice 57) ─────────────────

// Search-result tabs: All (unified sections, previous behavior), Chats
// (local + server chat hits), Messages (text hits), Links / Files (message
// hits filtered engine-side by URL / media presence).
const (
	searchTabAll = iota
	searchTabChats
	searchTabMsgs
	searchTabLinks
	searchTabFiles
)

var searchTabLabels = [...]string{"All", "Chats", "Messages", "Links", "Files"}

// searchTabKind maps a tab to the engine message-kind filter ("" = none).
func searchTabKind(tab int) string {
	switch tab {
	case searchTabLinks:
		return engine.SearchFilterLinks
	case searchTabFiles:
		return engine.SearchFilterFiles
	}
	return ""
}

// filterSearchRows narrows built rows to one tab's sections (the invite
// row survives everywhere). Pure — unit-tested.
func filterSearchRows(rows []sbRow, tab int) []sbRow {
	if tab == searchTabAll {
		return rows
	}
	keepChat := tab == searchTabChats
	keepMsg := tab == searchTabMsgs || tab == searchTabLinks || tab == searchTabFiles
	out := make([]sbRow, 0, len(rows))
	headerFor := -1 // -1: none pending, -2: emitted
	for _, r := range rows {
		switch r.kind {
		case sbRowInvite:
			out = append(out, r)
		case sbRowHeader:
			headerFor = -2
			if (keepChat && (r.title == "Chats" || r.title == "Global results")) ||
				(keepMsg && r.title == "Messages") {
				headerFor = len(out)
				out = append(out, r)
			}
		case sbRowChat, sbRowGlobal:
			if keepChat && headerFor != -2 {
				out = append(out, r)
			}
		case sbRowMsg:
			if keepMsg && headerFor != -2 {
				out = append(out, r)
			}
		}
	}
	return out
}

// ── state transitions ─────────────────────────────────────────────────────

// onSearchChanged (GUI goroutine, from the search field's ChangeEvents)
// kicks the async engine search; results land only if the query still
// matches (stale runs are dropped).
func (a *App) onSearchChanged(q string) {
	q = strings.TrimSpace(q)
	if len([]rune(q)) < 2 {
		a.mu.Lock()
		a.searchMsgs = nil
		a.searchGlobal = nil
		a.searchFor = q
		a.mu.Unlock()
		return
	}
	a.mu.Lock()
	a.searchFor = q
	acct := a.acctFilter
	accounts := make([]string, 0, len(a.accounts))
	for _, acc := range a.accounts {
		accounts = append(accounts, acc.ID)
	}
	a.mu.Unlock()

	a.mu.Lock()
	tab := a.searchTab
	a.mu.Unlock()

	go func() {
		msgs, errM := a.eng.SearchMessagesEx(q, acct, 30, "", "", "", searchTabKind(tab))
		if errM != nil {
			log.Printf("gui: search messages: %v", errM)
			msgs = nil
		}
		a.mu.Lock()
		if a.searchFor == q {
			a.searchMsgs = msgs
		}
		a.mu.Unlock()
		a.invalidate()

		var global []engine.ChatInfo
		for _, accID := range accounts {
			if acct != "" && accID != acct {
				continue
			}
			found, err := a.eng.SearchGlobalChats(accID, q, 8)
			if err != nil {
				continue // per-account: server search is best-effort
			}
			global = append(global, found...)
		}
		a.mu.Lock()
		if a.searchFor == q {
			a.searchGlobal = global
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// setSearchTab switches the results tab and re-runs the message search
// (links/files hits come from the engine kind filter).
func (a *App) setSearchTab(tab int) {
	a.mu.Lock()
	if a.searchTab == tab {
		a.mu.Unlock()
		return
	}
	a.searchTab = tab
	q := a.searchFor
	a.mu.Unlock()
	a.invalidate()
	if q != "" {
		a.onSearchChanged(q)
	}
}

// openSearchResult opens the chat for a message hit and jumps to it.
func (a *App) openSearchResult(r engine.SearchResult) {
	k := chatKey{AccountID: r.AccountID, ChatID: r.ChatID}
	title := r.ChatTitle
	if title == "" {
		title = r.SenderName
	}
	a.openChat(k, title)
	a.jumpToMessageAt(r.MsgID, r.Timestamp)
}

// openGlobalResult opens a server-side chat hit.
func (a *App) openGlobalResult(c engine.ChatInfo) {
	k := chatKey{AccountID: c.AccountID, ChatID: c.ChatID}
	a.openChat(k, c.Title)
}

// ── layouts ────────────────────────────────────────────────────────────────

// searchSectionHeader renders a "Chats / Messages / Global" label row.
func (a *App) searchSectionHeader(gtx layout.Context, title string) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(10), Bottom: unit.Dp(4), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Label(unit.Sp(11), strings.ToUpper(title))
			lbl.Color = a.ui.p.TextFaint
			return lbl.Layout(gtx)
		})
}

// searchMsgRow renders one message hit: chat/sender + snippet + time.
func (a *App) searchMsgRow(gtx layout.Context, btn *widget.Clickable, r engine.SearchResult) layout.Dimensions {
	title := r.ChatTitle
	if title == "" {
		title = r.SenderName
	}
	if title == "" {
		title = "Message"
	}
	return material.ButtonLayout(a.ui.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return a.ui.Avatar(gtx, title, unit.Dp(38), dotNone)
					})
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Label(unit.Sp(14), title)
									lbl.MaxLines = 1
									return lbl.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									t := a.ui.Dim(unit.Sp(11), fmtTime(r.Timestamp))
									t.Color = a.ui.p.TextFaint
									return t.Layout(gtx)
								}),
							)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(13), quotePreview(r.Text, 64))
								lbl.Color = a.ui.p.TextDim
								lbl.MaxLines = 1
								return lbl.Layout(gtx)
							})
						}),
					)
				}),
			)
		})
	})
}

// searchGlobalRow renders one server-side chat hit (with a "server" tag).
func (a *App) searchGlobalRow(gtx layout.Context, btn *widget.Clickable, c engine.ChatInfo, platform string) layout.Dimensions {
	return material.ButtonLayout(a.ui.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return a.ui.Avatar(gtx, c.Title, unit.Dp(38), dotNone)
					})
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(14), c.Title)
							lbl.MaxLines = 1
							return lbl.Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), "Found on "+platform)
								lbl.Color = a.ui.p.TextFaint
								return lbl.Layout(gtx)
							})
						}),
					)
				}),
			)
		})
	})
}

// searchTabBtns pools the result-tab pills.
var searchTabBtns []widget.Clickable

// layoutSearchTabs renders the result filter bar (All/Chats/Messages/
// Links/Files) — shown while a query is active.
func (a *App) layoutSearchTabs(gtx layout.Context, f frame) layout.Dimensions {
	if f.search == "" {
		return layout.Dimensions{}
	}
	growClickables(&searchTabBtns, len(searchTabLabels))
	return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		children := make([]layout.FlexChild, 0, len(searchTabLabels))
		for i, label := range searchTabLabels {
			i, label := i, label
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := &searchTabBtns[i]
				if btn.Clicked(gtx) {
					a.setSearchTab(i)
				}
				active := f.searchTab == i
				b := material.Button(a.ui.Theme, btn, label)
				b.Background = a.ui.p.Surface
				b.Color = a.ui.p.TextDim
				b.TextSize = unit.Sp(12)
				b.CornerRadius = 12
				b.Inset = layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4), Left: unit.Dp(8), Right: unit.Dp(8)}
				if active {
					b.Background = a.ui.p.AccentDim
					b.Color = a.ui.p.Text
				}
				return layout.Inset{Right: unit.Dp(4)}.Layout(gtx, b.Layout)
			}))
		}
		return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, children...)
	})
}
