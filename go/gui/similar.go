package gui

// Similar channels (slice 167): the channel-recommendations block under
// the last post of broadcast channels (tdesktop
// channels.getChannelRecommendations surface — the engine/core already
// fetch them; this renders it). Horizontal card row: avatar, title,
// member count; tap opens the channel (access hashes are cached by the
// core, so the ID resolves even without a prior dialog).
//
// Slice 169 — AyuGram settings (primary source: ayu_settings.h):
// hideSimilarChannels never renders the block; collapseSimilarChannels
// (default ON) starts it collapsed into a compact bar with an expander
// (tdesktop ChannelDataFlag::SimilarExpanded parity: per-chat runtime
// state, not persisted).

import (
	"log"
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// similarBlockMode is the pure render decision for the block: "off"
// (hidden), "collapsed" (compact bar) or "expanded" (card row). Hide
// wins over collapse.
func similarBlockMode(hide, collapsed bool) string {
	switch {
	case hide:
		return "off"
	case collapsed:
		return "collapsed"
	default:
		return "expanded"
	}
}

// similarExpandedDefault derives a channel's initial expanded state from
// the collapse config: collapse ON → channels start collapsed.
func similarExpandedDefault(collapseCfg bool) bool {
	return !collapseCfg
}

// similarEffectiveExpanded resolves the per-chat expanded state: an
// explicit toggle beats the config default; absent falls back to it.
// Pure (the map is read-only here).
func similarEffectiveExpanded(expanded map[string]bool, key string, def bool) bool {
	if v, ok := expanded[key]; ok {
		return v
	}
	return def
}

// loadSimilar fetches the recommendations for the open channel chat.
func (a *App) loadSimilar(k chatKey) {
	go func() {
		var chat *engine.ChatInfo
		a.mu.Lock()
		for i := range a.chats {
			if a.chats[i].AccountID == k.AccountID && a.chats[i].ChatID == k.ChatID {
				c := a.chats[i]
				chat = &c
				break
			}
		}
		a.mu.Unlock()
		if chat == nil || chat.Type != engine.ChatTypeChanVal {
			return
		}
		items, err := a.eng.GetSimilarChannels(k.AccountID, k.ChatID)
		if err != nil {
			if !strings.Contains(err.Error(), "does not support") {
				log.Printf("gui: similar channels: %v", err)
			}
			items = nil
		}
		a.mu.Lock()
		if cur := a.selected; cur != nil && *cur == k {
			a.similar = items
			a.similarFor = k.AccountID + "|" + k.ChatID
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// layoutSimilarBlock renders the block: caption + the horizontal card
// row. Shown for broadcast channels (not in topic views) with
// recommendations.
func (a *App) layoutSimilarBlock(gtx layout.Context, f frame) layout.Dimensions {
	if len(f.similar) == 0 || f.selected == nil {
		return layout.Dimensions{}
	}
	if a.wid.similarCollapseBtn.Clicked(gtx) {
		a.setSimilarExpanded(false)
		a.invalidate()
	}
	growClickables(&a.wid.similarCardBtns, len(f.similar))
	for i := range f.similar {
		if a.wid.similarCardBtns[i].Clicked(gtx) {
			c := f.similar[i]
			a.mu.Lock()
			k := chatKey{AccountID: f.selected.AccountID, ChatID: c.ChatID}
			a.pendingOpen = &k
			a.pendingTitle = c.Title
			a.mu.Unlock()
			a.invalidate()
			break
		}
	}
	return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(12), "Similar channels")
						lbl.Color = a.ui.p.TextFaint
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.TextButton(&a.wid.similarCollapseBtn, "Hide")
						btn.TextSize = unit.Sp(12)
						btn.Inset.Top, btn.Inset.Bottom = unit.Dp(2), unit.Dp(2)
						return btn.Layout(gtx)
					}),
				)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					var children []layout.FlexChild
					for i := range f.similar {
						i := i
						children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return a.similarCard(gtx, &f.similar[i], &a.wid.similarCardBtns[i])
							})
						}))
					}
					return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, children...)
				})
			}),
		)
	})
}

// layoutSimilarCollapsed renders the compact bar (slice 169): caption +
// recommendation count + the expander. Tapping it expands the block for
// this chat (runtime per-chat state, tdesktop SimilarExpanded parity).
func (a *App) layoutSimilarCollapsed(gtx layout.Context, f frame) layout.Dimensions {
	if len(f.similar) == 0 || f.selected == nil {
		return layout.Dimensions{}
	}
	if a.wid.similarExpandBtn.Clicked(gtx) {
		a.setSimilarExpanded(true)
		a.invalidate()
	}
	return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(12), "Similar channels")
				lbl.Color = a.ui.p.TextFaint
				return lbl.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(12), "· "+commonMemberLabel(len(f.similar)))
					lbl.Color = a.ui.p.TextFaint
					return lbl.Layout(gtx)
				})
			}),
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				return layout.Dimensions{Size: gtx.Constraints.Min}
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.TextButton(&a.wid.similarExpandBtn, "Show")
				btn.TextSize = unit.Sp(12)
				btn.Inset.Top, btn.Inset.Bottom = unit.Dp(2), unit.Dp(2)
				return btn.Layout(gtx)
			}),
		)
	})
}

// setSimilarExpanded records this App's expanded preference for the open
// chat (keyed like similarFor). Runs on the GUI loop.
func (a *App) setSimilarExpanded(v bool) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.similarExpanded == nil {
		a.similarExpanded = map[string]bool{}
	}
	if a.selected == nil {
		return
	}
	a.similarExpanded[a.selected.AccountID+"|"+a.selected.ChatID] = v
}

// similarCard: one recommendation — avatar, title, member count.
func (a *App) similarCard(gtx layout.Context, c *engine.SimilarChannelInfo, btn *widget.Clickable) layout.Dimensions {
	bl := material.ButtonLayout(a.ui.Theme, btn)
	bl.Background = a.ui.p.Surface
	bl.CornerRadius = 12
	return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(200))
		return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return a.similarAvatar(gtx, c)
					})
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(13), c.Title)
							lbl.MaxLines = 1
							return lbl.Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							if c.MemberCount <= 0 {
								return layout.Dimensions{}
							}
							return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), commonMemberLabel(c.MemberCount))
								lbl.Color = a.ui.p.TextDim
								return lbl.Layout(gtx)
							})
						}),
					)
				}),
			)
		})
	})
}

// similarAvatar: the recommendation's stripped thumb or a letter bubble.
func (a *App) similarAvatar(gtx layout.Context, c *engine.SimilarChannelInfo) layout.Dimensions {
	if c.AvatarB64 != "" {
		key := "thumb:" + c.AvatarB64
		if img := mediaImgs.get(key); img != nil {
			return avatarFromImage(gtx, a, img, unit.Dp(34), dotNone)
		}
		a.decodeThumbAsync(key, c.AvatarB64)
	}
	return a.ui.Avatar(gtx, c.Title, unit.Dp(34), dotNone)
}
