package gui

import (
	"image"
	"log"
	"strings"

	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Emoji picker (AyuGram parity §4 "composer helpers" / top-gap #15): the 😊
// button next to the composer opens a category-tabbed emoji panel above the
// input; taps insert at the caret (widget.Editor.Insert) and keep the panel
// open for multi-insert, with a backspace key. Emoji are plain text rendered
// through the Noto Emoji fallback face registered in theme.go — no engine
// involvement, nothing faked (§1.10). Sticker/GIF tabs (engine sticker APIs)
// are the follow-up slice.

// emojiCategory is one tab: a representative emoji, a label, and the grid.
type emojiCategory struct {
	icon   string
	label  string
	emojis []string
}

// emojiCategories mirrors AyuGram's emoji panel order (minus recent-stickers,
// which needs a persistence layer).
var emojiCategories = []emojiCategory{
	{"😀", "Smileys", []string{
		"😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂", "🙃", "😉", "😊",
		"😇", "🥰", "😍", "🤩", "😘", "😗", "😚", "😙", "🥲", "😋", "😛", "😜",
		"🤪", "😝", "🤑", "🤗", "🤭", "🤫", "🤔", "🤐", "🤨", "😐", "😑", "😶",
		"😏", "😒", "🙄", "😬", "🤥", "😌", "😔", "😪", "🤤", "😴", "😷", "🤒",
		"🤕", "🤢", "🤮", "🥵", "🥶", "🥴", "😵", "🤯", "🥳", "😎", "🤓", "🧐",
		"😕", "😟", "🙁", "😮", "😯", "😲", "😳", "🥺", "😢", "😭", "😤", "😠",
		"😡", "🤬", "😈", "💀", "💩", "🤡", "👻",
	}},
	{"👋", "Gestures", []string{
		"👋", "🤚", "🖐", "✋", "🖖", "👌", "🤌", "🤏", "✌", "🤞", "🤟", "🤘",
		"🤙", "👈", "👉", "👆", "👇", "☝", "👍", "👎", "✊", "👊", "🤛", "🤜",
		"👏", "🙌", "👐", "🤲", "🤝", "🙏", "✍", "💅", "🤳", "💪", "🦾", "👀",
	}},
	{"❤️", "Hearts", []string{
		"❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔", "❣", "💕",
		"💞", "💓", "💗", "💖", "💘", "💝", "💟", "♥", "💌", "😻", "😽", "🫶",
	}},
	{"🐶", "Animals", []string{
		"🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮",
		"🐷", "🐸", "🐵", "🙈", "🙉", "🙊", "🐒", "🐔", "🐧", "🐦", "🐤", "🦆",
		"🦅", "🦉", "🦇", "🐺", "🐗", "🐴", "🦄", "🐝", "🐛", "🦋", "🐌", "🐞",
		"🐜", "🦂", "🐢", "🐍", "🦎", "🐙", "🦑", "🦐", "🦞", "🦀", "🐡", "🐠",
		"🐟", "🐬", "🐳", "🐋", "🦈", "🐊", "🐘", "🦒", "🦘", "🐄", "🐎", "🐖",
	}},
	{"🍎", "Food", []string{
		"🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍈", "🍒",
		"🍑", "🍍", "🥭", "🥥", "🥝", "🍅", "🥑", "🍆", "🥔", "🥕", "🌽", "🌶",
		"🥒", "🥬", "🥦", "🧄", "🧅", "🍄", "🥜", "🍞", "🥐", "🥖", "🥨", "🥞",
		"🧇", "🧈", "🍳", "🥚", "🧀", "🍖", "🍗", "🥩", "🥓", "🍔", "🍟", "🍕",
		"🌭", "🥪", "🌮", "🌯", "🥗", "🍝", "🍜", "🍲", "🍣", "🍱", "🥟", "🍤",
	}},
	{"⚽", "Activity", []string{
		"⚽", "🏀", "🏈", "⚾", "🥎", "🎾", "🏐", "🏉", "🥏", "🎱", "🏓", "🏸",
		"🏒", "🏑", "🥍", "🏏", "🥊", "🥋", "⛳", "🎣", "🤿", "🎽", "🎿", "🛷",
		"🥌", "🎯", "🏹", "🪁", "🎮", "🕹", "🎰", "🎲", "🎖", "🏆", "🏅", "🥇",
	}},
	{"🚗", "Travel", []string{
		"🚗", "🚕", "🚙", "🚌", "🚎", "🏎", "🚓", "🚑", "🚒", "🚐", "🚚", "🚛",
		"🚜", "🛵", "🏍", "🚲", "🛴", "🚨", "🚦", "🚧", "🚏", "🗺", "🗿", "🗽",
		"🗼", "🏰", "🏯", "🎡", "🎢", "🎠", "⛲", "⛱", "🏖", "🏝", "🏜", "🌋",
		"⛰", "🏔", "🏕", "⛺", "🏠", "🏡", "🏢", "🏥", "🏦", "🏨", "🏫", "🏭",
	}},
	{"⌚", "Objects", []string{
		"⌚", "📱", "📲", "💻", "⌨", "🖥", "🖨", "🖱", "🖲", "💽", "💾", "💿",
		"📀", "🧮", "🎥", "📷", "📹", "📼", "🔍", "🔎", "🕯", "💡", "🔦", "🏮",
		"📔", "📓", "📒", "📃", "📜", "📄", "📰", "🔖", "🏷", "💰", "🪙", "💳",
		"✉", "📧", "📨", "📩", "📤", "📥", "📦", "📮", "🗳", "✏", "✒", "🖌",
		"🖍", "📝", "💼", "📁", "📂", "🗓", "📈", "📋", "📌", "📍", "📎", "✂",
	}},
	{"✅", "Symbols", []string{
		"✅", "❌", "❓", "❗", "‼", "⁉", "💯", "🔥", "⭐", "🌟", "✨", "⚡",
		"💥", "☄", "🌈", "☀", "🌤", "☁", "🌧", "⛈", "❄", "☃", "⛄", "🌬",
		"💨", "💧", "💦", "☔", "🌊", "♻", "⚠", "♠", "♦", "♣", "♪", "🔵",
		"➕", "➖", "➗", "✖", "♾", "🔴", "🟠", "🟡", "🟢", "⚪", "🟣", "⚫",
	}},
}

// emoji button pool.
var (
	emojiBtn       widget.Clickable // the 😊 composer toggle
	emojiBackspace widget.Clickable
	emojiCellBtns  []widget.Clickable
	emojiSearchEd  widget.Editor // panel search (keyword -> emoji, slice 50)
	emojiTabBtns   []widget.Clickable
)

var emojiList widget.List // grid scroller
var emojiTabsList widget.List

// ── pure helpers (unit-tested) ────────────────────────────────────────────

// emojiRowCount returns the grid rows for n items at cols columns.
func emojiRowCount(n, cols int) int {
	if cols <= 0 {
		return 0
	}
	r := n / cols
	if n%cols != 0 {
		r++
	}
	return r
}

// emojiCategorySafe clamps a tab index into the category list.
func emojiCategorySafe(i int) emojiCategory {
	if i < 0 || i >= len(emojiCategories) {
		return emojiCategories[0]
	}
	return emojiCategories[i]
}

// ── state transitions ─────────────────────────────────────────────────────

// toggleEmojiPanel shows/hides the picker; switching to the emoji panel
// closes the attach popup (one helper surface at a time, AyuGram behavior).
func (a *App) toggleEmojiPanel() {
	a.mu.Lock()
	a.attachMenuOpen = false
	a.emojiOpen = !a.emojiOpen
	a.mu.Unlock()
	a.invalidate()
}

// closeEmojiPanel hides the picker.
func (a *App) closeEmojiPanel() {
	a.mu.Lock()
	a.emojiOpen = false
	a.mu.Unlock()
	a.invalidate()
}

// setEmojiTab switches the visible category.
func (a *App) setEmojiTab(i int) {
	a.mu.Lock()
	if i >= 0 && i < len(emojiCategories) {
		a.emojiTab = i
	}
	a.mu.Unlock()
	a.invalidate()
}

// insertEmoji inserts one emoji at the composer caret (AyuGram: panel stays
// open for multi-insert). Called from the GUI goroutine.
func (a *App) insertEmoji(e string) {
	if e == "" {
		return
	}
	composer.Insert(e)
	a.invalidate()
}

// emojiBackspace deletes the cluster before the caret.
func (a *App) emojiBackspaceAt() {
	composer.Delete(-1)
	a.invalidate()
}

// ── emoji search (AyuGram keyword search, slice 50) ────────────────────────

// filterEmojiByKeyword (pure, testable): emojis matching a keyword query —
// case-insensitive substring over the engine keyword list (Telegram
// MessagesGetEmojiKeywords: keyword -> emoticons/emojis), deduped, capped.
func filterEmojiByKeyword(kws []engine.EmojiKeywordEntry, q string, cap int) []string {
	q = strings.ToLower(strings.TrimSpace(q))
	if q == "" || len(kws) == 0 {
		return nil
	}
	seen := make(map[string]struct{}, 64)
	out := make([]string, 0, 32)
	for _, kw := range kws {
		if !strings.Contains(strings.ToLower(kw.Keyword), q) {
			continue
		}
		for _, e := range kw.Emoticons {
			if e == "" {
				continue
			}
			if _, dup := seen[e]; dup {
				continue
			}
			seen[e] = struct{}{}
			out = append(out, e)
			if len(out) >= cap {
				return out
			}
		}
	}
	return out
}

// emojiKeywords returns the cached keyword list (nil until fetched).
func (a *App) emojiKeywords() []engine.EmojiKeywordEntry {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.emojiKws
}

// emojiKeywordsLoaded reports whether the keyword map arrived.
func (a *App) emojiKeywordsLoaded() bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.emojiKwsLoaded
}

// ensureEmojiKeywords fetches the keyword map once (best-effort; failures
// leave the panel as the plain category grid).
func (a *App) ensureEmojiKeywords(accountID string) {
	if accountID == "" {
		return
	}
	a.mu.Lock()
	if a.emojiKwsLoaded || a.emojiKwsFetching {
		a.mu.Unlock()
		return
	}
	a.emojiKwsFetching = true
	a.mu.Unlock()

	go func() {
		kws, err := a.eng.GetEmojiKeywords(accountID, "en")
		a.mu.Lock()
		a.emojiKwsFetching = false
		if err == nil && kws != nil {
			a.emojiKws = kws.Keywords
			a.emojiKwsLoaded = true
		}
		a.mu.Unlock()
		if err != nil {
			log.Printf("gui: emoji keywords: %v", err)
		}
		a.invalidate()
	}()
}

// ── layout ────────────────────────────────────────────────────────────────

// layoutEmojiPanel renders the category-tabbed emoji grid above the composer.
// Records its rect for outside-press dismissal (menu.go onPanePress).
func (a *App) layoutEmojiPanel(gtx layout.Context, f frame) layout.Dimensions {
	cat := emojiCategorySafe(f.emojiTab)

	// Search (slice 50): while the field has a query the grid shows keyword
	// matches from the engine (Telegram emoji keywords), fetched lazily.
	query := strings.TrimSpace(emojiSearchEd.Text())
	var results []string
	searching := len([]rune(query)) >= 2
	if searching {
		acc := ""
		if f.selected != nil {
			acc = f.selected.AccountID
		} else if len(f.accounts) > 0 {
			acc = f.accounts[0].ID
		}
		a.ensureEmojiKeywords(acc)
		results = filterEmojiByKeyword(a.emojiKeywords(), query, 64)
	}

	emojis := cat.emojis
	if searching {
		emojis = results
	}
	n := len(emojis)
	if n < 1 {
		n = 1
	}
	growClickables(&emojiCellBtns, n)
	growClickables(&emojiTabBtns, len(emojiCategories))

	if emojiBackspace.Clicked(gtx) {
		a.emojiBackspaceAt()
	}

	const cols = 8
	const cellDp = unit.Dp(36)
	panelW := gtx.Constraints.Max.X - gtx.Dp(unit.Dp(20))
	if panelW > gtx.Dp(unit.Dp(360)) {
		panelW = gtx.Dp(unit.Dp(360))
	}
	if panelW < gtx.Dp(unit.Dp(220)) {
		panelW = gtx.Dp(unit.Dp(220))
	}
	panelH := gtx.Dp(unit.Dp(292))
	if panelH > gtx.Constraints.Max.Y/2 {
		panelH = gtx.Constraints.Max.Y / 2
	}

	pos := image.Pt(gtx.Dp(unit.Dp(10)), gtx.Constraints.Max.Y-panelH-gtx.Dp(unit.Dp(78)))
	a.emojiRect = image.Rect(pos.X, pos.Y, pos.X+panelW, pos.Y+panelH)

	defer op.Offset(pos).Push(gtx.Ops).Pop()
	gtx.Constraints = layout.Constraints{Max: image.Pt(panelW, panelH), Min: image.Pt(panelW, panelH)}
	return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			// Top-level mode row: Emoji / Stickers / GIFs (slice 58).
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.layoutPanelModeRow(gtx, f)
			}),
			// Search row (AyuGram emoji search, slice 50).
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if f.emojiMode != panelModeEmoji {
					return layout.Dimensions{}
				}
				return layout.Inset{Left: unit.Dp(8), Right: unit.Dp(8), Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return roundedFill(gtx, a.ui.p.SurfaceHi, 8, func(gtx layout.Context) layout.Dimensions {
						return layout.UniformInset(unit.Dp(4)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							ed := a.ui.Editor(&emojiSearchEd, "Search emoji")
							ed.TextSize = unit.Sp(13)
							return ed.Layout(gtx)
						})
					})
				})
			}),
			// Tab row.
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if f.emojiMode != panelModeEmoji {
					return layout.Dimensions{}
				}
				gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(44))
				return layout.Inset{Left: unit.Dp(4), Right: unit.Dp(4), Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					emojiTabsList.Axis = layout.Horizontal
					tl := material.List(a.ui.Theme, &emojiTabsList)
					return tl.Layout(gtx, len(emojiCategories), func(gtx layout.Context, i int) layout.Dimensions {
						btn := &emojiTabBtns[i]
						if btn.Clicked(gtx) {
							a.setEmojiTab(i)
						}
						cur := i == f.emojiTab
						return layout.Inset{Right: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							bl := material.ButtonLayout(a.ui.Theme, btn)
							bl.Background = a.ui.p.Surface
							bl.CornerRadius = 8
							if cur {
								bl.Background = a.ui.p.AccentDim
							}
							return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Label(unit.Sp(13), emojiCategories[i].icon+" "+emojiCategories[i].label)
									if cur {
										lbl.Color = a.ui.p.Text
									} else {
										lbl.Color = a.ui.p.TextDim
									}
									return lbl.Layout(gtx)
								})
							})
						})
					})
				})
			}),
			// Divider.
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.ui.Divider(gtx)
			}),
			// Grid (search results while querying, categories otherwise).
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				if f.emojiMode == panelModeStickers {
					return a.layoutStickerMode(gtx, f)
				}
				if f.emojiMode == panelModeGifs {
					return a.layoutGifMode(gtx, f)
				}
				if searching && len(results) == 0 {
					return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						note := "Searching…"
						if a.emojiKeywordsLoaded() {
							note = "No emoji found"
						}
						lbl := a.ui.Dim(unit.Sp(12), note)
						return lbl.Layout(gtx)
					})
				}
				rows := emojiRowCount(n, cols)
				emojiList.Axis = layout.Vertical
				gl := material.List(a.ui.Theme, &emojiList)
				return gl.Layout(gtx, rows, func(gtx layout.Context, r int) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, cellsForRow(emojis, r*cols, cols, func(gtx layout.Context, idx int, e string) layout.Dimensions {
						btn := &emojiCellBtns[idx]
						if btn.Clicked(gtx) {
							a.insertEmoji(e)
						}
						cell := gtx.Dp(cellDp)
						gtx.Constraints.Max.X = cell
						gtx.Constraints.Max.Y = cell
						gtx.Constraints.Min = image.Pt(cell, cell)
						bl := material.ButtonLayout(a.ui.Theme, btn)
						bl.Background = a.ui.p.Surface
						bl.CornerRadius = 8
						return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(20), e)
								lbl.Color = a.ui.p.Text
								return lbl.Layout(gtx)
							})
						})
					})...)
				})
			}),
			// Bottom bar: backspace key (right-aligned, AyuGram layout).
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if f.emojiMode != panelModeEmoji {
					return layout.Dimensions{}
				}
				gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(40))
				return layout.Inset{Right: unit.Dp(6), Bottom: unit.Dp(4), Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							return layout.Dimensions{}
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.IconButton(&emojiBackspace, iconContentBackspace, "Backspace")
							btn.Color = a.ui.p.TextDim
							btn.Background = a.ui.p.SurfaceHi
							btn.Size = unit.Dp(20)
							btn.Inset = layout.UniformInset(unit.Dp(8))
							return btn.Layout(gtx)
						}),
					)
				})
			}),
		)
	})
}

// cellsForRow builds the grid children for one row: items [start, start+cols)
// padded with spacers to keep the grid aligned (the list row is Rigid-height).
func cellsForRow(emojis []string, start, cols int, cell func(gtx layout.Context, idx int, e string) layout.Dimensions) []layout.FlexChild {
	out := make([]layout.FlexChild, 0, cols)
	for c := 0; c < cols; c++ {
		i := start + c
		if i < len(emojis) {
			idx, e := i, emojis[i]
			out = append(out, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return cell(gtx, idx, e)
			}))
		} else {
			out = append(out, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Dimensions{}
			}))
		}
	}
	return out
}
