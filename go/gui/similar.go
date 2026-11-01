package gui

import (
	"log"
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

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

func similarExpandedDefault(collapseCfg bool) bool {
	return !collapseCfg
}

func similarEffectiveExpanded(expanded map[string]bool, key string, def bool) bool {
	if v, ok := expanded[key]; ok {
		return v
	}
	return def
}

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

func (a *App) similarAvatar(gtx layout.Context, c *engine.SimilarChannelInfo) layout.Dimensions {
	if c.AvatarB64 != "" {
		key := "thumb:" + c.AvatarB64
		if img := mediaImgs.get(key); img != nil {
			return avatarFromImage(gtx, a, img, unit.Dp(34), dotNone, a.ui.avatarRadiusPx(gtx.Dp(unit.Dp(34))))
		}
		a.decodeThumbAsync(key, c.AvatarB64)
	}
	return a.ui.Avatar(gtx, c.Title, unit.Dp(34), dotNone)
}
