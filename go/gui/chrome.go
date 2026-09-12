package gui

import (
	"image"
	"log"
	"time"

	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Chat-view chrome (AyuGram parity, matrix §3 "chat view chrome" / top-gap
// #16): the pinned-message bar under the header (tap jumps to the message,
// chevron cycles multiples), the "Unread messages" separator at the position
// the chat was opened at, and the empty-chat intro bubble. All data comes
// from the engine (GetPinnedMessages, ChatInfo.UnreadCount); nothing is
// faked (§1.10).

// chrome button pool.
var (
	pinnedBarBtn   widget.Clickable
	pinnedCycleBtn widget.Clickable
)

// ── pure helpers (unit-tested) ────────────────────────────────────────────

// unreadSepIndex returns the message index the "Unread messages" separator
// is inserted BEFORE (chronological order: the last `unread` are unread).
// Returns -1 when there is nothing to mark.
func unreadSepIndex(n, unread int) int {
	if unread <= 0 || n <= 0 {
		return -1
	}
	i := n - unread
	if i < 0 {
		return 0
	}
	return i
}

// chatRow is one messageList row: a day divider, the unread separator, a
// message, an album group (msgIdx = first member, album = member
// indices), or a sponsored row (spHead caption / spIdx 1-based ad index,
// slice 163 — appended after all message rows).
type chatRow struct {
	day    string
	msgIdx int // -1 for dividers/separator
	unread bool
	album  []int // nil unless an album row (indices into messages)
	spHead bool  // the "Sponsored" caption row
	spIdx  int   // 0 = not sponsored; N = sponsored item N-1
}

// buildChatRows builds the messageList row model: day dividers + messages,
// consecutive same-GroupedID media collapsed into album rows, and the
// unread separator anchored to its boundary message ID (so the separator
// travels with the message across window reloads/jumps, AyuGram behavior).
func buildChatRows(messages []engine.CachedMessage, sepMsgID string) []chatRow {
	rows := make([]chatRow, 0, len(messages)+5)
	var lastDay string
	for i := 0; i < len(messages); {
		m := &messages[i]
		if sepMsgID != "" && m.MsgID == sepMsgID {
			rows = append(rows, chatRow{msgIdx: -1, unread: true})
		}
		day := time.UnixMilli(m.Timestamp).Format("2 Jan 2006")
		if day != lastDay {
			rows = append(rows, chatRow{day: day, msgIdx: -1})
			lastDay = day
		}
		if isAlbumMedia(m) {
			group := []int{i}
			j := i + 1
			for j < len(messages) && messages[j].GroupedID == m.GroupedID && isAlbumMedia(&messages[j]) {
				group = append(group, j)
				j++
			}
			rows = append(rows, chatRow{msgIdx: i, album: group})
			i = j
			continue
		}
		rows = append(rows, chatRow{msgIdx: i})
		i++
	}
	return rows
}

// rowIndexOf returns the ROW index of msgID in the model built by
// buildChatRows (same parameters), or -1 when absent. Album members resolve
// to their album row. Jumps land exactly.
func rowIndexOf(messages []engine.CachedMessage, msgID, sepMsgID string) int {
	for i, r := range buildChatRows(messages, sepMsgID) {
		if r.album != nil {
			for _, mi := range r.album {
				if messages[mi].MsgID == msgID {
					return i
				}
			}
			continue
		}
		if r.msgIdx >= 0 && messages[r.msgIdx].MsgID == msgID {
			return i
		}
	}
	return -1
}

// pinnedPreview is the pinned-bar preview line: the message text, or the
// media label for media-only messages (AyuGram shows "Photo"/"Voice
// message" there).
func pinnedPreview(m *engine.CachedMessage) string {
	if s := quotePreview(m.ContentText, 48); s != "" {
		return s
	}
	if m.HasMedia {
		return engine.MediaPreviewLabel(m.MediaType)
	}
	return ""
}

// pinnedTitle labels the bar: singular, or the counter for multiples.
func pinnedTitle(n int) string {
	if n <= 1 {
		return "Pinned message"
	}
	return "Pinned messages (" + itoa(n) + ")"
}

// ── pinned state ──────────────────────────────────────────────────────────

// loadPinned fetches the chat's pinned messages (async, cached engine call).
func (a *App) loadPinned(k chatKey) {
	go func() {
		pinned, err := a.eng.GetPinnedMessages(k.AccountID, k.ChatID)
		if err != nil {
			log.Printf("gui: pinned: %v", err)
			pinned = nil
		}
		a.mu.Lock()
		if cur := a.selected; cur != nil && *cur == k {
			a.pinned = pinned
			a.pinnedIdx = 0
			a.pinnedLoaded = true
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// captureUnread is inlined in openChat's locked section (state.go).

// cyclePinned advances the shown pinned message (wrap-around).
func (a *App) cyclePinned() {
	a.mu.Lock()
	if a.pinned != nil && len(a.pinned) > 1 {
		a.pinnedIdx = (a.pinnedIdx + 1) % len(a.pinned)
	}
	a.mu.Unlock()
	a.invalidate()
}

// jumpToMessageAt scrolls the message list to a message: in-window messages
// scroll instantly; anything else loads a window around tsFallback (engine
// GetMessages beforeMs/afterMs — the jump path the pagination API was built
// for; used by the pinned bar and search results). Runs on the GUI goroutine.
func (a *App) jumpToMessageAt(msgID string, tsFallback int64) {
	if msgID == "" {
		return
	}
	a.mu.Lock()
	k := a.selected
	msgs := a.messages
	sepMsgID := a.unreadSepMsgID
	a.mu.Unlock()
	if k == nil {
		return
	}

	if row := rowIndexOf(msgs, msgID, sepMsgID); row >= 0 {
		msgList.Position.First = row
		msgList.Position.Offset = 0
		msgList.Position.BeforeEnd = true
		a.invalidate()
		return
	}

	// Not in the window: prefer the pinned metadata, else the caller's
	// timestamp (search results carry it), and load a window around it.
	a.mu.Lock()
	pinned := a.pinned
	a.mu.Unlock()
	target := engine.CachedMessage{MsgID: msgID, Timestamp: tsFallback}
	for i := range pinned {
		if pinned[i].MsgID == msgID {
			target = pinned[i]
			break
		}
	}
	if target.Timestamp <= 0 {
		return
	}
	go func() {
		older, errO := a.eng.GetMessages(k.AccountID, k.ChatID, target.Timestamp, 0, 25)
		newer, errN := a.eng.GetMessages(k.AccountID, k.ChatID, 0, target.Timestamp, 25)
		if errO != nil || errN != nil {
			log.Printf("gui: jump window: %v / %v", errO, errN)
			return
		}
		// older/newer are newest-first; assemble a chronological window:
		// reverse(older) + [target] + newer — target excluded from both
		// (beforeMs/afterMs are strict).
		win := make([]engine.CachedMessage, 0, len(older)+1+len(newer))
		for i, j := 0, len(older)-1; i < j; i, j = i+1, j-1 {
			older[i], older[j] = older[j], older[i]
		}
		win = append(win, older...)
		win = append(win, target)
		win = append(win, newer...)
		a.mu.Lock()
		if cur := a.selected; cur != nil && *cur == *k {
			a.messages = win
			a.olderDone = false
			if row := rowIndexOf(win, msgID, a.unreadSepMsgID); row >= 0 {
				msgList.Position.First = row
				msgList.Position.Offset = 0
				msgList.Position.BeforeEnd = true
			}
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// ── layouts ────────────────────────────────────────────────────────────────

// pinnedBar: the bar under the chat header (AyuGram pinned-message bar):
// pin glyph, title + preview line, cycle chevron for multiple pins; tapping
// the bar jumps to the shown message.
func (a *App) pinnedBar(gtx layout.Context, f frame) layout.Dimensions {
	if len(f.pinned) == 0 {
		return layout.Dimensions{}
	}
	if pinnedBarBtn.Clicked(gtx) {
		if f.pinnedIdx >= 0 && f.pinnedIdx < len(f.pinned) {
			a.jumpToMessageAt(f.pinned[f.pinnedIdx].MsgID, f.pinned[f.pinnedIdx].Timestamp)
		}
	}
	if pinnedCycleBtn.Clicked(gtx) {
		a.cyclePinned()
	}

	idx := f.pinnedIdx
	if idx < 0 || idx >= len(f.pinned) {
		idx = 0
	}
	m := f.pinned[idx]
	preview := pinnedPreview(&m)

	bl := material.ButtonLayout(a.ui.Theme, &pinnedBarBtn)
	bl.Background = a.ui.p.Surface
	bl.CornerRadius = 0
	return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6), Left: unit.Dp(12), Right: unit.Dp(4)}.Layout(gtx,
			func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return iconActionOfflinePin.Layout(gtx, a.ui.p.Accent)
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Label(unit.Sp(12), pinnedTitle(len(f.pinned)))
									lbl.Color = a.ui.p.Accent
									return lbl.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									if preview == "" {
										return layout.Dimensions{}
									}
									lbl := a.ui.Dim(unit.Sp(13), preview)
									lbl.Color = a.ui.p.TextDim
									lbl.MaxLines = 1
									return lbl.Layout(gtx)
								}),
							)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if len(f.pinned) <= 1 {
							return layout.Dimensions{}
						}
						return layout.Inset{Left: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							if pinnedCycleBtn.Clicked(gtx) {
								a.cyclePinned()
							}
							btn := a.ui.IconButton(&pinnedCycleBtn, iconNavChevronRight, "Next pinned")
							btn.Color = a.ui.p.TextDim
							btn.Size = unit.Dp(18)
							btn.Inset = layout.UniformInset(unit.Dp(6))
							return btn.Layout(gtx)
						})
					}),
				)
			})
	})
}

