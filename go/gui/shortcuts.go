package gui

import (
	"log"

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
// chatSwitchAction: Ctrl+Up/Down/PgUp/PgDn and Alt+Up/Down (tdesktop
// ChatNext/ChatPrevious bindings) step through the chat list.
func chatSwitchAction(name key.Name, ctrl, alt bool) int {
	if ctrl {
		switch name {
		case key.NameUpArrow, key.NamePageUp:
			return -1
		case key.NameDownArrow, key.NamePageDown:
			return 1
		}
		return 0
	}
	if alt {
		switch name {
		case key.NameUpArrow:
			return -1
		case key.NameDownArrow:
			return 1
		}
	}
	return 0
}

// jumplistDigit maps the tdesktop Ctrl+digit family: 1..8 = jump to the
// Nth pinned chat (ChatPinned1..8), 9 = ShowArchive, 10 = ChatSelf
// (Saved Messages); 0 = not a jumplist key.
func jumplistDigit(name key.Name, ctrl bool) int {
	if !ctrl {
		return 0
	}
	if len(name) != 1 || name[0] < '0' || name[0] > '9' {
		return 0
	}
	d := int(name[0] - '0')
	if d == 0 {
		return 10 // ChatSelf
	}
	return d
}

// pinnedJumpChat resolves the Nth pinned chat of the visible list (the
// list is pinned-first, so this walks the pinned prefix).
func pinnedJumpChat(chats []engine.ChatInfo, n int) (engine.ChatInfo, bool) {
	if n <= 0 {
		return engine.ChatInfo{}, false
	}
	seen := 0
	for _, c := range chats {
		if !c.IsPinned {
			continue
		}
		seen++
		if seen == n {
			return c, true
		}
	}
	return engine.ChatInfo{}, false
}

// chatEdgeAction: Ctrl+Alt+Home = ChatFirst (1), Ctrl+Alt+End =
// ChatLast (2).
func chatEdgeAction(name key.Name, ctrl, alt bool) int {
	if !ctrl || !alt {
		return 0
	}
	switch name {
	case key.NameHome:
		return 1
	case key.NameEnd:
		return 2
	}
	return 0
}

// showContactsKey: Ctrl+J = ShowContacts.
func showContactsKey(name key.Name, ctrl bool) bool {
	return ctrl && name == "J"
}

// readChatKey: Ctrl+R = ReadChat (mark the open chat read).
func readChatKey(name key.Name, ctrl bool) bool {
	return ctrl && name == "R"
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
		ctrl := ke.Modifiers.Contain(key.ModCtrl)
		alt := ke.Modifiers.Contain(key.ModAlt)
		if step := chatSwitchAction(ke.Name, ctrl, alt); step != 0 {
			a.handleChatSwitch(f, step)
			continue
		}
		// Slice 166: the tdesktop jumplist family.
		if edge := chatEdgeAction(ke.Name, ctrl, alt); edge != 0 {
			a.handleChatEdge(f, edge)
			continue
		}
		if n := jumplistDigit(ke.Name, ctrl); n != 0 {
			a.handleJumplistDigit(f, n)
			continue
		}
		if showContactsKey(ke.Name, ctrl) {
			if acc := currentAccount(f); acc.ID != "" {
				a.openContacts(acc.ID)
			}
			continue
		}
		if readChatKey(ke.Name, ctrl) {
			a.handleReadChat(f)
			continue
		}
	}
	// Alt+Up/Down (tdesktop ChatNext/ChatPrevious) ride the same switch.
	for {
		ev, ok := gtx.Source.Event(key.Filter{Required: key.ModAlt})
		if !ok {
			break
		}
		ke, is := ev.(key.Event)
		if !is || ke.State != key.Press {
			continue
		}
		if step := chatSwitchAction(ke.Name, false, true); step != 0 {
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

// handleChatEdge jumps to the first (which=1) or last (which=2) chat of
// the visible list (tdesktop ChatFirst/ChatLast, Ctrl+Alt+Home/End).
func (a *App) handleChatEdge(f frame, which int) {
	visible := filterChats(f)
	if len(visible) == 0 {
		return
	}
	c := visible[0]
	if which == 2 {
		c = visible[len(visible)-1]
	}
	a.openChat(chatKey{AccountID: c.AccountID, ChatID: c.ChatID}, c.Title)
}

// handleJumplistDigit: Ctrl+1..8 jump to the Nth pinned chat
// (ChatPinned1..8); Ctrl+9 opens the archive view (ShowArchive); Ctrl+0
// opens Saved Messages (ChatSelf).
func (a *App) handleJumplistDigit(f frame, n int) {
	switch {
	case n == 9: // ShowArchive
		a.mu.Lock()
		a.archiveView = true
		a.mu.Unlock()
		a.invalidate()
	case n == 10: // ChatSelf → Saved Messages
		accID := ""
		if sel := f.selected; sel != nil {
			accID = sel.AccountID
		} else if len(f.savedMsgAccts) > 0 {
			accID = f.savedMsgAccts[0]
		} else if acc := currentAccount(f); acc.ID != "" {
			accID = acc.ID
		}
		if accID != "" {
			a.openSavedMessages(accID)
		}
	default: // ChatPinned1..8
		if c, ok := pinnedJumpChat(filterChats(f), n); ok {
			a.openChat(chatKey{AccountID: c.AccountID, ChatID: c.ChatID}, c.Title)
		}
	}
}

// handleReadChat marks the open chat read (tdesktop ReadChat, Ctrl+R).
func (a *App) handleReadChat(f frame) {
	if f.selected == nil {
		return
	}
	acc, chat := f.selected.AccountID, f.selected.ChatID
	go func() {
		if err := a.eng.MarkChatRead(acc, chat, ""); err != nil {
			log.Printf("gui: read chat shortcut: %v", err)
		}
	}()
}
