package gui

import (
	"image"
	"strconv"

	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/cores"
	"uniclient/engine"
)

type topicTab struct {
	topicID string
	title   string
	colorID int
	unread  int
	closed  bool
	active  bool
}

func topicTabsFor(topics []cores.ForumTopic, active string) []topicTab {
	tabs := []topicTab{{topicID: "", title: "All topics", active: active == ""}}
	for _, t := range topics {
		if t.IsHidden {
			continue
		}
		tabs = append(tabs, topicTab{
			topicID: t.ID,
			title:   t.Title,
			colorID: t.ColorID,
			unread:  t.UnreadCount,
			closed:  t.IsClosed,
			active:  active != "" && active == t.ID,
		})
	}
	return tabs
}

func topicTabBadgeText(n int) string {
	if n <= 0 {
		return ""
	}
	if n > 99 {
		return "99+"
	}
	return strconv.Itoa(n)
}

func (a *App) layoutTopicTabs(gtx layout.Context, f frame, chat *engine.ChatInfo) layout.Dimensions {
	if chat == nil || !chat.IsForum {
		return layout.Dimensions{}
	}
	tabs := topicTabsFor(f.forumTopics, f.forumTopic)
	growClickables(&a.wid.topicTabBtns, len(tabs))
	for i, tab := range tabs {
		i, tab := i, tab
		if a.wid.topicTabBtns[i].Clicked(gtx) {
			if tab.topicID == "" {
				a.backToForumTopics()
			} else if tab.topicID != f.forumTopic {
				a.openForumTopic(tab.topicID)
			}
		}
	}
	return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4), Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return material.List(a.ui.Theme, &a.wid.topicTabList).Layout(gtx, len(tabs), func(gtx layout.Context, idx int) layout.Dimensions {
			return a.topicTabChip(gtx, &a.wid.topicTabBtns[idx], tabs[idx])
		})
	})
}

func (a *App) topicTabChip(gtx layout.Context, btn *widget.Clickable, tab topicTab) layout.Dimensions {
	bg := a.ui.p.Surface
	if tab.active {
		bg = a.ui.p.SurfaceHi
	}
	bl := material.ButtonLayout(a.ui.Theme, btn)
	bl.Background = bg
	bl.CornerRadius = 14
	return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.topicTabIcon(gtx, tab)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						children := make([]layout.FlexChild, 0, 2)
						children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(13), tab.title)
							if tab.active {
								lbl.Color = a.ui.p.Text
							} else {
								lbl.Color = a.ui.p.TextDim
							}
							return lbl.Layout(gtx)
						}))
						if tab.closed {
							children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Left: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									gtx.Constraints.Max.X = gtx.Dp(unit.Dp(13))
									gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(13))
									return iconActionLock.Layout(gtx, a.ui.p.TextFaint)
								})
							}))
						}
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx, children...)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						badge := topicTabBadgeText(tab.unread)
						if badge == "" {
							return layout.Dimensions{}
						}
						return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.topicTabBadge(gtx, badge)
						})
					}),
				)
			})
		})
	})
}

func (a *App) topicTabIcon(gtx layout.Context, tab topicTab) layout.Dimensions {
	if tab.topicID == "" {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(18))
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(18))
		return iconCommunicationForum.Layout(gtx, a.ui.p.TextDim)
	}
	size := gtx.Dp(unit.Dp(18))
	c := topicColor(tab.colorID, a.ui.p.Accent)
	defer clip.Ellipse{Min: image.Pt(0, 0), Max: image.Pt(size, size)}.Push(gtx.Ops).Pop()
	paint.FillShape(gtx.Ops, c, clip.Ellipse{Min: image.Pt(0, 0), Max: image.Pt(size, size)}.Op(gtx.Ops))
	return layout.Dimensions{Size: image.Pt(size, size)}
}

func (a *App) topicTabBadge(gtx layout.Context, text string) layout.Dimensions {
	return roundedFill(gtx, a.ui.p.Accent, 10, func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(1), Bottom: unit.Dp(1), Left: unit.Dp(6), Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := material.Label(a.ui.Theme, unit.Sp(11), text)
			lbl.Color = rgb(0xFFFFFF)
			return lbl.Layout(gtx)
		})
	})
}
