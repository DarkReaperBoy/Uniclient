package gui

import (
	"image"
	"image/color"
	"strings"

	"gioui.org/font"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Sidebar widgets (created once, reused every frame).
var (
	sidebarSearch      widget.Editor
	sidebarAddBtn      widget.Clickable
	sidebarChatsList   widget.List
	sidebarFolderTabs  widget.List
	chatListBtns       []widget.Clickable // one per visible chat row
	accountSwitchBtn   widget.Clickable
	accountMenuBtns    []widget.Clickable
	accountMenuOpen    bool
	accountMenuRemove  []widget.Clickable
	sidebarModeChatBtn widget.Clickable
	sidebarModeVoiceBt widget.Clickable
	sidebarSettingsBtn widget.Clickable
)

func init() {
	sidebarSearch.SingleLine = true
	sidebarChatsList.Axis = layout.Vertical
	sidebarFolderTabs.Axis = layout.Horizontal
}

// layoutSidebar: account bar, mode tabs, search, folder tabs, chat list.
func (a *App) layoutSidebar(gtx layout.Context, f frame, narrow bool) layout.Dimensions {
	// Route sidebar presses (chat-row context menu, menu dismissal).
	a.processSidebarEvents(gtx, f)

	// Pre-size the per-row clickables.
	visible := filterChats(f)
	for len(chatListBtns) < len(visible) {
		chatListBtns = append(chatListBtns, widget.Clickable{})
	}

	// Reset this frame's row-bounds bookkeeping; filled by layoutChatList.
	a.chatRowBounds = make(map[int]image.Rectangle, len(visible))
	a.sbVisible = visible
	a.sbAboveList = 0

	record := func(fn func(gtx layout.Context) layout.Dimensions) func(gtx layout.Context) layout.Dimensions {
		return func(gtx layout.Context) layout.Dimensions {
			d := fn(gtx)
			a.sbAboveList += d.Size.Y
			return d
		}
	}

	dims := layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		// Account bar (+ dropdown menu when open)
		layout.Rigid(record(func(gtx layout.Context) layout.Dimensions {
			barFn := a.layoutAccountBar(gtx, f)
			if !accountMenuOpen || len(f.accounts) == 0 {
				return barFn(gtx)
			}
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
				layout.Rigid(barFn),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.accountMenu(gtx, f)
				}),
			)
		})),
		// Chat / Voice mode tabs
		layout.Rigid(record(func(gtx layout.Context) layout.Dimensions {
			return a.layoutModeTabs(gtx, f)
		})),
		// Search
		layout.Rigid(record(func(gtx layout.Context) layout.Dimensions {
			return insetAll(gtx, unit.Dp(8), unit.Dp(12), 4, unit.Dp(12), func(gtx layout.Context) layout.Dimensions {
				return a.searchField(gtx, f)
			})
		})),
		// Folder tabs
		layout.Rigid(record(func(gtx layout.Context) layout.Dimensions {
			return a.layoutFolders(gtx, f)
		})),
		// Chat list (scrollable)
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			return a.layoutChatList(gtx, f, visible)
		}),
	)

	// Chat-row context menu on top of the sidebar.
	if f.chatMenu != nil {
		a.layoutChatMenu(gtx, f)
	}
	return dims
}

// layoutAccountBar: current account (avatar+name+conn dot) + add button +
// dropdown menu for account switching/removal.
func (a *App) layoutAccountBar(gtx layout.Context, f frame) func(gtx layout.Context) layout.Dimensions {
	return func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(8), Left: unit.Dp(12), Right: unit.Dp(8), Bottom: unit.Dp(4)}.Layout(gtx,
			func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					// account switcher (opens menu)
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						current := currentAccount(f)
						accBtn := &accountSwitchBtn
						if accBtn.Clicked(gtx) {
							accountMenuOpen = !accountMenuOpen
						}
						return material.ButtonLayout(a.ui.Theme, accBtn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							gtx.Constraints.Min.X = 0
							return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									name := accountName(current)
									return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
										return a.ui.Avatar(gtx, name, unit.Dp(38), connDotFor(current))
									})
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											lbl := a.ui.H3(accountName(current))
											return lbl.Layout(gtx)
										}),
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											lbl := a.ui.Dim(unit.Sp(12), accountSubtitle(current, f))
											return lbl.Layout(gtx)
										}),
									)
								}),
							)
						})
					}),
					// add-account button
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if sidebarAddBtn.Clicked(gtx) {
							a.mu.Lock()
							a.showPicker = true
							a.mu.Unlock()
							a.invalidate()
						}
						btn := a.ui.IconButton(&sidebarAddBtn, iconContentAdd, "Add account")
						btn.Color = a.ui.p.Accent
						return btn.Layout(gtx)
					}),
					// settings (gear) — AyuGram settings entry
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if sidebarSettingsBtn.Clicked(gtx) {
							a.openSettings(setSectionMain)
						}
						btn := a.ui.IconButton(&sidebarSettingsBtn, iconActionSettings, "Settings")
						btn.Color = a.ui.p.TextDim
						return btn.Layout(gtx)
					}),
				)
			},
		)
	}
}

