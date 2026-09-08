package gui

import (
	"image"

	"gioui.org/io/event"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Chat-row context menu (AyuGram parity §2 "Chat row context menu"):
// right-click a chat row for mute (1h/8h/forever), pin, mark read/unread,
// archive, delete — all real engine calls. Hit-testing mirrors the chat
// pane: the sidebar registers a pane-wide press area; row bounds recorded
// during layout map the press to a chat.

// sidebarPaneTag receives pointer presses across the sidebar.
var sidebarPaneTag = new(struct{})

// chatMenuTarget is an open chat-row context menu. When folderPick is
// set the menu shows the account's folders instead (add-to-folder).
type chatMenuTarget struct {
	chat       engine.ChatInfo
	pos        image.Point
	folderPick bool
}

// chatMenuAction is one menu row: a label plus the engine action id.
type chatMenuAction struct {
	label  string
	action string
}

// chatMenuItems derives the action rows for a chat (flags decide labels).
func chatMenuItems(c engine.ChatInfo) []chatMenuAction {
	var items []chatMenuAction
	if c.IsMuted {
		items = append(items, chatMenuAction{"Unmute", "unmute"})
	} else {
		items = append(items,
			chatMenuAction{"Mute for 1 hour", "mute1h"},
			chatMenuAction{"Mute for 8 hours", "mute8h"},
			chatMenuAction{"Mute forever", "mute"})
	}
	if c.IsPinned {
		items = append(items, chatMenuAction{"Unpin", "unpin"})
	} else {
		items = append(items, chatMenuAction{"Pin", "pin"})
	}
	if c.UnreadCount > 0 {
		items = append(items, chatMenuAction{"Mark as read", "read"})
	} else {
		items = append(items, chatMenuAction{"Mark as unread", "unread"})
	}
	if c.IsArchived {
		items = append(items, chatMenuAction{"Unarchive", "unarchive"})
	} else {
		items = append(items, chatMenuAction{"Archive", "archive"})
	}
	// Block user (AyuGram chat-row menu, DMs; the header ⋮ menu keeps the
	// state-aware unblock with the profile loaded).
	if c.Type == engine.ChatTypeDMVal {
		items = append(items, chatMenuAction{"Block user", "block"})
	}
	items = append(items, chatMenuAction{"Delete chat", "delete"})
	return items
}

// dispatchChatAction runs one menu action against the engine (async).
func (a *App) dispatchChatAction(c engine.ChatInfo, action string) {
	go func() {
		var err error
		switch action {
		case "mute1h":
			err = a.eng.MuteChat(c.AccountID, c.ChatID, true, 3600)
		case "mute8h":
			err = a.eng.MuteChat(c.AccountID, c.ChatID, true, 8*3600)
		case "mute":
			err = a.eng.MuteChat(c.AccountID, c.ChatID, true, 0)
		case "unmute":
			err = a.eng.MuteChat(c.AccountID, c.ChatID, false, 0)
		case "pin":
			err = a.eng.PinChat(c.AccountID, c.ChatID, true)
		case "unpin":
			err = a.eng.PinChat(c.AccountID, c.ChatID, false)
		case "read":
			err = a.eng.MarkChatRead(c.AccountID, c.ChatID, "")
		case "unread":
			err = a.eng.MarkChatUnread(c.AccountID, c.ChatID)
		case "archive":
			err = a.eng.ArchiveChat(c.AccountID, c.ChatID, true)
		case "unarchive":
			err = a.eng.ArchiveChat(c.AccountID, c.ChatID, false)
		case "block":
			err = a.eng.BlockUser(c.AccountID, c.ChatID)
			if err == nil {
				a.setToast("User blocked")
			}
		case "delete":
			err = a.eng.DeleteChat(c.AccountID, c.ChatID, false)
		case "addfolder":
			// Handled synchronously in layoutChatMenu (opens the picker).
		}
		if err != nil {
			a.setToast("Chat action failed: " + err.Error())
		}
	}()
}

// openChatMenu opens the chat-row menu at pos.
func (a *App) openChatMenu(c engine.ChatInfo, pos image.Point) {
	a.mu.Lock()
	a.chatMenu = &chatMenuTarget{chat: c, pos: pos}
	a.mu.Unlock()
	a.invalidate()
}

// closeChatMenu dismisses it.
func (a *App) closeChatMenu() {
	a.mu.Lock()
	a.chatMenu = nil
	a.mu.Unlock()
	a.invalidate()
}

// processSidebarEvents registers the sidebar press area and routes presses:
// right-click on a chat row opens the menu; any outside press closes it.
func (a *App) processSidebarEvents(gtx layout.Context, f frame) {
	stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
	event.Op(gtx.Ops, sidebarPaneTag)
	stack.Pop()
	for {
		ev, ok := gtx.Source.Event(pointer.Filter{Target: sidebarPaneTag, Kinds: pointer.Press})
		if !ok {
			break
		}
		if pe, is := ev.(pointer.Event); is && pe.Kind == pointer.Press {
			a.onSidebarPress(f, pe)
		}
	}
}

func (a *App) onSidebarPress(f frame, pe pointer.Event) {
	pos := image.Pt(int(pe.Position.X), int(pe.Position.Y))
	if f.folderMenu != nil {
		if !pointInRect(pos, a.folderMenuRect) {
			a.closeFolderMenu()
		}
		return
	}
	if f.chatMenu != nil {
		if !pointInRect(pos, a.chatMenuRect) {
			a.closeChatMenu()
		}
		return
	}
	if pe.Buttons != pointer.ButtonSecondary {
		return
	}
	// Folder tabs first (right-click a server folder tab → its menu).
	if f.folderDlg == nil {
		tabs := buildFolderTabs(f.acctFilter, f.folders, f.foldersSupported)
		for i, r := range a.sbTabBounds {
			if pointInRect(pos, r) && i < len(tabs) && tabs[i].kind == folderTabServer && tabs[i].folder != nil {
				a.openFolderMenu(*tabs[i].folder, f.foldersFor, pos)
				return
			}
		}
	}
	for idx, r := range a.chatRowBounds {
		if pointInRect(pos, r) {
			if idx >= 0 && idx < len(a.sbVisible) {
				a.openChatMenu(a.sbVisible[idx], pos)
			}
			return
		}
	}
}

// layoutChatMenu draws the open chat-row menu, clamped to the sidebar.
func (a *App) layoutChatMenu(gtx layout.Context, f frame) layout.Dimensions {
	m := f.chatMenu.chat
	if f.chatMenu.folderPick {
		return a.layoutFolderPickMenu(gtx, f, m)
	}
	// The account's folders enable the add-to-folder row (slice 27).
	// frame.folders is loaded for the scoped account (frame.foldersFor),
	// so the row only appears when the chat belongs to that account.
	folders := foldersForAccount(f, m.AccountID)
	hasFolders := f.foldersSupported && len(folders) > 0
	items := chatMenuItems(m)
	if hasFolders {
		items = append(items, chatMenuAction{"Add to folder", "addfolder"})
	}
	growClickables(&chatMenuBtns, len(items))

	menuW := gtx.Dp(unit.Dp(210))
	rowH := gtx.Dp(unit.Dp(36))
	h := gtx.Dp(unit.Dp(8)) + len(items)*rowH + gtx.Dp(unit.Dp(8))

	pos := f.chatMenu.pos
	paneW, paneH := gtx.Constraints.Max.X, gtx.Constraints.Max.Y
	if pos.X+menuW > paneW {
		pos.X = paneW - menuW
	}
	if pos.X < 0 {
		pos.X = 0
	}
	if pos.Y+h > paneH {
		pos.Y = paneH - h
	}
	if pos.Y < 0 {
		pos.Y = 0
	}
	a.chatMenuRect = image.Rect(pos.X, pos.Y, pos.X+menuW, pos.Y+h)

	defer op.Offset(pos).Push(gtx.Ops).Pop()
	gtx.Constraints = layout.Constraints{Max: image.Pt(menuW, h), Min: image.Pt(menuW, h)}
	return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
		children := make([]layout.FlexChild, 0, len(items))
		for i := range items {
			i := i
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := &chatMenuBtns[i]
				if btn.Clicked(gtx) {
					chat, action := m, items[i].action
					if action == "addfolder" {
						a.openChatFolderPick(chat)
					} else {
						a.closeChatMenu()
						a.dispatchChatAction(chat, action)
					}
				}
				bl := material.ButtonLayout(a.ui.Theme, btn)
				bl.Background = a.ui.p.Surface
				bl.CornerRadius = 8
				gtx.Constraints.Min.Y = rowH
				return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(9)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(14), items[i].label)
						return lbl.Layout(gtx)
					})
				})
			}))
		}
		layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
		return layout.Dimensions{Size: image.Pt(menuW, h)}
	})
}

