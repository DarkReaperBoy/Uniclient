package gui

import (
	"gioui.org/io/key"
	"gioui.org/layout"

	"uniclient/engine"
)

// Global keyboard shortcuts (AyuGram parity, matrix "Keyboard shortcuts"):
// Esc closes the topmost surface, Ctrl+F opens search (in-chat when a chat
// is open, the sidebar filter otherwise), Ctrl+Up/Down and Ctrl+PgUp/PgDn
// switch to the previous/next chat in the list. Dialogs, the media viewer,
// the drawer and contacts handle Esc inside their own layouts (they render
// earlier and consume the event first), so this layer only picks up the
// remaining surfaces, top-down — mirrors AyuGram's dismissal order.

var shortcutKeyTag = new(struct{})

// escTarget names the surface a global Esc should close ("" = nothing).
// Pure over the frame — unit-tested. Self-handled surfaces (dialogs,
// viewer, drawer, contacts, settings) return "" so the layer stays idle.
func escTarget(f frame) string {
	switch {
	case f.delDlg != nil,
		f.reportDlg != nil,
		f.schedDlg != nil,
		f.pollDlg != nil,
		f.folderDlg != nil,
		f.folderInvites != nil,
		f.attachDlg != nil,
		f.ttlDlg != nil,
		f.privacyDlg != nil,
		f.autoDlDlg != nil,
		f.themeDlg != nil,
		f.cloudDlg != nil,
		f.ayuFilterDlg != nil,
		f.shadowDlg != nil,
		f.editHistDlg != nil,
		f.deletedDlg != nil,
		f.seenDlg != nil,
		f.msgDetailDlg != nil,  // self-handled: details dialog Esc (slice 105)
		f.stickerSetDlg != nil, // self-handled: sticker pack Esc (slice 108)
		f.folderImportDlg != nil,
		f.exportDlg != nil,
		f.inviteDlg != nil,
		f.newDlg != nil,
		f.viewer != nil,
		f.storyView != nil, // self-handled: story viewer Esc layer (slice 104)
		f.call != nil,      // self-handled: the call overlay has its own Esc layer (slice 101)
		f.drawerOpen,
		f.contactsOpen,
		f.callsBoxOpen,
		f.settingsOpen,
		f.schedPanel:
		return "" // those surfaces consume Esc in their own layouts
	case f.menu != nil:
		return "menu"
	case f.headerMenu != nil:
		return "headerMenu"
	case f.folderMenu != nil:
		return "folderMenu"
	case f.chatMenu != nil:
		return "chatMenu"
	case f.attachMenuOpen:
		return "attach"
	case f.botCmdsOn:
		return "botcmds"
	case f.emojiOpen:
		return "emoji"
	case f.selOn:
		return "selection"
	case f.inSearch:
		return "inChatSearch"
	case f.panelOpen:
		return "panel"
	case f.search != "":
		return "search"
	case f.archiveView:
		return "archive"
	}
	return ""
}

// chatSwitchAction maps a ctrl-modified key press to a chat-list step
// (+1 next, -1 previous, 0 none). Pure — unit-tested.
func chatSwitchAction(name key.Name, ctrl bool) int {
	if !ctrl {
		return 0
	}
	switch name {
	case key.NameUpArrow, key.NamePageUp:
		return -1
	case key.NameDownArrow, key.NamePageDown:
		return 1
	}
	return 0
}

// accountScopeCycle steps the account scope through "" (all chats) and
// every account ID in list order, wrapping. Pure — unit-tested.
func accountScopeCycle(accounts []engine.AccountInfo, cur string, delta int) string {
	if len(accounts) == 0 || delta == 0 {
		return cur
	}
	scopes := make([]string, 0, len(accounts)+1)
	scopes = append(scopes, "")
	for _, acc := range accounts {
		scopes = append(scopes, acc.ID)
	}
	idx := 0
	for i, s := range scopes {
		if s == cur {
			idx = i
			break
		}
	}
	next := ((idx+delta)%len(scopes) + len(scopes)) % len(scopes)
	return scopes[next]
}

// accountSwitchStep maps a Tab key press to an account-scope step
// (+1 Ctrl+Tab, -1 Ctrl+Shift+Tab, 0 otherwise). Pure — unit-tested.
func accountSwitchStep(name key.Name, ctrl, shift bool) int {
	if !ctrl || name != key.NameTab {
		return 0
	}
	if shift {
		return -1
	}
	return 1
}