// accountMenu: dropdown listing accounts (click = filter list to that
// account; trash button = remove) + "All accounts" reset row.
func (a *App) accountMenu(gtx layout.Context, f frame) layout.Dimensions {
	for len(accountMenuBtns) < len(f.accounts)+1 {
		accountMenuBtns = append(accountMenuBtns, widget.Clickable{})
	}
	for len(accountMenuRemove) < len(f.accounts) {
		accountMenuRemove = append(accountMenuRemove, widget.Clickable{})
	}
	// Row 0: All accounts (clears filter).
	if accountMenuBtns[0].Clicked(gtx) {
		a.mu.Lock()
		a.acctFilter = ""
		a.folder = 0
		a.mu.Unlock()
		accountMenuOpen = false
		a.invalidate()
	}
	for i, acc := range f.accounts {
		if accountMenuBtns[i+1].Clicked(gtx) {
			a.mu.Lock()
			if a.acctFilter == acc.ID {
				a.acctFilter = ""
			} else {
				a.acctFilter = acc.ID
			}
			a.folder = 0
			scope := a.acctFilter
			a.mu.Unlock()
			a.refreshFolders(scope)
			accountMenuOpen = false
			a.invalidate()
		}
		if accountMenuRemove[i].Clicked(gtx) {
			accountMenuOpen = false
			a.removeAccount(acc.ID)
		}
	}

	rows := make([]layout.FlexChild, 0, len(f.accounts)+1)
	rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		active := f.acctFilter == ""
		lbl := a.ui.Label(unit.Sp(14), "All accounts")
		if active {
			lbl.Color = a.ui.p.Accent
		}
		return menuRow(gtx, a.ui, &accountMenuBtns[0], lbl)
	}))
	for i, acc := range f.accounts {
		i, acc := i, acc
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					active := f.acctFilter == acc.ID
					lbl := a.ui.Label(unit.Sp(14), accountName(acc)+"  ·  "+platformTitle(acc.Platform))
					if active {
						lbl.Color = a.ui.p.Accent
					}
					return menuRow(gtx, a.ui, &accountMenuBtns[i+1], lbl)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.IconButton(&accountMenuRemove[i], iconActionDelete, "Remove account")
					btn.Color = a.ui.p.Error
					btn.Size = unit.Dp(18)
					return btn.Layout(gtx)
				}),
			)
		}))
	}
	return layout.Inset{Left: unit.Dp(8), Right: unit.Dp(8), Top: unit.Dp(2), Bottom: unit.Dp(6)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
				})
			})
		})
}

// menuRow: a flat clickable row.
func menuRow(gtx layout.Context, u *UI, btn *widget.Clickable, lbl material.LabelStyle) layout.Dimensions {
	return material.ButtonLayout(u.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Min.X = 0
		return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6), Left: unit.Dp(10), Right: unit.Dp(10)}.Layout(gtx, lbl.Layout)
	})
}

// layoutModeTabs: Chat | Voice segmented control.
func (a *App) layoutModeTabs(gtx layout.Context, f frame) layout.Dimensions {
	if sidebarModeChatBtn.Clicked(gtx) {
		a.mu.Lock()
		a.mode = 0
		a.mu.Unlock()
		a.invalidate()
	}
	if sidebarModeVoiceBt.Clicked(gtx) {
		a.mu.Lock()
		a.mode = 1
		a.mu.Unlock()
		a.invalidate()
	}
	return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return segControl(gtx, a.ui, [2]segItem{
			{label: "Chats", icon: iconCommunicationChat, active: f.mode == 0, btn: &sidebarModeChatBtn},
			{label: "Voice", icon: iconHardwareHeadset, active: f.mode == 1, btn: &sidebarModeVoiceBt},
		})
	})
}

type segItem struct {
	label  string
	icon   *widget.Icon
	active bool
	btn    *widget.Clickable
}

