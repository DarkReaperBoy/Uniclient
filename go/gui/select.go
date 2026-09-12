package gui

import (
	"image"
	"io"
	"strings"

	"gioui.org/io/clipboard"
	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"

	"uniclient/engine"
)

// Message selection mode (AyuGram parity §3 "Message selection mode",
// P1): "Select" in the context menu (or tapping rows once the mode is on)
// marks messages with check circles; a header action bar offers Forward
// (engine.ForwardMessages batch), Delete (per-message engine.DeleteMessage
// with revoke=outgoing) and Copy; Escape or ✕ cancels. Selection is
// per-visit GUI state over the real cached messages — nothing faked.

// selection button pool.

// a.wid.fwdComment is the forward picker's optional comment (AyuGram share
// sheet, slice 126): shipped as its own message before the forwarded
// batch in every picked recipient chat.

// forward commit step kinds (pure plan, unit-tested).
const (
	fwdStepComment = iota
	fwdStepForward
)

type fwdCommitStep struct {
	kind int
	text string
	ids  []string
}

// trimForwardComment normalizes the comment box text (whitespace-only
// counts as no comment). Pure.
func trimForwardComment(s string) string {
	return strings.TrimSpace(s)
}

// forwardCommitSteps plans one recipient's commit: the comment message
// first (Telegram share-sheet semantics), then the forward batch. Pure.
func forwardCommitSteps(comment string, ids []string) []fwdCommitStep {
	var steps []fwdCommitStep
	if c := trimForwardComment(comment); c != "" {
		steps = append(steps, fwdCommitStep{kind: fwdStepComment, text: c})
	}
	if len(ids) > 0 {
		steps = append(steps, fwdCommitStep{kind: fwdStepForward, ids: ids})
	}
	return steps
}

var selectionKeyTag = new(struct{})

// ── state transitions ─────────────────────────────────────────────────────

// startSelection enters selection mode with the first message marked.
func (a *App) startSelection(msgID string) {
	a.mu.Lock()
	a.selOn = true
	if a.sel == nil {
		a.sel = map[string]bool{}
	}
	a.sel[msgID] = true
	a.menu = nil
	a.mu.Unlock()
	a.invalidate()
}

// toggleMsgSel flips one message's mark (only in selection mode).
func (a *App) toggleMsgSel(msgID string) {
	a.mu.Lock()
	if a.selOn {
		if a.sel == nil {
			a.sel = map[string]bool{}
		}
		if a.sel[msgID] {
			delete(a.sel, msgID)
		} else {
			a.sel[msgID] = true
		}
	}
	a.mu.Unlock()
	a.invalidate()
}

// cancelSelection leaves selection mode.
func (a *App) cancelSelection() {
	a.mu.Lock()
	a.selOn = false
	a.sel = nil
	a.mu.Unlock()
	a.invalidate()
}

// selectionCount counts marked messages in the open window.
func (a *App) selectionCount() int {
	a.mu.Lock()
	defer a.mu.Unlock()
	if !a.selOn || a.sel == nil {
		return 0
	}
	n := 0
	for range a.sel {
		n++
	}
	return n
}

// selectedMessages returns marked messages from the open chat window (copy).
func (a *App) selectedMessages() []engine.CachedMessage {
	a.mu.Lock()
	k := a.msgFor
	msgs := a.messages
	sel := a.sel
	on := a.selOn
	a.mu.Unlock()
	if !on || sel == nil || k == nil {
		return nil
	}
	var out []engine.CachedMessage
	for i := range msgs {
		if sel[msgs[i].MsgID] {
			out = append(out, msgs[i])
		}
	}
	return out
}

// forwardSelected opens the forward picker over the selected messages.
// reportSelected opens the report flow for the selected messages.
func (a *App) reportSelected() {
	msgs := a.selectedMessages()
	if len(msgs) == 0 {
		return
	}
	batch := make([]engine.CachedMessage, len(msgs))
	copy(batch, msgs)
	a.openReportDialog(batch)
}

// openForward opens the forward picker for a batch and resets the
// recipient selection (slice 41).
func (a *App) openForward(msgs []engine.CachedMessage) {
	fwdSel = map[string]bool{}
	a.wid.fwdComment.SetText("")
	a.mu.Lock()
	a.fwd = msgs
	capOK := a.savedCap
	a.mu.Unlock()
	// Saved Messages as a forward target (slice 116): ensure the saved chat
	// exists before the picker renders.
	if len(msgs) > 0 && capOK[msgs[0].AccountID] {
		a.ensureForwardSavedChat(msgs[0])
	}
	a.invalidate()
}