// switchAccountScope applies one account-scope step (the same path as
// the sidebar/tray account rows).
func (a *App) switchAccountScope(delta int) {
	a.mu.Lock()
	next := accountScopeCycle(a.accounts, a.acctFilter, delta)
	if next == a.acctFilter {
		a.mu.Unlock()
		return
	}
	a.acctFilter = next
	a.folder = 0
	scope := next
	a.mu.Unlock()
	a.refreshFolders(scope)
	a.invalidate()
}

// neighborChat picks the chat delta steps away from the current one in the
// list (wrapping). cur == nil selects the first (delta > 0) or last chat.
// Pure — unit-tested.
func neighborChat(chats []engine.ChatInfo, cur *chatKey, delta int) (engine.ChatInfo, bool) {
	if len(chats) == 0 || delta == 0 {
		return engine.ChatInfo{}, false
	}
	idx := -1
	if cur != nil {
		for i := range chats {
			if chats[i].AccountID == cur.AccountID && chats[i].ChatID == cur.ChatID {
				idx = i
				break
			}
		}
	}
	next := idx + delta
	if next < 0 {
		next = len(chats) - 1
	} else if next >= len(chats) {
		next = 0
	}
	if next == idx {
		return engine.ChatInfo{}, false
	}
	return chats[next], true
}

// layoutShortcuts registers the global key layer. Called at the END of
// Root so surface-local handlers consume their events first.
func (a *App) layoutShortcuts(gtx layout.Context, f frame) {
	{
		// Window-wide key listener, transparent to pointer hit-testing —
		// see keyLayer (input-freeze regression, 2026-09-09).
		keyLayer(gtx, shortcutKeyTag)
	}

	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.handleEscTarget(escTarget(f))
		}
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: "F", Required: key.ModCtrl})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.handleSearchShortcut(gtx, f)
		}
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Required: key.ModCtrl})
		if !ok {
			break
		}
		ke, is := ev.(key.Event)
		if !is || ke.State != key.Press {
			continue
		}
		if step := chatSwitchAction(ke.Name, ke.Modifiers.Contain(key.ModCtrl)); step != 0 {
			a.handleChatSwitch(f, step)
		}
	}
	// Ctrl+Tab / Ctrl+Shift+Tab (slice 147): cycle the account scope
	// ("" = all chats, then each account, wrapping).
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameTab, Required: key.ModCtrl})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			if step := accountSwitchStep(ke.Name, true, ke.Modifiers.Contain(key.ModShift)); step != 0 {
				a.switchAccountScope(step)
			}
		}
	}
}

// handleEscTarget closes the surface named by escTarget.
func (a *App) handleEscTarget(target string) {
	switch target {
	case "menu":
		a.closeMenu()
	case "headerMenu":
		a.closeHeaderMenu()
	case "folderMenu":
		a.closeFolderMenu()
	case "chatMenu":
		a.closeChatMenu()
	case "attach":
		a.closeAttachMenu()
	case "botcmds":
		a.closeBotCmds()
	case "emoji":
		a.closeEmojiPanel()
	case "selection":
		a.cancelSelection()
	case "inChatSearch":
		a.closeInChatSearch()
	case "panel":
		a.closePanel()
	case "search":
		sidebarSearch.SetText("")
	case "archive":
		a.exitArchive() // slice 67: Esc leaves the archived-chats view
	}
}

// handleSearchShortcut: Ctrl+F opens the in-chat search when a chat is
// open (AyuGram behavior), otherwise focuses the sidebar search field.
func (a *App) handleSearchShortcut(gtx layout.Context, f frame) {
	if f.selected != nil && !f.inSearch {
		a.toggleInChatSearch()
		return
	}
	gtx.Execute(key.FocusCmd{Tag: &sidebarSearch})
}

// handleChatSwitch opens the neighbor chat in the list.
func (a *App) handleChatSwitch(f frame, step int) {
	c, ok := neighborChat(f.chats, f.selected, step)
	if !ok {
		return
	}
	a.openChat(chatKey{AccountID: c.AccountID, ChatID: c.ChatID}, c.Title)
}