// segControl renders a rounded segmented control.
func segControl(gtx layout.Context, u *UI, items [2]segItem) layout.Dimensions {
	h := gtx.Dp(unit.Dp(40))
	return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			return roundedFill(gtx, u.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
				gtx.Constraints.Max.Y = h
				return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return segCell(gtx, u, items[0])
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return segCell(gtx, u, items[1])
					}),
				)
			})
		}),
	)
}

func segCell(gtx layout.Context, u *UI, it segItem) layout.Dimensions {
	bg := u.p.Surface
	if it.active {
		bg = u.p.AccentDim
	}
	return roundedFill(gtx, bg, 10, func(gtx layout.Context) layout.Dimensions {
		return material.ButtonLayout(u.Theme, it.btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			gtx.Constraints.Min = gtx.Constraints.Max
			return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := u.Label(unit.Sp(14), it.label)
				if it.active {
					lbl.Color = u.p.Text
					lbl.Font.Weight = font.SemiBold
				} else {
					lbl.Color = u.p.TextDim
				}
				return lbl.Layout(gtx)
			})
		})
	})
}

func (a *App) searchField(gtx layout.Context, f frame) layout.Dimensions {
	// Update search state from editor.
	for {
		ev, ok := sidebarSearch.Update(gtx)
		if !ok {
			break
		}
		switch ev.(type) {
		case widget.ChangeEvent:
			a.mu.Lock()
			a.search = sidebarSearch.Text()
			a.mu.Unlock()
			a.invalidate()
		}
	}
	ed := a.ui.Editor(&sidebarSearch, "Search")
	return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(9), Bottom: unit.Dp(9), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, ed.Layout)
	})
}

// layoutFolders: horizontal scrollable folder tabs (AyuGram parity).
// Right-clicking a real server folder tab opens the folder editor (the tab
// bounds recorded here feed the sidebar press routing).
func (a *App) layoutFolders(gtx layout.Context, f frame) layout.Dimensions {
	// Real server folders when an account is scoped and its core supports
	// them; smart fallback tabs otherwise (AyuGram parity §2).
	tabs := buildFolderTabs(f.acctFilter, f.folders, f.foldersSupported)
	for len(folderBtns) < len(tabs) {
		folderBtns = append(folderBtns, widget.Clickable{})
	}
	for i := range tabs {
		if folderBtns[i].Clicked(gtx) {
			if tabs[i].kind == folderTabNew {
				a.openFolderDlg()
			} else {
				a.mu.Lock()
				a.folder = i
				a.mu.Unlock()
				a.invalidate()
			}
		}
	}
	// Tab bounds in sidebar-pane coords (y fixed by the accumulated layout,
	// x scrolled with the tab list).
	tabY := a.sbAboveList
	tabH := gtx.Dp(unit.Dp(30))
	a.sbTabBounds = a.sbTabBounds[:0]
	x := -sidebarFolderTabs.Position.Offset
	list := material.List(a.ui.Theme, &sidebarFolderTabs)
	dims := list.Layout(gtx, len(tabs), func(gtx layout.Context, i int) layout.Dimensions {
		d := layout.Inset{Left: unit.Dp(4), Right: unit.Dp(4), Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			active := f.folder == i && tabs[i].kind != folderTabNew
			return layoutFolderTab(gtx, a, &folderBtns[i], tabs[i], active)
		})
		a.sbTabBounds = append(a.sbTabBounds, image.Rect(x, tabY, x+d.Size.X, tabY+d.Size.Y))
		x += d.Size.X
		return d
	})
	_ = tabH
	return dims
}

var folderBtns []widget.Clickable

// search-result row clickables (slice 16).
var (
	searchMsgBtns    []widget.Clickable
	searchGlobalBtns []widget.Clickable
)

// filterChats applies folder + search.
func filterChats(f frame) []engine.ChatInfo {
	q := strings.ToLower(strings.TrimSpace(f.search))
	tabs := buildFolderTabs(f.acctFilter, f.folders, f.foldersSupported)
	tab := folderTab{kind: folderTabAll}
	if f.folder >= 0 && f.folder < len(tabs) {
		tab = tabs[f.folder]
	}
	out := make([]engine.ChatInfo, 0, len(f.chats))
	for _, c := range f.chats {
		if f.acctFilter != "" && c.AccountID != f.acctFilter {
			continue
		}
		if !tabMatches(tab, c) {
			continue
		}
		if q != "" && !strings.Contains(strings.ToLower(c.Title), q) &&
			!strings.Contains(strings.ToLower(c.LastMsgText), q) {
			continue
		}
		out = append(out, c)
	}
	return out
}

