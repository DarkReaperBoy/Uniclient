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

func effectiveCornerReply(v *bool) bool {
	return v == nil || *v
}

func fastReplyGate(cornerOn, selOn, canReply bool, m engine.CachedMessage) bool {
	if !cornerOn || selOn || !canReply || m.IsOutgoing || m.IsService || m.MsgID == "" {
		return false
	}
	return true
}

var (
	hoverMu     sync.Mutex
	hoverMsgID  string
	hoverChatOn bool
)

func setHoverMsg(id string) {
	hoverMu.Lock()
	hoverMsgID, hoverChatOn = id, id != ""
	hoverMu.Unlock()
}

func hoveredMsgID() string {
	hoverMu.Lock()
	defer hoverMu.Unlock()
	if !hoverChatOn {
		return ""
	}
	return hoverMsgID
}

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

func (a *App) msgReplyBtn(key string) *widget.Clickable {
	if btn, ok := a.wid.msgReplyBtns[key]; ok {
		return btn
	}
	btn := new(widget.Clickable)
	a.wid.msgReplyBtns[key] = btn
	return btn
}

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

func cornerReplyCanSend(f frame, m *engine.CachedMessage) bool {
	chat := chatOf(f, *m)
	if restricted, _ := composerRestricted(chat); restricted {
		return false
	}
	return true
}
