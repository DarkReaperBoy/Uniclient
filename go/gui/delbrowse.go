package gui

// Deleted-messages browser (AyuGram "View deleted messages", matrix row
// 165, slice 97): the header ⋮ menu gains "View deleted messages…" —
// a dialog listing the anti-recall copies kept for this chat (engine
// messages WHERE is_deleted = 1), newest first, with a text filter,
// "Load more" paging and the destructive "Clear all" (existing engine
// ClearDeletedMessages). Read-only rows: the server copy is gone; what
// anti-recall saved is the local copy.

import (
	"image"
	"sort"
	"strings"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"

	"uniclient/engine"
)

// deletedDlgState is the open deleted-messages browser (nil when closed).
type deletedDlgState struct {
	chat   chatKey
	msgs   []engine.CachedMessage
	loaded bool
	busy   bool
	search string
	more   bool
}

var (
	deletedDlgKeyTag = new(struct{})
)

// deletedRowPreview (pure, testable): one browser row — "Sender: first
// line", media rows use the typed label, "(no text)" for empty bodies.
func deletedRowPreview(m engine.CachedMessage) string {
	name := "someone"
	switch {
	case m.SenderName != "":
		name = m.SenderName
	case m.SenderID != "":
		name = "user " + m.SenderID
	}
	return name + ": " + deletedRowBody(m)
}

// deletedRowBody (pure): the row body after the sender prefix.
func deletedRowBody(m engine.CachedMessage) string {
	if m.HasMedia {
		if label := engine.MediaPreviewLabel(m.MediaType); label != "" {
			return label
		}
	}
	t := strings.TrimSpace(m.ContentText)
	if i := strings.IndexByte(t, '\n'); i >= 0 {
		t = t[:i]
	}
	if t == "" {
		return "(no text)"
	}
	return t
}

// sortDeletedNewest (pure): rows newest-first.
func sortDeletedNewest(msgs []engine.CachedMessage) []engine.CachedMessage {
	out := make([]engine.CachedMessage, len(msgs))
	copy(out, msgs)
	sort.SliceStable(out, func(i, j int) bool { return out[i].Timestamp > out[j].Timestamp })
	return out
}

// openDeletedDialog opens the browser for a chat and loads the first page.
func (a *App) openDeletedDialog(k chatKey) {
	a.mu.Lock()
	a.deletedDlg = &deletedDlgState{chat: k}
	a.mu.Unlock()
	a.loadDeleted(false)
	a.invalidate()
}

// closeDeletedDialog dismisses the browser.
func (a *App) closeDeletedDialog() {
	a.mu.Lock()
	a.deletedDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// loadDeleted fetches one page of deleted messages (appending when
// paging; a changed search restarts from the top).
func (a *App) loadDeleted(reset bool) {
	a.mu.Lock()
	d := a.deletedDlg
	if d == nil || d.busy {
		a.mu.Unlock()
		return
	}
	d.busy = true
	if reset {
		d.msgs = nil
		d.loaded = false
	}
	acc, chat, search := d.chat.AccountID, d.chat.ChatID, d.search
	offset := len(d.msgs)
	a.mu.Unlock()
	a.invalidate()

	go func() {
		msgs, err := a.eng.GetDeletedMessages(acc, chat, search, offset, 40)
		msgs = sortDeletedNewest(msgs)
		a.mu.Lock()
		if a.deletedDlg == nil {
			a.mu.Unlock()
			return
		}
		d := a.deletedDlg
		d.busy = false
		d.loaded = true
		if err == nil {
			d.msgs = append(d.msgs, msgs...)
			d.more = len(msgs) == 40
		}
		a.mu.Unlock()
		if err != nil {
			a.setToast("Deleted messages: " + err.Error())
		}
		a.invalidate()
	}()
}

// clearDeletedFromDialog wipes the chat's anti-recall copies (with the
// existing header-menu action's engine call) and reloads the browser.
func (a *App) clearDeletedFromDialog(k chatKey) {
	go func() {
		n, err := a.eng.ClearDeletedMessages(k.AccountID, k.ChatID)
		if err != nil {
			a.setToast("Clear deleted: " + err.Error())
			return
		}
		a.setToast("Cleared " + itoa(int(n)) + " deleted message" + pluralS(int(n)))
		a.loadDeleted(true)
	}()
}

// layoutDeletedDialog renders the browser card over the chat pane.
func (a *App) layoutDeletedDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.deletedDlg
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, deletedDlgKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeDeletedDialog()
		}
	}
	if a.wid.deletedDlgClose.Clicked(gtx) {
		a.closeDeletedDialog()
	}
	if a.wid.deletedDlgMore.Clicked(gtx) && d.more && !d.busy {
		a.loadDeleted(false)
	}
	if a.wid.deletedDlgClear.Clicked(gtx) && len(d.msgs) > 0 {
		k := d.chat
		go a.clearDeletedFromDialog(k)
	}

	paintScrimRect(gtx)

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(380))
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(480))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(14)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.H3("Deleted messages")
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								btn := a.ui.IconButton(&a.wid.deletedDlgClose, iconContentClear, "Close")
								btn.Color = a.ui.p.TextDim
								return btn.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(12), "Anti-recall copies kept locally — newest first.")
							lbl.Color = a.ui.p.TextFaint
							return lbl.Layout(gtx)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						if !d.loaded {
							return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return a.loadingNote(gtx)
							})
						}
						if len(d.msgs) == 0 {
							return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(13), "Nothing deleted was captured in this chat")
								lbl.Color = a.ui.p.TextFaint
								return lbl.Layout(gtx)
							})
						}
						rows := make([]layout.FlexChild, 0, len(d.msgs))
						for _, m := range d.msgs {
							rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return a.deletedDlgRow(gtx, m)
							}))
						}
						return layout.Flex{Axis: layout.Vertical, Spacing: layout.Spacing(4)}.Layout(gtx, rows...)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if !d.more || d.busy {
							return layout.Dimensions{}
						}
						return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.TextButton(&a.wid.deletedDlgMore, "Load more")
							btn.Color = a.ui.p.Accent
							return btn.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if len(d.msgs) == 0 {
							return layout.Dimensions{}
						}
						return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.TextButton(&a.wid.deletedDlgClear, "Clear all")
							btn.Color = a.ui.p.Error
							return btn.Layout(gtx)
						})
					}),
				)
			})
		})
	})
}

// deletedDlgRow: sender + deleted-at header, preview body.
func (a *App) deletedDlgRow(gtx layout.Context, m engine.CachedMessage) layout.Dimensions {
	return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
		return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(12), deletedRowPreview(m))
							lbl.MaxLines = 2
							return lbl.Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							when := fmtTime(m.Timestamp)
							if m.DeletedAt != 0 {
								when = fmtTime(m.DeletedAt)
							}
							lbl := a.ui.Dim(unit.Sp(11), when)
							return lbl.Layout(gtx)
						}),
					)
				}),
			)
		})
	})
}
