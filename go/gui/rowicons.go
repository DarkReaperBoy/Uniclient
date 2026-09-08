package gui

import (
	"image"
	"image/color"

	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"

	"uniclient/engine"
)

// Sidebar row meta icons + unread-mark dot + service-message pill
// (AyuGram parity slice 29).

// rowMetaIcons draws the pin and mute markers right of the chat title,
// before the timestamp — Telegram shows a small pin for pinned rows and a
// muted icon for muted ones.
func (a *App) rowMetaIcons(gtx layout.Context, f frame, c engine.ChatInfo) layout.Dimensions {
	return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if !c.IsPinned {
				return layout.Dimensions{}
			}
			return layout.Inset{Right: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layoutIconPx(gtx, iconCustomPin, a.ui.p.TextFaint, gtx.Dp(unit.Dp(12)))
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if !c.IsMuted {
				return layout.Dimensions{}
			}
			return layout.Inset{Right: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layoutIconPx(gtx, iconAVVolumeOff, a.ui.p.TextFaint, gtx.Dp(unit.Dp(13)))
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			t := a.ui.Dim(unit.Sp(11), fmtTime(c.LastMsgTime))
			t.Color = a.ui.p.TextFaint
			return t.Layout(gtx)
		}),
	)
}

// layoutIconPx draws an icon scaled to a pixel size with a small margin.
func layoutIconPx(gtx layout.Context, icon iconDrawer, col color.NRGBA, sz int) layout.Dimensions {
	if icon == nil {
		return layout.Dimensions{}
	}
	gtx.Constraints = layout.Constraints{Max: image.Pt(sz, sz), Min: image.Pt(0, 0)}
	return icon.Layout(gtx, col)
}

// unreadMarkDot renders the small "marked unread" dot Telegram shows for
// rows explicitly flagged unread without a count.
func unreadMarkDot(gtx layout.Context, u *UI, muted bool) layout.Dimensions {
	col := u.p.Accent
	if muted {
		col = u.p.TextFaint
	}
	sz := gtx.Dp(unit.Dp(8))
	// Center the dot in the badge-sized cell so rows don't shift.
	cell := gtx.Dp(unit.Dp(18))
	off := (cell - sz) / 2
	if off < 0 {
		off = 0
	}
	defer op.Offset(image.Pt(off, off)).Push(gtx.Ops).Pop()
	paint.FillShape(gtx.Ops, col, clip.Ellipse{Min: image.Pt(0, 0), Max: image.Pt(sz, sz)}.Op(gtx.Ops))
	return layout.Dimensions{Size: image.Pt(cell, cell)}
}

// iconDrawer is the widget.Icon layout surface (keeps tests free of gio).
type iconDrawer interface {
	Layout(gtx layout.Context, col color.NRGBA) layout.Dimensions
}

// serviceRow renders a service message as a centered dim pill —
// Telegram/AyuGram style ("Alice joined the group", "photo changed").
func (a *App) serviceRow(gtx layout.Context, m *engine.CachedMessage) layout.Dimensions {
	text := m.ContentText
	if text == "" {
		text = "(service message)"
	}
	pill := func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.SurfaceHi, 9, func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3), Left: unit.Dp(10), Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Label(unit.Sp(12), text)
				lbl.Color = a.ui.p.TextDim
				lbl.MaxLines = 2
				return lbl.Layout(gtx)
			})
		})
	}
	return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Center.Layout(gtx, pill)
	})
}

// rowBadgeKind picks which trailing badge a row shows.
const (
	rowBadgeNone  = "none"
	rowBadgeCount = "count"
	rowBadgeMark  = "mark"
)

// rowBadgeKindFor: unread count wins, then the explicit unread mark.
func rowBadgeKindFor(c engine.ChatInfo) string {
	switch {
	case c.UnreadCount > 0:
		return rowBadgeCount
	case c.UnreadMark:
		return rowBadgeMark
	default:
		return rowBadgeNone
	}
}

// servicePillText derives the centered pill text for a service message.
func servicePillText(m engine.CachedMessage) string {
	if m.ContentText != "" {
		return m.ContentText
	}
	return "(service message)"
}

// accountUnread sums unread counts for one account's chats.
func accountUnread(chats []engine.ChatInfo, accountID string) int {
	n := 0
	for _, c := range chats {
		if c.AccountID == accountID {
			n += c.UnreadCount
		}
	}
	return n
}