// unreadDivider: the "Unread messages" separator — a hairline with a
// centered pill label (AyuGram style).
func (a *App) unreadDivider(gtx layout.Context) layout.Dimensions {
	const inset = unit.Dp(14)
	return layout.Inset{Top: inset, Bottom: inset, Left: unit.Dp(16), Right: unit.Dp(16)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			w := gtx.Constraints.Max.X
			const pillDp = unit.Dp(24)
			pill := gtx.Dp(pillDp)
			line := gtx.Dp(unit.Dp(1))
			return layout.Stack{}.Layout(gtx,
				layout.Expanded(func(gtx layout.Context) layout.Dimensions {
					defer op.Offset(image.Pt(0, pill/2)).Push(gtx.Ops).Pop()
					defer clip.Rect{Min: image.Pt(0, 0), Max: image.Pt(w, line)}.Push(gtx.Ops).Pop()
					paint.Fill(gtx.Ops, a.ui.p.Divider)
					return layout.Dimensions{Size: image.Pt(w, pill)}
				}),
				layout.Stacked(func(gtx layout.Context) layout.Dimensions {
					return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
						gtx.Constraints.Min = image.Pt(pill, pill)
						gtx.Constraints.Max = image.Pt(pill, pill)
						return roundedFill(gtx, a.ui.p.Accent, 12, func(gtx layout.Context) layout.Dimensions {
							return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), "unread")
								lbl.Color = a.ui.p.Text
								return lbl.Layout(gtx)
							})
						})
					})
				}),
			)
		})
}

// emptyIntro: the "No messages here yet…" bubble (AyuGram empty chat view).
func (a *App) emptyIntro(gtx layout.Context, _ frame) layout.Dimensions {
	return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 14, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(14)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(13), "No messages here yet…")
				lbl.Color = a.ui.p.TextDim
				return lbl.Layout(gtx)
			})
		})
	})
}