// layoutChatList: the scrolling list of chat rows + loading/empty states.
func (a *App) layoutChatList(gtx layout.Context, f frame, visible []engine.ChatInfo) layout.Dimensions {
	if len(f.accounts) == 0 {
		return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(14), "Add an account to get started (+)")
			lbl.Color = a.ui.p.TextFaint
			return lbl.Layout(gtx)
		})
	}
	if len(visible) == 0 {
		return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(14), "No chats here")
			lbl.Color = a.ui.p.TextFaint
			return lbl.Layout(gtx)
		})
	}

	// Click handling.
	for i := range visible {
		if i < len(chatListBtns) && chatListBtns[i].Clicked(gtx) {
			c := visible[i]
			k := chatKey{c.AccountID, c.ChatID}
			a.mu.Lock()
			a.folder = f.folder // keep
			a.mu.Unlock()
			a.openChat(k, c.Title)
		}
	}

	// Global search: message + server-chat result sections under the local
	// matches (slice 16).
	global := searchGlobalScope(f.searchGlobal, f.acctFilter)
	rows := buildSearchRows(visible, f.searchMsgs, global, f.acctFilter)
	if len(rows) != len(visible) {
		growClickables(&searchMsgBtns, len(f.searchMsgs))
		growClickables(&searchGlobalBtns, len(global))
		for i := range f.searchMsgs {
			if searchMsgBtns[i].Clicked(gtx) {
				r := f.searchMsgs[i]
				a.openSearchResult(r)
			}
		}
		for i := range global {
			if searchGlobalBtns[i].Clicked(gtx) {
				c := global[i]
				a.openGlobalResult(c)
			}
		}
		list := material.List(a.ui.Theme, &sidebarChatsList)
		y := a.sbAboveList - sidebarChatsList.Position.Offset
		paneW := gtx.Constraints.Max.X
		chatIdx := 0
		dims := list.Layout(gtx, len(rows), func(gtx layout.Context, i int) layout.Dimensions {
			r := rows[i]
			var d layout.Dimensions
			switch r.kind {
			case sbRowHeader:
				d = a.searchSectionHeader(gtx, r.title)
			case sbRowChat:
				c := visible[r.chatIdx]
				selected := f.selected != nil && f.selected.AccountID == c.AccountID && f.selected.ChatID == c.ChatID
				d = a.chatRow(gtx, f, c, selected, &chatListBtns[r.chatIdx])
				a.chatRowBounds[r.chatIdx] = image.Rectangle{Min: image.Pt(0, y), Max: image.Pt(paneW, y+d.Size.Y)}
				chatIdx++
			case sbRowMsg:
				d = a.searchMsgRow(gtx, &searchMsgBtns[r.listIdx], *r.msg)
			case sbRowGlobal:
				d = a.searchGlobalRow(gtx, &searchGlobalBtns[r.listIdx], *r.gchat, platformOf(f, r.gchat.AccountID))
			}
			y += d.Size.Y
			return d
		})
		return dims
	}

	list := material.List(a.ui.Theme, &sidebarChatsList)
	y := a.sbAboveList - sidebarChatsList.Position.Offset
	paneW := gtx.Constraints.Max.X
	dims := list.Layout(gtx, len(visible), func(gtx layout.Context, i int) layout.Dimensions {
		c := visible[i]
		selected := f.selected != nil && f.selected.AccountID == c.AccountID && f.selected.ChatID == c.ChatID
		d := a.chatRow(gtx, f, c, selected, &chatListBtns[i])
		a.chatRowBounds[i] = image.Rectangle{Min: image.Pt(0, y), Max: image.Pt(paneW, y+d.Size.Y)}
		y += d.Size.Y
		return d
	})
	return dims
}

