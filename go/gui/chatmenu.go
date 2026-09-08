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

// chatMenuTarget is an open chat-row context menu.
type chatMenuTarget struct {
	chat engine.ChatInfo
	pos  image.Point
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
		case "delete":
			err = a.eng.DeleteChat(c.AccountID, c.ChatID, false)
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
	if f.chatMenu != nil {
		if !pointInRect(pos, a.chatMenuRect) {
			a.closeChatMenu()
		}
		return
	}
	if pe.Buttons != pointer.ButtonSecondary {
		return
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
	items := chatMenuItems(m)
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
					a.closeChatMenu()
					a.dispatchChatAction(chat, action)
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
