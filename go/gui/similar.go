package gui

// Similar channels (slice 167): the channel-recommendations block under
// the last post of broadcast channels (tdesktop
// channels.getChannelRecommendations surface — the engine/core already
// fetch it; this renders it). Horizontal card row: avatar, title,
// member count; tap opens the channel (access hashes are cached by the
// core, so the ID resolves even without a prior dialog).

import (
	"log"
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

var similarCardBtns []widget.Clickable

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
	growClickables(&similarCardBtns, len(f.similar))
	for i := range f.similar {
		if similarCardBtns[i].Clicked(gtx) {
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
				lbl := a.ui.Dim(unit.Sp(12), "Similar channels")
				lbl.Color = a.ui.p.TextFaint
				return lbl.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					var children []layout.FlexChild
					for i := range f.similar {
						i := i
						children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return a.similarCard(gtx, &f.similar[i], &similarCardBtns[i])
							})
						}))
					}
					return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, children...)
				})
			}),
		)
	})
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
