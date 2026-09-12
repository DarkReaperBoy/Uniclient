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
	msg    engine.CachedMessage
	pos    image.Point
	picker bool // full reaction-grid mode (slice 55)

	// shadow-ban state of msg's sender in its chat (slice 91): nil =
	// unknown (item hidden until resolved); set by openMenu's lookup.
	senderBanned *bool

	// edits-history availability (slice 96): nil = lookup pending
	// (item hidden); set by openMenu's HasEditRevisions lookup.
	hasEdits *bool
}

// menu button pools (grown per frame, repo style).
var (
	menuBtns      []widget.Clickable // action rows
	menuReactBtns []widget.Clickable // quick-reaction pills
	menuPickBtns  []widget.Clickable // full-picker grid cells (slice 55)
	reactList     widget.List        // picker grid scroller
	fwdChatBtns   []widget.Clickable // forward picker rows
	fwdCancelBtn  widget.Clickable
	chipCancelBtn widget.Clickable // reply/edit header close

	fwdHideAuthor   widget.Bool // forward options (AyuGram)
	fwdHideCaptions widget.Bool
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
// Move/Enter/Leave events feed the corner-reply hover tracking (slice 157)
// through the same rowBounds hit-test.
func (a *App) processPaneEvents(gtx layout.Context, f frame) {
	stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
	event.Op(gtx.Ops, chatPaneTag)
	stack.Pop()
	for {
		ev, ok := gtx.Source.Event(pointer.Filter{Target: chatPaneTag, Kinds: pointer.Press | pointer.Move | pointer.Enter | pointer.Leave})
		if !ok {
			break
		}
		pe, is := ev.(pointer.Event)
		if !is {
			continue
		}
		if pe.Kind == pointer.Press {
			a.onPanePress(f, pe)
		} else {
			a.notePaneHover(f, pe)
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

	// Shadow-ban state (slice 91): resolve once per menu open so the
	// action reflects the live ban state (label switches to Unban).
	if msg.SenderID != "" && !msg.IsOutgoing && !msg.IsService {
		go func() {
			banned := a.eng.IsShadowBanned(msg.AccountID, msg.ChatID, msg.SenderID)
			a.mu.Lock()
			if a.menu != nil && a.menu.msg.MsgID == msg.MsgID {
				a.menu.senderBanned = &banned
			}
			a.mu.Unlock()
			a.invalidate()
		}()
	}

	// Edits-history availability (slice 96): resolve once per menu open;
	// the item stays hidden while the lookup is in flight.
	if msg.EditedAt != 0 && !msg.IsService {
		go func() {
			has, err := a.eng.HasEditRevisions(msg.AccountID, msg.ChatID, msg.MsgID)
			if err != nil {
				has = false
			}
			a.mu.Lock()
			if a.menu != nil && a.menu.msg.MsgID == msg.MsgID {
				a.menu.hasEdits = &has
			}
			a.mu.Unlock()
			a.invalidate()
		}()
	}

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
	// Ayu translator (AyuGram "translate message": inline under the bubble).
	if acts.Translate {
		label := "Translate"
		if _, shown := a.translationFor(&m); shown {
			label = "Hide translation"
		}
		items = append(items, menuAction{label, func(gtx layout.Context) {
			a.toggleTranslation(&m)
		}})
	}
	// Message shot (AyuGram "take message screenshot", slice 151):
	// render the message into a shareable PNG via the save picker.
	if strings.TrimSpace(m.ContentText) != "" || m.MediaThumbB64 != "" {
		msg := m
		items = append(items, menuAction{"Message shot…", func(gtx layout.Context) {
			a.saveMessageShot(msg)
		}})
	}
	// Copy link to message (AyuGram: t.me link for channel/group posts).
	chat := chatOf(f, m)
	if chat.Type == engine.ChatTypeChanVal || chat.Type == engine.ChatTypeGroupVal {
		items = append(items, menuAction{"Copy Link", func(gtx layout.Context) {
			go func() {
				link, err := a.eng.MessageLink(m.AccountID, m.ChatID, m.MsgID)
				if err != nil {
					a.setToast("Copy link failed: " + err.Error())
					return
				}
				a.copyTextSoon(link)
			}()
		}})
	}
	// Save to Downloads (matrix row 158, slice 99): AyuGram's save-file /
	// save-GIF / save-sound — copies the media into the user-visible
	// downloads directory (downloading first when needed).
	if saveToDownloadsMenuGate(m) {
		msg := m
		seq := 0
		items = append(items, menuAction{"Save to Downloads", func(gtx layout.Context) {
			a.saveMediaToDownloads(msg.AccountID, msg.ChatID, msg.MsgID, seq)
		}})
	}
	// OS integration (AyuGram row 159): reveal a downloaded media file in
	// the platform file manager (slice 86).
	if m.MediaLocalPath != "" {
		path := m.MediaLocalPath
		items = append(items, menuAction{"Show in Folder", func(gtx layout.Context) {
			a.revealMedia(path)
		}})
	}
	if acts.Forward {
		items = append(items, menuAction{"Forward", func(gtx layout.Context) {
			a.openForward([]engine.CachedMessage{m})
		}})
	}
	// Who reacted (AyuGram reactions list, slice 49).
	if len(m.Reactions) > 0 {
		items = append(items, menuAction{"Who reacted", func(gtx layout.Context) {
			a.openReactors(&m, "")
		}})
	}
	// Ayu local hide (AyuGram "hide message": gone from this client only).
	if !m.IsService {
		items = append(items, menuAction{"Hide Locally", func(gtx layout.Context) {
			go func() {
				if err := a.eng.HideMessage(m.AccountID, m.ChatID, m.MsgID, true); err != nil {
					a.setToast("Hide failed: " + err.Error())
					return
				}
				go a.refreshMessages()
				a.setToast("Message hidden locally")
			}()
		}})
	}
	// Ayu quick filter-add (matrix row 168): prefill a message filter
	// from this message's text (regex-quoted, first line, capped).
	if acts.Filter {
		items = append(items, menuAction{"Filter Like This…", func(gtx layout.Context) {
			a.openAyuFilterDialogPrefilled(quickFilterPattern(m.ContentText))
		}})
	}
	// Read receipts (matrix row 97): who read an own message in a DM
	// or group, with the chat's last-read date.
	if seenByMenuGate(m, chat.Type) {
		msg := m
		items = append(items, menuAction{"Seen by", func(gtx layout.Context) {
			a.openSeenByDialog(&msg)
		}})
	}
	// Sticker pack info (AyuGram, slice 108): sticker messages with set keys.
	if stickerPackMenuGate(m) {
		msg := m
		items = append(items, menuAction{"View sticker pack", func(gtx layout.Context) {
			a.openStickerSetDialog(&msg)
		}})
	}
	// Stop poll (AyuGram parity, slice 124): the creator of an open poll
	// closes it from the context menu.
	if stopPollMenuGate(&m) {
		msg := m
		items = append(items, menuAction{"Stop poll", func(gtx layout.Context) {
			a.stopPollMessage(&msg)
		}})
	}
	// Message details (AyuGram, slice 105): key/value rows from the cache.
	if msgDetailMenuGate(m) {
		msg := m
		items = append(items, menuAction{"Message details", func(gtx layout.Context) {
			a.openMsgDetailDialog(&msg)
		}})
	}
	// Ayu edits history (matrix row 164): anti-recall kept revisions for
	// this message — the dialog lists them newest-first.
	if f.menu != nil && editsMenuGate(m, f.menu.hasEdits != nil, f.menu.hasEdits != nil && *f.menu.hasEdits) {
		msg := m
		items = append(items, menuAction{"Edits history", func(gtx layout.Context) {
			a.openEditHistDialog(&msg)
		}})
	}
	// Ayu shadow ban (matrix row 240): per-chat local ignore of the
	// sender. Label flips once openMenu's lookup resolves the state.
	if f.menu != nil && shadowBanMenuGate(m, f.menu.senderBanned != nil) {
		banned := *f.menu.senderBanned
		label := "Shadow-ban sender"
		if banned {
			label = "Unshadow-ban sender"
		}
		items = append(items, menuAction{label, func(gtx layout.Context) {
			a.toggleShadowBan(m, !banned)
		}})
	}
	// Ayu repeat (AyuGram "repeat message": resend as your own, no forward).
	if !m.IsService && strings.TrimSpace(m.ContentText) != "" {
		items = append(items, menuAction{"Repeat", func(gtx layout.Context) {
			go func() {
				if _, err := a.eng.RepeatMessage(m.AccountID, m.ChatID, m.MsgID); err != nil {
					a.setToast("Repeat failed: " + err.Error())
				}
			}()
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
	if f.menu.picker {
		return a.layoutReactionPicker(gtx, f)
	}
	m := f.menu.msg
	items := a.menuActionsFor(f, m)

	reacts := f.availEmojis
	acts := actionsFor(&m, f.menuCaps)
	var quick []string
	var more bool
	if acts.React {
		quick, more = quickReactions(reacts)
	}
	nReact := len(quick)
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
			return a.menuReactionsRow(gtx, f, quick, more, &m)
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

// quickReactions splits the available reactions into the quick bar
// (max 7 pills) and whether more exist for the expandable picker.
func quickReactions(reacts []string) ([]string, bool) {
	if len(reacts) > 7 {
		return reacts[:7], true
	}
	return reacts, false
}

// menuReactionsRow renders the quick-reaction pills (emoji buttons) and,
// when more reactions exist, the ⋯ toggle that swaps the menu into the
// full picker (AyuGram quick bar + expandable grid).
func (a *App) menuReactionsRow(gtx layout.Context, f frame, emojis []string, more bool, m *engine.CachedMessage) layout.Dimensions {
	growClickables(&menuReactBtns, len(emojis)+1)
	return layout.Inset{
		Top: unit.Dp(8), Bottom: unit.Dp(4), Left: unit.Dp(8), Right: unit.Dp(8),
	}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		children := make([]layout.FlexChild, 0, len(emojis)+1)
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
		if more {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := &menuReactBtns[len(emojis)]
				if btn.Clicked(gtx) {
					a.openReactionPicker()
				}
				b := material.Button(a.ui.Theme, btn, "â¯")
				b.Background = a.ui.p.Surface
				b.Color = a.ui.p.TextFaint
				b.TextSize = unit.Sp(16)
				b.CornerRadius = 14
				b.Inset = layout.UniformInset(unit.Dp(5))
				return b.Layout(gtx)
			}))
		}
		return layout.Flex{Spacing: layout.SpaceBetween}.Layout(gtx, children...)
	})
}

// openReactionPicker swaps the open message menu into the full picker.
func (a *App) openReactionPicker() {
	a.mu.Lock()
	if a.menu != nil {
		a.menu.picker = true
	}
	a.mu.Unlock()
	a.invalidate()
}

// layoutReactionPicker: the full reaction grid (AyuGram expandable
// picker) — every available reaction in an 8-column scrollable grid,
// anchored at the message menu position. Tapping reacts and closes;
// outside-press and Esc keep the menu dismissal paths (menuRect).
func (a *App) layoutReactionPicker(gtx layout.Context, f frame) layout.Dimensions {
	m := f.menu.msg
	emojis := f.availEmojis
	n := len(emojis)
	growClickables(&menuPickBtns, n)

	const cols = 8
	const cellDp = unit.Dp(34)
	menuW := gtx.Dp(unit.Dp(236))
	rows := emojiRowCount(n, cols)
	maxRows := 5
	if rows > maxRows {
		rows = maxRows
	}
	if rows < 1 {
		rows = 1
	}
	cellPx := gtx.Dp(cellDp)
	h := gtx.Dp(unit.Dp(30)) + rows*cellPx + gtx.Dp(unit.Dp(10))

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
	return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(11), "Reactions")
					lbl.Color = a.ui.p.TextFaint
					return lbl.Layout(gtx)
				})
			}),
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				reactList.Axis = layout.Vertical
				lt := material.List(a.ui.Theme, &reactList)
				return lt.Layout(gtx, emojiRowCount(len(emojis), cols), func(gtx layout.Context, row int) layout.Dimensions {
					children := make([]layout.FlexChild, 0, cols)
					for c := 0; c < cols; c++ {
						idx := row*cols + c
						if idx >= len(emojis) {
							break
						}
						idx, emoji := idx, emojis[idx]
						children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							btn := &menuPickBtns[idx]
							if btn.Clicked(gtx) {
								msg, emoji := m, emoji
								go func() {
									if err := a.eng.ReactToMessage(msg.AccountID, msg.ChatID, msg.MsgID, emoji); err != nil {
										a.setToast("React failed: " + err.Error())
									}
								}()
								a.closeMenu()
							}
							b := material.Button(a.ui.Theme, btn, emoji)
							b.Background = a.ui.p.Surface
							b.Color = a.ui.p.Text
							b.TextSize = unit.Sp(17)
							b.CornerRadius = 10
							b.Inset = layout.UniformInset(unit.Dp(4))
							gtx.Constraints.Min = image.Point{}
							return b.Layout(gtx)
						}))
					}
					return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, children...)
				})
			}),
		)
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

	// Candidates: chats on the same account as the source message, with the
	// account's Saved Messages chat pinned first (slice 116).
	candidates := buildForwardCandidates(f.chats, m, f.savedChatID[m.AccountID])
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
		// Forward options (AyuGram: hide sender / hide captions).
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(16), Right: unit.Dp(16)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							chk := material.CheckBox(a.ui.Theme, &fwdHideAuthor, "Hide sender")
							chk.Color = a.ui.p.Accent
							return chk.Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Left: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								chk := material.CheckBox(a.ui.Theme, &fwdHideCaptions, "Hide captions")
								chk.Color = a.ui.p.Accent
								return chk.Layout(gtx)
							})
						}),
					)
				})
		}),
		// Forward comment (AyuGram share sheet, slice 126): optional message
		// shipped before the forwarded batch in each recipient chat.
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(8), Left: unit.Dp(16), Right: unit.Dp(16)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					ed := a.ui.Editor(&fwdComment, "Add a comment…")
					fwdComment.SingleLine = false
					return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
						return layout.UniformInset(unit.Dp(8)).Layout(gtx, ed.Layout)
					})
				})
		}),
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
					// Multi-pick (AyuGram, slice 41): rows toggle recipients.
					fwdSel[c.ChatID] = !fwdSel[c.ChatID]
					a.invalidate()
				}
				sel := fwdSel[c.ChatID]
				bl := material.ButtonLayout(a.ui.Theme, btn)
				bl.Background = a.ui.p.Surface
				if sel {
					bl.Background = a.ui.p.AccentDim
				}
				bl.CornerRadius = 0
				return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(12), Bottom: unit.Dp(12), Left: unit.Dp(16), Right: unit.Dp(16)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return a.selectionCircle(gtx, sel)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Label(unit.Sp(15), c.Title)
									return lbl.Layout(gtx)
								})
							}),
						)
					})
				})
			})
		}),
		// Send bar: commit the selection (slice 41).
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if fwdSendBtn.Clicked(gtx) {
				a.forwardToSelection(srcs, candidates)
			}
			count := 0
			for _, c := range candidates {
				if fwdSel[c.ChatID] {
					count++
				}
			}
			return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(10), Left: unit.Dp(16), Right: unit.Dp(16)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.PrimaryButton(&fwdSendBtn, "Send")
				if count == 0 {
					btn.Background = a.ui.p.SurfaceHi
					btn.Color = a.ui.p.TextFaint
					btn.Text = "Pick recipients"
				} else if count == 1 {
					btn.Text = "Forward to 1 chat"
				} else {
					btn.Text = "Forward to " + itoa(count) + " chats"
				}
				return btn.Layout(gtx)
			})
		}),
	)
}

