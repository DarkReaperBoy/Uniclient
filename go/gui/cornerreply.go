package gui

import (
	"image"
	"sync"

	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Corner reply button (AyuGram parity slice 157): tdesktop's fast-reply
// pill (HistoryView ReplyButton::Manager + Message::replyButtonParameters,
// lng_fast_reply "Reply") — a small pill at the top-right corner of a
// hovered INCOMING message bubble; tapping starts a reply to it. Gated by
// the Messages-section toggle (tdesktop cornerReply, default ON), hidden
// in selection mode, for own messages, and in read-only chats
// (displayFastReply semantics). Hover tracking rides the chat-pane
// pointer routing (Move/Enter/Leave + the rowBounds hit-test the context
// menu already uses) — no per-row clickables, so the existing hit tree
// (links, quotes, keyboards, pane right-clicks) is untouched.

// effectiveCornerReply resolves the config (nil = tdesktop default ON).
func effectiveCornerReply(v *bool) bool {
	return v == nil || *v
}

// fastReplyGate decides whether the pill renders for a message (pure,
// tested): setting on + regular incoming message + chat allows sending +
// not in selection mode.
func fastReplyGate(cornerOn, selOn, canReply bool, m engine.CachedMessage) bool {
	if !cornerOn || selOn || !canReply || m.IsOutgoing || m.IsService || m.MsgID == "" {
		return false
	}
	return true
}

// ── hover state ──────────────────────────────────────────────────────────

// hoverMu guards hoverMsgID (written from pane event processing on the
// GUI goroutine, read by messageRow in the same frame — cheap and
// contention-free, kept a mutex for the layout-time reads).
var (
	hoverMu     sync.Mutex
	hoverMsgID  string
	hoverChatOn bool // pointer is inside the chat pane
)

// setHoverMsg records the hovered message id ("" = none).
func setHoverMsg(id string) {
	hoverMu.Lock()
	hoverMsgID, hoverChatOn = id, id != ""
	hoverMu.Unlock()
}

// hoveredMsgID reads the tracked id.
func hoveredMsgID() string {
	hoverMu.Lock()
	defer hoverMu.Unlock()
	if !hoverChatOn {
		return ""
	}
	return hoverMsgID
}

// notePaneHover routes pane pointer movement to row hover tracking. Called
// from processPaneEvents for Move/Enter/Leave (same tag as presses).
func (a *App) notePaneHover(f frame, pe pointer.Event) {
	switch pe.Kind {
	case pointer.Leave:
		setHoverMsg("")
	case pointer.Move, pointer.Enter:
		pos := image.Pt(int(pe.Position.X), int(pe.Position.Y))
		idx := a.rowAt(pos)
		if idx < 0 || idx >= len(f.messages) {
			setHoverMsg("")
			return
		}
		setHoverMsg(f.messages[idx].MsgID)
	}
}

// ── pill widgets ─────────────────────────────────────────────────────────

// a.wid.msgReplyBtns pools the pill clickables keyed by chat/message.

func (a *App) msgReplyBtn(key string) *widget.Clickable {
	if btn, ok := a.wid.msgReplyBtns[key]; ok {
		return btn
	}
	btn := new(widget.Clickable)
	a.wid.msgReplyBtns[key] = btn
	return btn
}

// layoutCornerReply renders the pill (or nothing) as an East-anchored
// overlay for the incoming row. The pill floats beside the bubble's
// top-right corner (tdesktop replyCornerCenter placement).
func (a *App) layoutCornerReply(gtx layout.Context, f frame, m *engine.CachedMessage, canReply bool) layout.Dimensions {
	if !fastReplyGate(f.cfg.CornerReply, f.selOn, canReply, *m) {
		return layout.Dimensions{}
	}
	if m.MsgID != hoveredMsgID() {
		return layout.Dimensions{}
	}
	btn := a.msgReplyBtn(m.AccountID + "/" + m.ChatID + "/" + m.MsgID)
	if btn.Clicked(gtx) {
		a.startReply(m)
		return layout.Dimensions{}
	}
	return layout.Inset{Top: unit.Dp(2), Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		bl := material.ButtonLayout(a.ui.Theme, btn)
		bl.Background = a.ui.p.SurfaceHi
		bl.CornerRadius = 10
		return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(4)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						gtx.Constraints.Max.X = gtx.Dp(unit.Dp(14))
						gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(14))
						return iconContentReply.Layout(gtx, a.ui.p.Accent)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(12), "Reply")
							lbl.Color = a.ui.p.Accent
							return lbl.Layout(gtx)
						})
					}),
				)
			})
		})
	})
}

// cornerReplyOverlay wraps an incoming row in a Stack that anchors the
// pill North-East (the bubble's top-right corner); the content renders
// first so inner interactive widgets keep their hit priority and the pill
// sits above the row background.
func (a *App) cornerReplyOverlay(gtx layout.Context, f frame, m *engine.CachedMessage, canReply bool, content func(gtx layout.Context) layout.Dimensions) layout.Dimensions {
	return layout.Stack{Alignment: layout.NE}.Layout(gtx,
		layout.Stacked(func(gtx layout.Context) layout.Dimensions {
			return content(gtx)
		}),
		layout.Stacked(func(gtx layout.Context) layout.Dimensions {
			return a.layoutCornerReply(gtx, f, m, canReply)
		}),
	)
}

// cornerReplyCanSend resolves the chat's reply permission for a message.
func cornerReplyCanSend(f frame, m *engine.CachedMessage) bool {
	chat := chatOf(f, *m)
	if restricted, _ := composerRestricted(chat); restricted {
		return false
	}
	return true
}
