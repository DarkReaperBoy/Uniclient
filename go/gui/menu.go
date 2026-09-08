package gui

import (
	"image"
	"io"
	"strings"

	"gioui.org/io/clipboard"
	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Context menu + forward picker — the AyuGram message-action surface
// (research/ayugram_parity.md §3/§4: message context menu, quick reactions,
// forward box). Every visible entry dispatches a real engine action
// asynchronously; nothing here fakes state (§1.10).

// defaultQuickReactions mirrors Telegram's built-in default reaction set
// (AyuGram shows the server-configured list; this is the offline fallback
// while/when the server list is unavailable).
var defaultQuickReactions = []string{"👍", "👎", "❤️", "🔥", "🥰", "👏", "😁", "🤔", "😱", "😢", "🎉", "🙏"}

// chatPaneTag receives pointer presses across the chat pane so right-clicks
// open the message context menu anchored at the cursor (AyuGram behavior),
// and any press outside an open menu dismisses it.
var chatPaneTag = new(struct{})

// menuTarget is an open context menu: the message it acts on (a copy) and
// the anchor position in chat-pane coordinates.
type menuTarget struct {
	msg engine.CachedMessage
	pos image.Point
}

// menu button pools (grown per frame, repo style).
var (
	menuBtns      []widget.Clickable // action rows
	menuReactBtns []widget.Clickable // quick-reaction pills
	fwdChatBtns   []widget.Clickable // forward picker rows
	fwdCancelBtn  widget.Clickable
	chipCancelBtn widget.Clickable // reply/edit header close
)

func growClickables(pool *[]widget.Clickable, n int) {
	for len(*pool) < n {
		*pool = append(*pool, widget.Clickable{})
	}
}

// ── pane press routing ───────────────────────────────────────────────────

// processPaneEvents registers chat-pane pointer interest and routes presses:
// right-click on a message row opens the context menu; any press outside an
// open menu closes it. Context menus never block the chat (AyuGram).
func (a *App) processPaneEvents(gtx layout.Context, f frame) {
	stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
	event.Op(gtx.Ops, chatPaneTag)
	stack.Pop()
	for {
		ev, ok := gtx.Source.Event(pointer.Filter{Target: chatPaneTag, Kinds: pointer.Press})
		if !ok {
			break
		}
		if pe, is := ev.(pointer.Event); is && pe.Kind == pointer.Press {
			a.onPanePress(f, pe)
		}
	}
}

func (a *App) onPanePress(f frame, pe pointer.Event) {
	pos := image.Pt(int(pe.Position.X), int(pe.Position.Y))
	if f.attachMenuOpen {
		if !pointInRect(pos, a.attachMenuRect) {
			a.closeAttachMenu()
		}
	}
	if f.emojiOpen {
		if !pointInRect(pos, a.emojiRect) {
			a.closeEmojiPanel()
		}
	}
	if f.headerMenu != nil {
		if !pointInRect(pos, a.headerMenuRect) {
			a.closeHeaderMenu()
		}
		return // presses inside the menu belong to its own buttons
	}
	if f.menu != nil {
		if !pointInRect(pos, a.menuRect) {
			a.closeMenu()
		}
		return // presses inside the menu belong to its own buttons
	}
	// Selection mode: any row press toggles its mark (AyuGram multi-select;
	// taps are the pure-Go input surface here).
	if f.selOn {
		if idx := a.rowAt(pos); idx >= 0 && idx < len(f.messages) {
			a.toggleMsgSel(f.messages[idx].MsgID)
		}
		return
	}
	if pe.Buttons != pointer.ButtonSecondary {
		return
	}
	idx := a.rowAt(pos)
	if idx < 0 || idx >= len(f.messages) {
		return
	}
	a.openMenu(f.messages[idx], pos)
}

// pointInRect reports whether p is inside r.
func pointInRect(p image.Point, r image.Rectangle) bool {
	return p.X >= r.Min.X && p.X < r.Max.X && p.Y >= r.Min.Y && p.Y < r.Max.Y
}

// rowAt maps a pane-space point to the index (in f.messages) of the message
// row under it, using the row bounds recorded by the previous frame's layout.
func (a *App) rowAt(pos image.Point) int {
	for idx, r := range a.rowBounds {
		if pointInRect(pos, r) {
			return idx
		}
	}
	return -1
}

// ── menu state ───────────────────────────────────────────────────────────

func (a *App) openMenu(msg engine.CachedMessage, pos image.Point) {
	a.mu.Lock()
	a.menu = &menuTarget{msg: msg, pos: pos}
	a.mu.Unlock()
	a.invalidate()

	account := msg.AccountID
	if a.menuCapsForLocked() != account {
		go func() {
			caps := a.eng.AccountCapabilities(account)
			a.mu.Lock()
			a.menuCaps, a.menuCapsFor = caps, account
			a.mu.Unlock()
			a.invalidate()
		}()
	}
	if a.availForLocked() != account {
		go func() {
			emojis, err := a.eng.GetAvailableReactions(account)
			if err != nil || len(emojis) == 0 {
				emojis = defaultQuickReactions
			}
			a.mu.Lock()
			a.availEmojis, a.availFor = emojis, account
			a.mu.Unlock()
			a.invalidate()
		}()
	}
}

func (a *App) closeMenu() {
	a.mu.Lock()
	a.menu = nil
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) menuCapsForLocked() string {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.menuCapsFor
}

func (a *App) availForLocked() string {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.availFor
}

// ── menu actions ─────────────────────────────────────────────────────────

type menuAction struct {
	label string
	run   func(gtx layout.Context)
}

func (a *App) menuActionsFor(f frame, m engine.CachedMessage) []menuAction {
	acts := actionsFor(&m, f.menuCaps)
	pinned := m.IsPinned
	items := make([]menuAction, 0, 8)
	if acts.Reply {
		items = append(items, menuAction{"Reply", func(gtx layout.Context) {
			a.startReply(&m)
		}})
	}
	if acts.Edit {
		items = append(items, menuAction{"Edit", func(gtx layout.Context) {
			a.startEdit(&m)
			gtx.Execute(key.FocusCmd{Tag: &composer})
		}})
	}
	if acts.Copy {
		items = append(items, menuAction{"Copy Text", func(gtx layout.Context) {
			gtx.Execute(clipboard.WriteCmd{
				Type: "text/plain",
				Data: io.NopCloser(strings.NewReader(m.ContentText)),
			})
		}})
	}
	if acts.Forward {
		items = append(items, menuAction{"Forward", func(gtx layout.Context) {
			a.mu.Lock()
			a.fwd = []engine.CachedMessage{m}
			a.mu.Unlock()
			a.invalidate()
		}})
	}
	// Enter selection mode (AyuGram message multi-select).
	if !m.IsService {
		items = append(items, menuAction{"Select", func(gtx layout.Context) {
			a.startSelection(m.MsgID)
		}})
	}
	// Report (AyuGram: incoming, non-service messages).
	if canReport(m) {
		items = append(items, menuAction{"Report", func(gtx layout.Context) {
			a.openReportDialog([]engine.CachedMessage{m})
		}})
	}
	if acts.Pin {
		label := "Pin"
		if pinned {
			label = "Unpin"
		}
		items = append(items, menuAction{label, func(gtx layout.Context) {
			go func() {
				if err := a.eng.PinMessage(m.AccountID, m.ChatID, m.MsgID, !pinned); err != nil {
					a.setToast("Pin failed: " + err.Error())
				}
			}()
		}})
	}
	if acts.Delete {
		items = append(items, menuAction{"Delete", func(gtx layout.Context) {
			a.openDeleteDialog([]engine.CachedMessage{m}, chatOf(f, m))
		}})
	}
	return items
}

// ── context menu rendering ───────────────────────────────────────────────

// layoutContextMenu draws the open message context menu anchored at its press
// position, clamped to the pane. Called after the chat content so it draws
// on top. Records the rendered rect for outside-press dismissal.
func (a *App) layoutContextMenu(gtx layout.Context, f frame) layout.Dimensions {
	m := f.menu.msg
	items := a.menuActionsFor(f, m)

	reacts := f.availEmojis
	acts := actionsFor(&m, f.menuCaps)
	nReact := 0
	if acts.React {
		nReact = len(reacts)
		if nReact > 8 {
			nReact = 8 // top row only, AyuGram quick-reactions bar
		}
	}
	growClickables(&menuBtns, len(items))
	growClickables(&menuReactBtns, nReact)

	menuW := gtx.Dp(unit.Dp(200))
	rowH := gtx.Dp(unit.Dp(36))
	reactH := gtx.Dp(unit.Dp(46))
	h := gtx.Dp(unit.Dp(8))
	if nReact > 0 {
		h += reactH
	}
	h += len(items) * rowH
	h += gtx.Dp(unit.Dp(8))

	pos := f.menu.pos
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
	a.menuRect = image.Rect(pos.X, pos.Y, pos.X+menuW, pos.Y+h)

	defer op.Offset(pos).Push(gtx.Ops).Pop()
	gtx.Constraints = layout.Constraints{Max: image.Pt(menuW, h), Min: image.Pt(menuW, h)}

	flex := layout.Flex{Axis: layout.Vertical}
	var children []layout.FlexChild
	if nReact > 0 {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.menuReactionsRow(gtx, f, reacts[:nReact], &m)
		}))
	}
	for i := range items {
		i := i
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.menuItemRow(gtx, &menuBtns[i], items[i], rowH)
		}))
	}
	return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
		flex.Layout(gtx, children...)
		return layout.Dimensions{Size: image.Pt(menuW, h)}
	})
}