// forwardToSelection forwards the batch to every selected recipient.
func (a *App) forwardToSelection(srcs []engine.CachedMessage, candidates []engine.ChatInfo) {
	var dsts []engine.ChatInfo
	for _, c := range candidates {
		if fwdSel[c.ChatID] {
			dsts = append(dsts, c)
		}
	}
	if len(dsts) == 0 || len(srcs) == 0 {
		return
	}
	a.mu.Lock()
	a.fwd = nil
	a.mu.Unlock()
	fwdSel = map[string]bool{}
	a.invalidate()
	comment := trimForwardComment(fwdComment.Text())
	go func() {
		ids := make([]string, len(srcs))
		for k := range srcs {
			ids[k] = srcs[k].MsgID
		}
		ok := 0
		for _, dst := range dsts {
			failed := false
			// Comment first (Telegram share-sheet semantics), then the batch.
			for _, step := range forwardCommitSteps(comment, ids) {
				var err error
				switch step.kind {
				case fwdStepComment:
					_, err = a.eng.SendMessage(srcs[0].AccountID, dst.ChatID, step.text, "", nil, false, 0, "", "", false, false, false, false, false)
				case fwdStepForward:
					if len(step.ids) == 1 {
						err = a.eng.ForwardMessage(srcs[0].AccountID, srcs[0].ChatID, step.ids[0], dst.ChatID, fwdHideAuthor.Value, fwdHideCaptions.Value, false, 0)
					} else {
						err = a.eng.ForwardMessages(srcs[0].AccountID, srcs[0].ChatID, step.ids, dst.ChatID, fwdHideAuthor.Value, fwdHideCaptions.Value, false, 0)
					}
				}
				if err != nil {
					a.setToast("Forward failed: " + err.Error())
					failed = true
					break
				}
			}
			if !failed {
				ok++
			}
		}
		if ok > 0 {
			a.setToast("Forwarded to " + itoa(ok) + " chat(s)")
		}
	}()
}

var fwdList widget.List

// fwdSel is the forward picker's recipient selection (chat IDs, slice 41).
var fwdSel = map[string]bool{}

var fwdSendBtn widget.Clickable
