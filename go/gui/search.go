package gui

import (
	"log"
	"strings"
	"unicode/utf8"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

const (
	sbRowChat = iota
	sbRowHeader
	sbRowMsg
	sbRowGlobal
	sbRowInvite
)

type sbRow struct {
	kind    int
	chatIdx int
	listIdx int
	msg     *engine.SearchResult
	gchat   *engine.ChatInfo
	title   string
}

func buildSearchRows(visible []engine.ChatInfo, msgs []engine.SearchResult, posts []engine.SearchResult, global []engine.ChatInfo, acctFilter string) []sbRow {
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
	if len(posts) > 0 {
		rows = append(rows, sbRow{kind: sbRowHeader, title: "Posts"})
		for i := range posts {
			p := posts[i]
			rows = append(rows, sbRow{kind: sbRowMsg, msg: &p, listIdx: i})
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

func postsSearchQuery(q string) bool {
	if len(q) < 2 || q[0] != '#' {
		return false
	}
	r, size := utf8.DecodeRuneInString(q[1:])
	return size > 0 && r != ' ' && r != '\t' && r != '\n'
}

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

const (
	searchTabAll = iota
	searchTabChats
	searchTabMsgs
	searchTabLinks
	searchTabFiles
)

var searchTabLabels = [...]string{"All", "Chats", "Messages", "Links", "Files"}

func searchTabKind(tab int) string {
	switch tab {
	case searchTabLinks:
		return engine.SearchFilterLinks
	case searchTabFiles:
		return engine.SearchFilterFiles
	}
	return ""
}

func filterSearchRows(rows []sbRow, tab int) []sbRow {
	if tab == searchTabAll {
		return rows
	}
	keepChat := tab == searchTabChats
	keepMsg := tab == searchTabMsgs || tab == searchTabLinks || tab == searchTabFiles
	keepPosts := tab == searchTabMsgs
	out := make([]sbRow, 0, len(rows))
	headerFor := -1
	for _, r := range rows {
		switch r.kind {
		case sbRowInvite:
			out = append(out, r)
		case sbRowHeader:
			headerFor = -2
			if (keepChat && (r.title == "Chats" || r.title == "Global results")) ||
				(keepMsg && r.title == "Messages") ||
				(keepPosts && r.title == "Posts") {
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

func (a *App) onSearchChanged(q string) {
	q = strings.TrimSpace(q)
	if len([]rune(q)) < 2 {
		a.mu.Lock()
		a.searchMsgs = nil
		a.searchPosts = nil
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
				continue
			}
			global = append(global, found...)
		}
		a.mu.Lock()
		if a.searchFor == q {
			a.searchGlobal = global
		}
		a.mu.Unlock()
		a.invalidate()

		if postsSearchQuery(q) {
			var posts []engine.SearchResult
			for _, accID := range accounts {
				if acct != "" && accID != acct {
					continue
				}
				hits, err := a.eng.SearchGlobalPostMessages(accID, q, 20)
				if err != nil {
					continue
				}
				posts = append(posts, hits...)
			}
			a.mu.Lock()
			if a.searchFor == q {
				a.searchPosts = posts
			}
			a.mu.Unlock()
			a.invalidate()
		}
	}()
}

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

func (a *App) openSearchResult(r engine.SearchResult) {
	k := chatKey{AccountID: r.AccountID, ChatID: r.ChatID}
	title := r.ChatTitle
	if title == "" {
		title = r.SenderName
	}
	a.openChat(k, title)
	a.jumpToMessageAt(r.MsgID, r.Timestamp)
}

func (a *App) openGlobalResult(c engine.ChatInfo) {
	k := chatKey{AccountID: c.AccountID, ChatID: c.ChatID}
	a.openChat(k, c.Title)
}

func (a *App) searchSectionHeader(gtx layout.Context, title string) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(10), Bottom: unit.Dp(4), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Label(unit.Sp(11), strings.ToUpper(title))
			lbl.Color = a.ui.p.TextFaint
			return lbl.Layout(gtx)
		})
}

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

var searchTabBtns []widget.Clickable

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