// chatRow: avatar, title, last message, time, unread badge, typing indicator.
func (a *App) chatRow(gtx layout.Context, f frame, c engine.ChatInfo, selected bool, btn *widget.Clickable) layout.Dimensions {
	bg := color00
	if selected {
		bg = a.ui.p.AccentDim
	} else if btn.Hovered() {
		bg = a.ui.p.SurfaceHi
	}
	return roundedFill(gtx, bg, 0, func(gtx layout.Context) layout.Dimensions {
		return material.ButtonLayout(a.ui.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.ui.Avatar(gtx, c.Title, unit.Dp(46), dotNone)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
									layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
										lbl := a.ui.Label(unit.Sp(15), c.Title)
										lbl.MaxLines = 1
										return lbl.Layout(gtx)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										t := a.ui.Dim(unit.Sp(11), fmtTime(c.LastMsgTime))
										t.Color = a.ui.p.TextFaint
										return t.Layout(gtx)
									}),
								)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									preview := previewText(c)
									colorT := a.ui.p.TextDim
									if a.stillTyping(chatKey{c.AccountID, c.ChatID}) {
										preview = "typing…"
										colorT = a.ui.p.Accent
									}
									lbl := a.ui.Label(unit.Sp(13), preview)
									lbl.Color = colorT
									lbl.MaxLines = 1
									return lbl.Layout(gtx)
								})
							}),
						)
					}),
					// unread badge
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if c.UnreadCount <= 0 {
							return layout.Dimensions{}
						}
						return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return unreadBadge(gtx, a.ui, c.UnreadCount, c.IsMuted)
						})
					}),
				)
			})
		})
	})
}

func previewText(c engine.ChatInfo) string {
	prefix := ""
	if c.LastMsgSender != "" && !c.LastMsgIsOutgoing {
		prefix = c.LastMsgSender + ": "
	}
	if c.LastMsgIsOutgoing {
		prefix = "You: "
	}
	if c.LastMsgText != "" {
		return prefix + c.LastMsgText
	}
	// Media-only last message: typed label like AyuGram's dialog rows
	// ("Photo", "Voice message", ...).
	if c.LastMsgMediaType != 0 {
		return prefix + engine.MediaPreviewLabel(c.LastMsgMediaType)
	}
	return prefix
}

func unreadBadge(gtx layout.Context, u *UI, n int, muted bool) layout.Dimensions {
	bg := u.p.UnreadBadge
	if muted {
		bg = u.p.TextFaint
	}
	txt := itoa(n)
	w := gtx.Dp(unit.Dp(18))
	if len(txt) > 2 {
		w = gtx.Dp(unit.Dp(26))
	}
	return roundedFill(gtx, bg, 9, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Min.X = w
		gtx.Constraints.Max.X = w
		return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := u.Label(unit.Sp(11), txt)
			lbl.Color = rgb(0x0D1821)
			lbl.Font.Weight = font.Bold
			return lbl.Layout(gtx)
		})
	})
}

func itoa(n int) string {
	if n <= 0 {
		return "0"
	}
	if n > 999 {
		return "999+"
	}
	b := [4]byte{}
	i := len(b)
	for n > 0 && i > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	return string(b[i:])
}

// currentAccount picks the account to show in the account bar: the one owning
// the selected chat, else the first.
func currentAccount(f frame) engine.AccountInfo {
	if f.selected != nil {
		for _, acc := range f.accounts {
			if acc.ID == f.selected.AccountID {
				return acc
			}
		}
	}
	if len(f.accounts) > 0 {
		return f.accounts[0]
	}
	return engine.AccountInfo{Platform: "none"}
}

func accountName(acc engine.AccountInfo) string {
	if acc.DisplayName != "" {
		return acc.DisplayName
	}
	if acc.Username != "" {
		return acc.Username
	}
	if acc.Phone != "" {
		return acc.Phone
	}
	return platformTitle(acc.Platform)
}

func accountSubtitle(acc engine.AccountInfo, f frame) string {
	if busy, ok := f.connecting[acc.ID]; ok && busy {
		return "connecting…"
	}
	switch acc.ConnState {
	case int(engine.ConnConnected):
		return "connected"
	case int(engine.ConnConnecting):
		return "connecting…"
	case int(engine.ConnUnstable):
		return "unstable connection"
	default:
		return "offline"
	}
}

// ── drawing helpers ──────────────────────────────────────────────────────

var color00 = transparent()

func transparent() color.NRGBA {
	return color.NRGBA{}
}

// roundedFill paints a rounded-rect background behind w.
func roundedFill(gtx layout.Context, c color.NRGBA, radius unit.Dp, w layout.Widget) layout.Dimensions {
	return layout.Stack{}.Layout(gtx,
		layout.Expanded(func(gtx layout.Context) layout.Dimensions {
			r := gtx.Dp(radius)
			size := gtx.Constraints.Min
			defer clip.RRect{Rect: image.Rect(0, 0, size.X, size.Y), NE: r, NW: r, SE: r, SW: r}.Push(gtx.Ops).Pop()
			paint.Fill(gtx.Ops, c)
			return layout.Dimensions{Size: size}
		}),
		layout.Stacked(w),
	)
}

var _ op.Ops
var _ material.Theme
