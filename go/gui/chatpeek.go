package gui

import (
	"image"
	"strings"
	"time"

	"gioui.org/font"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/unit"

	"uniclient/engine"
)

const peekHoverDelay = 600 * time.Millisecond

const peekMaxRunes = 48

type peekLine struct {
	sender string
	text   string
}

func peekMsgLine(m engine.CachedMessage) (sender, text string) {
	txt := strings.TrimSpace(m.ContentText)
	if txt == "" && m.MediaType != 0 {
		txt = engine.MediaPreviewLabel(m.MediaType)
	}
	txt = strings.Join(strings.Fields(txt), " ")
	r := []rune(txt)
	if len(r) > peekMaxRunes {
		txt = strings.TrimSpace(string(r[:peekMaxRunes])) + "…"
	}
	if m.IsOutgoing {
		return "You", txt
	}
	if m.SenderName != "" {
		return m.SenderName, txt
	}
	return "", txt
}

func peekLines(msgs []engine.CachedMessage, max int) []peekLine {
	var keep []engine.CachedMessage
	for _, m := range msgs {
		if m.IsService {
			continue
		}
		keep = append(keep, m)
	}
	if len(keep) > max {
		keep = keep[:max]
	}
	var out []peekLine
	for i := len(keep) - 1; i >= 0; i-- {
		s, txt := peekMsgLine(keep[i])
		out = append(out, peekLine{sender: s, text: txt})
	}
	return out
}

func peekAnchorY(mouseY, peekH, winH int) int {
	y := mouseY - peekH/5
	if y+peekH > winH {
		y = winH - peekH
	}
	if y < 0 {
		y = 0
	}
	return y
}

type chatPeekState struct {
	accountID string
	chatID    string
	title     string

	lines []peekLine
}

func (a *App) noteChatHover(c engine.ChatInfo) {
	key := c.AccountID + "/" + c.ChatID
	a.hoverFrame = true
	a.mu.Lock()
	same := a.hoverChatKey == key
	if !same {
		a.hoverChatKey = key
		a.hoverSince = time.Now()
		a.chatPeek = nil
	}
	a.mu.Unlock()
	if same {
		return
	}
	time.AfterFunc(peekHoverDelay+50*time.Millisecond, func() {
		a.mu.Lock()
		key := a.hoverChatKey
		armed := key != "" && time.Since(a.hoverSince) >= peekHoverDelay
		a.mu.Unlock()
		if !armed {
			return
		}
		accID, chatID := splitChatKey(key)
		if accID == "" {
			return
		}
		msgs, err := a.eng.GetMessages(accID, chatID, 0, 0, 3)
		a.mu.Lock()
		if a.hoverChatKey != key || a.chatPeek != nil {
			a.mu.Unlock()
			return
		}
		if err != nil {
			a.mu.Unlock()
			return
		}
		var title string
		for _, ch := range a.chats {
			if ch.AccountID == accID && ch.ChatID == chatID {
				title = ch.Title
				break
			}
		}
		a.chatPeek = &chatPeekState{
			accountID: accID,
			chatID:    chatID,
			title:     title,
			lines:     peekLines(msgs, 3),
		}
		a.mu.Unlock()
		a.invalidate()
	})
}

func (a *App) resetChatHoverFrame() {
	a.hoverFrame = false
}

func (a *App) checkChatHoverFrame() {
	if a.hoverFrame {
		return
	}
	a.mu.Lock()
	was := a.hoverChatKey != "" || a.chatPeek != nil
	a.hoverChatKey = ""
	a.hoverSince = time.Time{}
	a.chatPeek = nil
	a.mu.Unlock()
	if was {
		a.invalidate()
	}
}

func splitChatKey(key string) (accountID, chatID string) {
	i := strings.IndexByte(key, '/')
	if i < 0 {
		return "", ""
	}
	return key[:i], key[i+1:]
}

func (a *App) hideChatPeek() {
	a.mu.Lock()
	a.chatPeek = nil
	a.hoverChatKey = ""
	a.mu.Unlock()
}

func (a *App) layoutChatPeek(gtx layout.Context, f frame) layout.Dimensions {
	p := f.chatPeek
	if p == nil {
		return layout.Dimensions{}
	}

	w := gtx.Dp(unit.Dp(280))
	lineH := gtx.Dp(unit.Dp(18))
	h := gtx.Dp(unit.Dp(10)) + gtx.Dp(unit.Dp(22)) + gtx.Dp(unit.Dp(6)) +
		len(p.lines)*lineH + gtx.Dp(unit.Dp(10))

	x := f.sidebarW + gtx.Dp(unit.Dp(10))
	y := peekAnchorY(f.hoverPos.Y, h, gtx.Constraints.Max.Y)

	defer op.Offset(image.Pt(x, y)).Push(gtx.Ops).Pop()
	gtx.Constraints = layout.Constraints{Max: image.Pt(w, h), Min: image.Pt(w, h)}
	return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
		var children []layout.FlexChild
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Label(unit.Sp(14), p.title)
				lbl.Font.Weight = font.SemiBold
				return lbl.Layout(gtx)
			})
		}))
		for _, ln := range p.lines {
			ln := ln
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Left: unit.Dp(10), Right: unit.Dp(10), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					parts := []layout.FlexChild{}
					if ln.sender != "" {
						parts = append(parts, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Right: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(12), ln.sender+":")
								return lbl.Layout(gtx)
							})
						}))
					}
					parts = append(parts, layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(12), ln.text)
						return lbl.Layout(gtx)
					}))
					return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, parts...)
				})
			}))
		}
		if len(p.lines) == 0 {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Left: unit.Dp(10), Right: unit.Dp(10), Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(12), "No messages")
					return lbl.Layout(gtx)
				})
			}))
		}
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
	})
}