func (a *App) forwardSelected() {
	msgs := a.selectedMessages()
	if len(msgs) == 0 {
		return
	}
	batch := make([]engine.CachedMessage, len(msgs))
	copy(batch, msgs)
	a.mu.Lock()
	a.selOn = false
	a.sel = nil
	a.mu.Unlock()
	a.openForward(batch)
}

// deleteSelected removes the selected messages (revoke for own messages).
func (a *App) deleteSelected() {
	msgs := a.selectedMessages()
	if len(msgs) == 0 {
		return
	}
	// Bulk delete goes through the same confirm dialog (revoke checkbox).
	chat := engine.ChatInfo{}
	if k := a.msgForLocked(); k != nil {
		for _, c := range a.chatsLocked() {
			if c.AccountID == k.AccountID && c.ChatID == k.ChatID {
				chat = c
				break
			}
		}
	}
	a.cancelSelection()
	a.openDeleteDialog(msgs, chat)
}

// msgForLocked returns a copy of the open chat key.
func (a *App) msgForLocked() *chatKey {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.msgFor == nil {
		return nil
	}
	k := *a.msgFor
	return &k
}

// chatsLocked returns a copy of the chat list.
func (a *App) chatsLocked() []engine.ChatInfo {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.chats
}

// copySelectedText joins the selected messages' text onto the clipboard.
func (a *App) copySelectedText(gtx layout.Context) {
	msgs := a.selectedMessages()
	var b strings.Builder
	for _, m := range msgs {
		if b.Len() > 0 {
			b.WriteByte('\n')
		}
		b.WriteString(m.ContentText)
	}
	gtx.Execute(clipboard.WriteCmd{
		Type: "text/plain",
		Data: io.NopCloser(strings.NewReader(b.String())),
	})
	a.setToast("Copied " + itoa(len(msgs)) + " message(s)")
}

// ── layout ────────────────────────────────────────────────────────────────

// layoutSelBar renders the selection action bar that replaces the pinned
// bar while selecting: "N selected" + Forward / Delete / Copy / ✕. Escape
// cancels.
func (a *App) layoutSelBar(gtx layout.Context, f frame) layout.Dimensions {
	if a.wid.selBarFwdBtn.Clicked(gtx) {
		a.forwardSelected()
	}
	if a.wid.selBarDelBtn.Clicked(gtx) {
		a.deleteSelected()
	}
	if a.wid.selBarCopyBtn.Clicked(gtx) {
		a.copySelectedText(gtx)
	}
	if a.wid.selBarRptBtn.Clicked(gtx) {
		a.reportSelected()
	}
	if a.wid.selBarXBtn.Clicked(gtx) {
		a.cancelSelection()
	}

	// Escape cancels (global key filter, like the media viewer).
	{
		stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
		event.Op(gtx.Ops, selectionKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.cancelSelection()
		}
	}

	n := itoa(len(f.sel))
	return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6), Left: unit.Dp(12), Right: unit.Dp(6)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(14), n+" selected")
					lbl.Color = a.ui.p.Accent
					return lbl.Layout(gtx)
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					return layout.Dimensions{}
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.TextButton(&a.wid.selBarFwdBtn, "Forward")
						btn.Color = a.ui.p.Text
						return btn.Layout(gtx)
					})
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.TextButton(&a.wid.selBarCopyBtn, "Copy")
						btn.Color = a.ui.p.Text
						return btn.Layout(gtx)
					})
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.TextButton(&a.wid.selBarRptBtn, "Report")
						btn.Color = a.ui.p.Error
						return btn.Layout(gtx)
					})
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.TextButton(&a.wid.selBarDelBtn, "Delete")
						btn.Color = a.ui.p.Error
						return btn.Layout(gtx)
					})
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.IconButton(&a.wid.selBarXBtn, iconContentClear, "Cancel selection")
					btn.Color = a.ui.p.TextDim
					btn.Size = unit.Dp(18)
					btn.Inset = layout.UniformInset(unit.Dp(6))
					return btn.Layout(gtx)
				}),
			)
		})
}

// selectionCircle renders the leading check circle for a message row.
func (a *App) selectionCircle(gtx layout.Context, on bool) layout.Dimensions {
	d := gtx.Dp(unit.Dp(22))
	gtx.Constraints.Min = image.Pt(d, d)
	gtx.Constraints.Max = gtx.Constraints.Min
	bg := a.ui.p.SurfaceHi
	if on {
		bg = a.ui.p.Accent
	}
	return roundedFill(gtx, bg, 11, func(gtx layout.Context) layout.Dimensions {
		return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(12), "✓")
			lbl.Color = a.ui.p.TextFaint
			if on {
				lbl.Color = a.ui.p.Text
			}
			return lbl.Layout(gtx)
		})
	})
}