// menuReactionsRow renders the quick-reaction pills (emoji buttons).
func (a *App) menuReactionsRow(gtx layout.Context, f frame, emojis []string, m *engine.CachedMessage) layout.Dimensions {
	return layout.Inset{
		Top: unit.Dp(8), Bottom: unit.Dp(4), Left: unit.Dp(8), Right: unit.Dp(8),
	}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		children := make([]layout.FlexChild, 0, len(emojis))
		for i, emoji := range emojis {
			i, emoji := i, emoji
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := &menuReactBtns[i]
				if btn.Clicked(gtx) {
					msg, emoji := *m, emoji
					go func() {
						if err := a.eng.ReactToMessage(msg.AccountID, msg.ChatID, msg.MsgID, emoji); err != nil {
							a.setToast("React failed: " + err.Error())
						}
					}()
					a.closeMenu()
				}
				b := material.Button(a.ui.Theme, btn, emoji)
				b.Background = a.ui.p.SurfaceHi
				b.Color = a.ui.p.Text
				b.TextSize = unit.Sp(16)
				b.CornerRadius = 14
				b.Inset = layout.UniformInset(unit.Dp(5))
				return b.Layout(gtx)
			}))
		}
		return layout.Flex{Spacing: layout.SpaceBetween}.Layout(gtx, children...)
	})
}

