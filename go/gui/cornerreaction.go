package gui

import (
	"strconv"
	"strings"
	"sync"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/cores"
	"uniclient/engine"
)

func effectiveCornerReaction(v *bool) bool {
	return v == nil || *v
}

func favoriteReactionOrDefault(v string) string {
	if v == "" {
		return "👍"
	}
	return v
}

func cornerReactGate(cornerOn, selOn bool, m engine.CachedMessage) bool {
	if !cornerOn || selOn || m.IsService || m.MsgID == "" {
		return false
	}
	return true
}

func customKeyDocID(key string) (int64, bool) {
	if !strings.HasPrefix(key, "custom_") {
		return 0, false
	}
	docID, err := strconv.ParseInt(key[7:], 10, 64)
	if err != nil || docID <= 0 {
		return 0, false
	}
	return docID, true
}

func ownHasReaction(reactions []cores.Reaction, emoji string) bool {
	favDoc, favCustom := customKeyDocID(emoji)
	for _, r := range reactions {
		if !r.ByMe {
			continue
		}
		if favCustom {
			if r.Emoji == "" && r.DocumentID == favDoc {
				return true
			}
			continue
		}
		if r.Emoji == emoji {
			return true
		}
	}
	return false
}

func toggleOwnReactionEmojis(reactions []cores.Reaction, fav string) []string {
	own := make([]string, 0, len(reactions)+1)
	hasFav := false
	for _, r := range reactions {
		if !r.ByMe {
			continue
		}
		key := r.Emoji
		if key == "" && r.DocumentID != 0 {
			key = customReactionKey(r.DocumentID)
		}
		if key == "" {
			continue
		}
		if key == fav {
			hasFav = true
			continue
		}
		own = append(own, key)
	}
	if !hasFav {
		own = append(own, fav)
	}
	return own
}

var (
	favMu        sync.Mutex
	favReactions = map[string]string{}
	favAttempted = map[string]bool{}
)

func setFavoriteReaction(accountID, emoji string) {
	favMu.Lock()
	favReactions[accountID] = emoji
	favMu.Unlock()
}

func favoriteReactionFor(accountID string) string {
	favMu.Lock()
	defer favMu.Unlock()
	return favReactions[accountID]
}

func (a *App) loadFavoriteReaction(accountID string) {
	if accountID == "" {
		return
	}
	favMu.Lock()
	_, attempted := favAttempted[accountID]
	if !attempted {
		favAttempted[accountID] = true
	}
	fav := favReactions[accountID]
	favMu.Unlock()
	if fav != "" || attempted {
		return
	}
	go func() {
		emoji, err := a.eng.GetDefaultReaction(accountID)
		if err != nil || emoji == "" {
			return
		}
		setFavoriteReaction(accountID, emoji)
		a.invalidate()
	}()
}

func (a *App) applyFavoriteReaction(accountID, emoji string) {
	setFavoriteReaction(accountID, emoji)
	go func() {
		if err := a.eng.SetDefaultReaction(accountID, emoji); err != nil {
			a.setToast("React with: " + err.Error())
			return
		}
	}()
}

func (a *App) msgReactBtn(key string) *widget.Clickable {
	if btn, ok := a.wid.msgReactBtns[key]; ok {
		return btn
	}
	btn := new(widget.Clickable)
	a.wid.msgReactBtns[key] = btn
	return btn
}

func (a *App) layoutCornerReaction(gtx layout.Context, f frame, m *engine.CachedMessage) layout.Dimensions {
	if !cornerReactGate(f.cfg.CornerReaction, f.selOn, *m) {
		return layout.Dimensions{}
	}
	if m.MsgID != hoveredMsgID() {
		return layout.Dimensions{}
	}
	btn := a.msgReactBtn(m.AccountID + "/" + m.ChatID + "/" + m.MsgID)
	fav := favoriteReactionOrDefault(favoriteReactionFor(m.AccountID))
	own := ownHasReaction(m.Reactions, fav)
	favDoc, favCustom := customKeyDocID(fav)
	if btn.Clicked(gtx) {
		emojis := toggleOwnReactionEmojis(m.Reactions, fav)
		acct, chat, msg := m.AccountID, m.ChatID, m.MsgID
		go func() {
			if err := a.eng.ReactToMessageList(acct, chat, msg, emojis); err != nil {
				a.setToast("React failed: " + err.Error())
			}
		}()
		return layout.Dimensions{}
	}
	return layout.UniformInset(unit.Dp(0)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		bl := material.ButtonLayout(a.ui.Theme, btn)
		bl.Background = a.ui.p.SurfaceHi
		bl.CornerRadius = 10
		return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(4)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				if favCustom {
					return a.customReactionGlyph(gtx, m.AccountID, favDoc)
				}
				lbl := a.ui.Label(unit.Sp(14), fav)
				if own {
					lbl.Color = a.ui.p.Accent
				} else {
					lbl.Color = a.ui.p.Text
				}
				return lbl.Layout(gtx)
			})
		})
	})
}

func (a *App) cornerButtonsOverlay(gtx layout.Context, f frame, m *engine.CachedMessage, canReply bool, content func(gtx layout.Context) layout.Dimensions) layout.Dimensions {
	return layout.Stack{Alignment: layout.NE}.Layout(gtx,
		layout.Stacked(func(gtx layout.Context) layout.Dimensions {
			return content(gtx)
		}),
		layout.Stacked(func(gtx layout.Context) layout.Dimensions {
			if !cornerReactGate(f.cfg.CornerReaction, f.selOn, *m) {
				return layout.Dimensions{}
			}
			return layout.Inset{Top: unit.Dp(2), Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.layoutCornerReaction(gtx, f, m)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.layoutCornerReply(gtx, f, m, canReply)
					}),
				)
			})
		}),
	)
}
