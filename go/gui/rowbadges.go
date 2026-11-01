package gui

import (
	"image"
	"image/color"
	"time"

	"gioui.org/font"
	"gioui.org/layout"
	"gioui.org/unit"

	"uniclient/engine"
)

func rowTitleBadges(c engine.ChatInfo) []hdrBadge {
	var out []hdrBadge
	if c.IsVerified {
		out = append(out, hdrBadge{icon: iconActionCheckCircle, col: badgeVerifiedCol, label: "verified"})
	}
	if c.IsPremium {
		out = append(out, hdrBadge{icon: iconToggleStar, col: badgePremiumCol, label: "premium"})
	}
	if c.IsScam {
		out = append(out, hdrBadge{col: badgeScamCol, label: "scam"})
	} else if c.IsFake {
		out = append(out, hdrBadge{col: badgeFakeCol, label: "fake"})
	}
	return out
}

const (
	rowBadgeMention   = "mention"
	rowBadgeReactions = "reactions"
	rowBadgeMuteTime  = "muteTime"
)

func trailingRowBadges(c engine.ChatInfo) []string {
	var out []string
	if c.IsMuted && c.MuteUntil > 0 {
		out = append(out, rowBadgeMuteTime)
	}
	if c.UnreadMentionCount > 0 {
		out = append(out, rowBadgeMention)
	}
	if c.UnreadReactionCount > 0 {
		out = append(out, rowBadgeReactions)
	}
	switch rowBadgeKindFor(c) {
	case rowBadgeCount:
		out = append(out, rowBadgeCount)
	case rowBadgeMark:
		out = append(out, rowBadgeMark)
	}
	return out
}

func (a *App) layoutRowTitleBadges(gtx layout.Context, badges []hdrBadge) layout.Dimensions {
	if len(badges) == 0 {
		return layout.Dimensions{}
	}
	children := make([]layout.FlexChild, 0, len(badges))
	for i := range badges {
		i := i
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Left: unit.Dp(4), Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				b := badges[i]
				if b.icon == nil {
					return tagPill(gtx, a.ui, b.label, b.col)
				}
				sz := gtx.Dp(unit.Dp(12))
				gtx.Constraints = layout.Constraints{Max: image.Pt(sz, sz), Min: image.Pt(0, 0)}
				return b.icon.Layout(gtx, b.col)
			})
		}))
	}
	return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx, children...)
}

func tagPill(gtx layout.Context, u *UI, label string, col color.NRGBA) layout.Dimensions {
	return roundedFill(gtx, col, 4, func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(1), Bottom: unit.Dp(1), Left: unit.Dp(5), Right: unit.Dp(5)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := u.Label(unit.Sp(9), upperASCII(label))
			lbl.Color = colorWhiteText
			return lbl.Layout(gtx)
		})
	})
}

var colorWhiteText = color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF}

func upperASCII(s string) string {
	out := []byte(s)
	for i, c := range out {
		if c >= 'a' && c <= 'z' {
			out[i] = c - 'a' + 'A'
		}
	}
	return string(out)
}

func muteTimeBadge(gtx layout.Context, u *UI, muteUntil int64) layout.Dimensions {
	remain := time.Until(time.Unix(muteUntil, 0))
	return roundedFill(gtx, u.p.SurfaceHi, 8, func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(1), Bottom: unit.Dp(1), Left: unit.Dp(6), Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := u.Label(unit.Sp(10), muteRemainingLabel(remain))
			lbl.Color = u.p.TextDim
			lbl.Font.Weight = font.Medium
			return lbl.Layout(gtx)
		})
	})
}

func mentionBadge(gtx layout.Context, u *UI) layout.Dimensions {
	return roundedFill(gtx, u.p.Accent, 9, func(gtx layout.Context) layout.Dimensions {
		w := gtx.Dp(unit.Dp(18))
		gtx.Constraints.Min.X = w
		gtx.Constraints.Max.X = w
		return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := u.Label(unit.Sp(11), "@")
			lbl.Color = colorWhiteText
			return lbl.Layout(gtx)
		})
	})
}

func reactionsBadge(gtx layout.Context, u *UI, n int, muted bool) layout.Dimensions {
	bg := u.p.TextFaint
	txt := colorWhiteText
	if muted {
		bg = u.p.SurfaceHi
		txt = u.p.TextDim
	}
	return roundedFill(gtx, bg, 9, func(gtx layout.Context) layout.Dimensions {
		w := gtx.Dp(unit.Dp(18))
		if n > 9 {
			w = gtx.Dp(unit.Dp(24))
		}
		gtx.Constraints.Min.X = w
		gtx.Constraints.Max.X = w
		return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := u.Label(unit.Sp(11), itoa(n))
			lbl.Color = txt
			return lbl.Layout(gtx)
		})
	})
}

func muteRemainingLabel(remain time.Duration) string {
	if remain < time.Minute {
		return "1m"
	}
	if remain < time.Hour {
		return itoa(int(remain.Minutes())) + "m"
	}
	if remain < 24*time.Hour {
		return itoa(int(remain.Hours())) + "h"
	}
	return itoa(int(remain.Hours()/24)) + "d"
}

func formatMutedUntil(muteUntil, nowUnix int64) string {
	until := time.Unix(muteUntil, 0)
	now := time.Unix(nowUnix, 0)
	if until.YearDay() == now.YearDay() && until.Year() == now.Year() {
		return until.Format("15:04")
	}
	if until.Year() == now.Year() {
		return until.Format("Jan 2, 15:04")
	}
	return until.Format("Jan 2, 2006")
}

func mutedRowHasTimedMute(chats []engine.ChatInfo) bool {
	for i := range chats {
		if chats[i].IsMuted && chats[i].MuteUntil > 0 {
			return true
		}
	}
	return false
}

func (a *App) layoutTrailingRowBadges(gtx layout.Context, c engine.ChatInfo) layout.Dimensions {
	kinds := trailingRowBadges(c)
	if len(kinds) == 0 {
		return layout.Dimensions{}
	}
	children := make([]layout.FlexChild, 0, len(kinds))
	for _, k := range kinds {
		k := k
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Left: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				switch k {
				case rowBadgeMention:
					return mentionBadge(gtx, a.ui)
				case rowBadgeReactions:
					return reactionsBadge(gtx, a.ui, c.UnreadReactionCount, c.IsMuted)
				case rowBadgeMuteTime:
					return muteTimeBadge(gtx, a.ui, c.MuteUntil)
				case rowBadgeCount:
					return unreadBadge(gtx, a.ui, c.UnreadCount, c.IsMuted)
				default:
					return unreadMarkDot(gtx, a.ui, c.IsMuted)
				}
			})
		}))
	}
	return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx, children...)
}
