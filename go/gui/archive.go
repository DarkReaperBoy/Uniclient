package gui

import (
	"image"

	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Archived chats (AyuGram parity slice 67): archived chats collapse behind
// one row at the top of the chat list — box avatar, "Archived Chats" title,
// aggregate unread badge (unmuted chats only, like Telegram). Tapping it
// swaps the list to the archived chats; the folder tabs are replaced by a
// back row. The context menu's Archive/Unarchive actions (slice 27) toggle
// chats in and out of this view; search still sees archived chats.

// splitArchived partitions a chat list into main and archived rows.
func splitArchived(chats []engine.ChatInfo) (main, archived []engine.ChatInfo) {
	for _, c := range chats {
		if c.IsArchived {
			archived = append(archived, c)
		} else {
			main = append(main, c)
		}
	}
	return main, archived
}

// archiveAggregateUnread sums the unread counts of unmuted archived chats.
func archiveAggregateUnread(archived []engine.ChatInfo) int {
	n := 0
	for _, c := range archived {
		if !c.IsMuted {
			n += c.UnreadCount
		}
	}
	return n
}

// archivedChatsFor collects the archived chats a frame can show (honoring
// the account filter) — feeds the collapsed row's badge and the archive view.
func archivedChatsFor(f frame) []engine.ChatInfo {
	var out []engine.ChatInfo
	for _, c := range f.chats {
		if !c.IsArchived {
			continue
		}
		if f.acctFilter != "" && c.AccountID != f.acctFilter {
			continue
		}
		out = append(out, c)
	}
	return out
}

var archiveRowBtn widget.Clickable
var archiveBackBtn widget.Clickable

// archiveBoxAvatar draws the boxed-archive glyph Telegram uses for the
// archived row: a rounded box with a downward "into the box" arrow.
func archiveBoxAvatar(gtx layout.Context, u *UI, size unit.Dp, unread int) layout.Dimensions {
	sz := gtx.Dp(size)
	col := u.p.TextDim
	if unread > 0 {
		col = u.p.Accent
	}
	// Box.
	r := gtx.Dp(unit.Dp(10))
	paint.FillShape(gtx.Ops, col, clip.UniformRRect(image.Rect(0, 0, sz, sz), r).Op(gtx.Ops))
	// Arrow cut: a background-colored chevron pointing down into the box.
	bg := u.p.Background
	ax := sz * 3 / 10
	ay := sz * 3 / 10
	aw := sz * 4 / 10
	ah := sz * 4 / 10
	paint.FillShape(gtx.Ops, bg, clip.UniformRRect(image.Rect(ax, ay, ax+aw, ay+ah/2), gtx.Dp(unit.Dp(2))).Op(gtx.Ops))
	paint.FillShape(gtx.Ops, bg, clip.UniformRRect(image.Rect(ax+aw/4, ay+ah/2, ax+3*aw/4, ay+ah), gtx.Dp(unit.Dp(2))).Op(gtx.Ops))
	return layout.Dimensions{Size: image.Pt(sz, sz)}
}

// archiveRow: the collapsed row at the top of the chat list. Sits above
// every chat row (Telegram: always first, above pinned chats).
func (a *App) archiveRow(gtx layout.Context, f frame, archived []engine.ChatInfo) layout.Dimensions {
	if archiveRowBtn.Clicked(gtx) {
		a.mu.Lock()
		a.archiveView = true
		a.mu.Unlock()
		a.invalidate()
	}
	unread := archiveAggregateUnread(archived)
	bg := color00
	if archiveRowBtn.Hovered() {
		bg = a.ui.p.SurfaceHi
	}
	return roundedFill(gtx, bg, 0, func(gtx layout.Context) layout.Dimensions {
		return material.ButtonLayout(a.ui.Theme, &archiveRowBtn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return archiveBoxAvatar(gtx, a.ui, unit.Dp(46), unread)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(15), "Archived Chats")
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								if unread <= 0 {
									return layout.Dimensions{}
								}
								return unreadBadge(gtx, a.ui, unread, false)
							}),
						)
					}),
				)
			})
		})
	})
}

// archiveHeader: the back row that replaces the folder tabs while the
// archived list is open. Back arrow + title; folder tabs return on exit.
func (a *App) archiveHeader(gtx layout.Context, f frame) layout.Dimensions {
	if archiveBackBtn.Clicked(gtx) {
		a.exitArchive()
	}
	return layout.Inset{Left: unit.Dp(6), Right: unit.Dp(12), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.IconButton(&archiveBackBtn, iconNavigationBack, "Back to chats")
				btn.Color = a.ui.p.TextDim
				return btn.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.H3("Archived Chats")
				return lbl.Layout(gtx)
			}),
		)
	})
}

// exitArchive leaves the archived-chats view.
func (a *App) exitArchive() {
	a.mu.Lock()
	a.archiveView = false
	a.mu.Unlock()
	a.invalidate()
}