// menuItemRow renders one menu action row (flat, ripple on press).
func (a *App) menuItemRow(gtx layout.Context, btn *widget.Clickable, item menuAction, rowH int) layout.Dimensions {
	if btn.Clicked(gtx) {
		a.closeMenu()
		item.run(gtx)
	}
	bl := material.ButtonLayout(a.ui.Theme, btn)
	bl.Background = a.ui.p.Surface // invisible against the menu card
	bl.CornerRadius = 8
	gtx.Constraints.Min.Y = rowH
	return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.UniformInset(unit.Dp(9)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Label(unit.Sp(14), item.label)
			return lbl.Layout(gtx)
		})
	})
}

// ── forward picker (AyuGram ChooseRecipientBox, first pass) ──────────────

// layoutForwardDialog replaces the chat-pane content while a forward target
// is being picked (layout swap = no click-through). Handles single and
// batch sources (selection mode).
func (a *App) layoutForwardDialog(gtx layout.Context, f frame) layout.Dimensions {
	if len(f.fwd) == 0 {
		return layout.Dimensions{}
	}
	srcs := f.fwd
	m := srcs[0]

	// Candidates: chats on the same account as the source message.
	var candidates []engine.ChatInfo
	for _, c := range f.chats {
		if c.AccountID == m.AccountID && !(c.ChatID == m.ChatID) {
			candidates = append(candidates, c)
		}
	}
	growClickables(&fwdChatBtns, len(candidates))

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(10), Bottom: unit.Dp(10), Left: unit.Dp(16), Right: unit.Dp(12)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							title := "Forward to…"
							if len(srcs) > 1 {
								title = "Forward " + itoa(len(srcs)) + " messages to…"
							}
							return a.ui.H3(title).Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							if fwdCancelBtn.Clicked(gtx) {
								a.mu.Lock()
								a.fwd = nil
								a.mu.Unlock()
								a.invalidate()
							}
							btn := a.ui.IconButton(&fwdCancelBtn, iconContentClear, "Cancel")
							btn.Color = a.ui.p.TextDim
							return btn.Layout(gtx)
						}),
					)
				})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions { return a.ui.Divider(gtx) }),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			if len(candidates) == 0 {
				return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(14), "No chats to forward to")
					return lbl.Layout(gtx)
				})
			}
			list := &fwdList
			list.Axis = layout.Vertical
			ml := material.List(a.ui.Theme, list)
			return ml.Layout(gtx, len(candidates), func(gtx layout.Context, i int) layout.Dimensions {
				c := candidates[i]
				btn := &fwdChatBtns[i]
				if btn.Clicked(gtx) {
					dst := c
					a.mu.Lock()
					a.fwd = nil
					a.mu.Unlock()
					a.invalidate()
					go func() {
						if len(srcs) == 1 {
							if err := a.eng.ForwardMessage(srcs[0].AccountID, srcs[0].ChatID, srcs[0].MsgID, dst.ChatID, false, false, false, 0); err != nil {
								a.setToast("Forward failed: " + err.Error())
							} else {
								a.setToast("Forwarded to " + dst.Title)
							}
							return
						}
						ids := make([]string, len(srcs))
						for k := range srcs {
							ids[k] = srcs[k].MsgID
						}
						if err := a.eng.ForwardMessages(srcs[0].AccountID, srcs[0].ChatID, ids, dst.ChatID, false, false, false, 0); err != nil {
							a.setToast("Forward failed: " + err.Error())
						} else {
							a.setToast("Forwarded " + itoa(len(ids)) + " messages to " + dst.Title)
						}
					}()
				}
				bl := material.ButtonLayout(a.ui.Theme, btn)
				bl.Background = a.ui.p.Surface
				bl.CornerRadius = 0
				return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(12), Bottom: unit.Dp(12), Left: unit.Dp(16), Right: unit.Dp(16)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(15), c.Title)
						return lbl.Layout(gtx)
					})
				})
			})
		}),
	)
}

var fwdList widget.List
