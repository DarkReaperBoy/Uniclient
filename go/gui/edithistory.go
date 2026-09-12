package gui

// Edit-history viewer (AyuGram "Edits history", matrix row 164, slice 96):
// the message context menu gains "Edits history" for edited messages — a
// dialog listing every locally-known revision of the message (engine
// edited_messages table, newest first, "Load more" paging). Anti-recall's
// revision copies are exactly what AyuGram's edits-history box shows.

import (
	"image"
	"strings"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"

	"uniclient/engine"
)

// editHistState is the open edits-history dialog (nil when closed).
type editHistState struct {
	msg       engine.CachedMessage
	revisions []engine.EditRevision
	loaded    bool
	busy      bool
	more      bool // another page exists
}

var (
	editHistKeyTag = new(struct{})
)

// editHistRowTitle (pure, testable): display name for one revision row.
func editHistRowTitle(r engine.EditRevision) string {
	if r.SenderName != "" {
		return r.SenderName
	}
	if r.SenderID != "" {
		return "user " + r.SenderID
	}
	return "someone"
}

// editHistRowPreview (pure, testable): the revision's text, first line,
// trimmed; "(no text)" for empty bodies.
func editHistRowPreview(text string) string {
	t := strings.TrimSpace(text)
	if t == "" {
		return "(no text)"
	}
	if i := strings.IndexByte(t, '\n'); i >= 0 {
		t = t[:i]
	}
	return t
}

// editsMenuGate (pure): when the context menu offers "Edits history" —
// an edited, non-service message with the revisions lookup resolved
// (nil state hides the item until openMenu's lookup lands, mirroring
// the shadow-ban gate).
func editsMenuGate(m engine.CachedMessage, stateKnown, hasEdits bool) bool {
	return m.EditedAt != 0 && !m.IsService && stateKnown && hasEdits
}

// openEditHistDialog shows the revision list for a message.
func (a *App) openEditHistDialog(m *engine.CachedMessage) {
	if m == nil {
		return
	}
	msg := *m
	a.mu.Lock()
	a.editHistDlg = &editHistState{msg: msg}
	a.mu.Unlock()
	a.invalidate()
	a.loadEditHist(0)
}

// closeEditHistDialog dismisses the dialog.
func (a *App) closeEditHistDialog() {
	a.mu.Lock()
	a.editHistDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// loadEditHist fetches one page of revisions (appending when paging).
func (a *App) loadEditHist(offset int) {
	a.mu.Lock()
	d := a.editHistDlg
	if d == nil || d.busy {
		a.mu.Unlock()
		return
	}
	d.busy = true
	acc, chat, msgID := d.msg.AccountID, d.msg.ChatID, d.msg.MsgID
	a.mu.Unlock()
	a.invalidate()

	go func() {
		revs, err := a.eng.GetEditRevisions(acc, chat, msgID, offset, 40)
		a.mu.Lock()
		if a.editHistDlg == nil {
			a.mu.Unlock()
			return
		}
		d := a.editHistDlg
		d.busy = false
		d.loaded = true
		if err == nil {
			d.revisions = append(d.revisions, revs...)
			d.more = len(revs) == 40 // a full page may mean more behind it
		}
		a.mu.Unlock()
		if err != nil {
			a.setToast("Edits history: " + err.Error())
		}
		a.invalidate()
	}()
}

// layoutEditHistDialog renders the revisions card over the chat pane.
func (a *App) layoutEditHistDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.editHistDlg
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, editHistKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeEditHistDialog()
		}
	}
	if a.wid.editHistClose.Clicked(gtx) {
		a.closeEditHistDialog()
	}
	if a.wid.editHistMore.Clicked(gtx) && d.more && !d.busy {
		a.loadEditHist(len(d.revisions))
	}

	paintScrimRect(gtx)

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(360))
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(480))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(14)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.H3("Edits history")
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								btn := a.ui.IconButton(&a.wid.editHistClose, iconContentClear, "Close")
								btn.Color = a.ui.p.TextDim
								return btn.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(12), "Saved by anti-recall — every locally-known revision, newest first.")
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
						if len(d.revisions) == 0 {
							return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(13), "No revisions were captured")
								lbl.Color = a.ui.p.TextFaint
								return lbl.Layout(gtx)
							})
						}
						rows := make([]layout.FlexChild, 0, len(d.revisions))
						for _, r := range d.revisions {
							rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return a.editHistRow(gtx, r)
							}))
						}
						return layout.Flex{Axis: layout.Vertical, Spacing: layout.Spacing(4)}.Layout(gtx, rows...)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if !d.more || d.busy {
							return layout.Dimensions{}
						}
						return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.TextButton(&a.wid.editHistMore, "Load more")
							btn.Color = a.ui.p.Accent
							return btn.Layout(gtx)
						})
					}),
				)
			})
		})
	})
}

// editHistRow: sender + timestamp header, text preview body.
func (a *App) editHistRow(gtx layout.Context, r engine.EditRevision) layout.Dimensions {
	return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
		return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(13), editHistRowTitle(r))
							lbl.MaxLines = 1
							return lbl.Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(11), fmtTime(r.Timestamp))
							return lbl.Layout(gtx)
						}),
					)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(13), editHistRowPreview(r.ContentText))
						lbl.MaxLines = 3
						return lbl.Layout(gtx)
					})
				}),
			)
		})
	})
}