var chatMenuBtns []widget.Clickable

// foldersForAccount returns the frame's server folders when they were
// loaded for the given account (folders are fetched per account scope).
func foldersForAccount(f frame, accountID string) []engine.FolderInfo {
	if f.foldersFor != accountID || accountID == "" {
		return nil
	}
	return f.folders
}

// openChatFolderPick switches the chat menu into folder-choice mode.
func (a *App) openChatFolderPick(chat engine.ChatInfo) {
	a.mu.Lock()
	if a.chatMenu != nil {
		a.chatMenu.folderPick = true
	}
	a.mu.Unlock()
	a.invalidate()
}

// layoutFolderPickMenu: the account's folders; clicking one adds the chat.
func (a *App) layoutFolderPickMenu(gtx layout.Context, f frame, m engine.ChatInfo) layout.Dimensions {
	folders := foldersForAccount(f, m.AccountID)
	growClickables(&chatMenuBtns, len(folders)+1)

	menuW := gtx.Dp(unit.Dp(210))
	rowH := gtx.Dp(unit.Dp(36))
	h := gtx.Dp(unit.Dp(8)) + (len(folders)+1)*rowH + gtx.Dp(unit.Dp(8))

	pos := f.chatMenu.pos
	paneW, paneH := gtx.Constraints.Max.X, gtx.Constraints.Max.Y
	if pos.X+menuW > paneW {
		pos.X = paneW - menuW
	}
	if pos.X < 0 {
		pos.X = 0
	}
	if pos.Y+h > paneH {
		pos.Y = paneH - h
	}
	if pos.Y < 0 {
		pos.Y = 0
	}
	a.chatMenuRect = image.Rect(pos.X, pos.Y, pos.X+menuW, pos.Y+h)

	// Cancel row sits last (AyuGram dialogs put the negative action last).
	cancelIdx := len(folders)
	if chatMenuBtns[cancelIdx].Clicked(gtx) {
		a.closeChatMenu()
	}
	for i, fo := range folders {
		i, fo := i, fo
		if chatMenuBtns[i].Clicked(gtx) {
			chat := m
			folder := fo
			a.closeChatMenu()
			go func() {
				if err := a.eng.AddChatToFolder(chat.AccountID, chat.ChatID, folder.ID); err != nil {
					a.setToast("Add to folder failed: " + err.Error())
					return
				}
				a.setToast("Added to " + folder.Name)
				a.refreshFolders(chat.AccountID)
			}()
		}
	}

	defer op.Offset(pos).Push(gtx.Ops).Pop()
	gtx.Constraints = layout.Constraints{Max: image.Pt(menuW, h), Min: image.Pt(menuW, h)}
	return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
		children := make([]layout.FlexChild, 0, len(folders)+1)
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Label(unit.Sp(11), "Add to folder")
			lbl.Color = a.ui.p.TextDim
			return layout.Inset{Top: unit.Dp(8), Left: unit.Dp(12), Bottom: unit.Dp(4)}.Layout(gtx, lbl.Layout)
		}))
		rows := append(folderNames(folders), "Cancel")
		for i, name := range rows {
			i := i
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := &chatMenuBtns[i]
				bl := material.ButtonLayout(a.ui.Theme, btn)
				bl.Background = a.ui.p.Surface
				bl.CornerRadius = 8
				gtx.Constraints.Min.Y = rowH
				return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(9)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(14), name)
						return lbl.Layout(gtx)
					})
				})
			}))
		}
		layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
		return layout.Dimensions{Size: image.Pt(menuW, h)}
	})
}

// folderNames: display names for folders (emoticon + name, AyuGram style).
func folderNames(folders []engine.FolderInfo) []string {
	out := make([]string, 0, len(folders))
	for _, fo := range folders {
		name := fo.Name
		if name == "" {
			name = "Folder"
		}
		if fo.Emoticon != "" {
			name = fo.Emoticon + " " + name
		}
		out = append(out, name)
	}
	return out
}
