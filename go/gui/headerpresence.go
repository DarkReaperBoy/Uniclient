package gui

import (
	"image"
	"image/color"
	"time"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"

	"uniclient/engine"
)

// Peer header status + badges (AyuGram parity slice 28).
//
// The DM chat header shows the peer's presence line ("online" / "last seen
// …") under the title, fed by GetUserProfile on chat open and refreshed
// live by engine.EventUserStatus. Channels/groups keep member counts.
// Next to the title sit the peer badges AyuGram renders: verified ✓,
// premium ⭐, scam/fake ⚠.

// hdrBadge is one title-adjacent badge icon.
type hdrBadge struct {
	icon  *widget.Icon
	col   color.NRGBA
	label string // semantic kind: verified/premium/scam/fake
}

// Badge colors (Telegram-ish): verified blue, premium gold, scam red,
// fake orange.
var (
	badgeVerifiedCol = color.NRGBA{R: 0x4F, G: 0xA8, B: 0xE8, A: 0xFF}
	badgePremiumCol  = color.NRGBA{R: 0xF5, G: 0xA6, B: 0x23, A: 0xFF}
	badgeScamCol     = color.NRGBA{R: 0xE5, G: 0x39, B: 0x35, A: 0xFF}
	badgeFakeCol     = color.NRGBA{R: 0xEF, G: 0x6C, B: 0x00, A: 0xFF}
)

// headerBadges derives the badge row for a chat from its flags.
func headerBadges(c engine.ChatInfo) []hdrBadge {
	var out []hdrBadge
	if c.IsVerified {
		out = append(out, hdrBadge{icon: iconActionCheckCircle, col: badgeVerifiedCol, label: "verified"})
	}
	if c.IsPremium {
		out = append(out, hdrBadge{icon: iconToggleStar, col: badgePremiumCol, label: "premium"})
	}
	if c.IsScam {
		out = append(out, hdrBadge{icon: iconAlertWarning, col: badgeScamCol, label: "scam"})
	} else if c.IsFake {
		out = append(out, hdrBadge{icon: iconAlertWarning, col: badgeFakeCol, label: "fake"})
	}
	return out
}

// layoutHeaderBadges draws the badge icons after the title.
func (a *App) layoutHeaderBadges(gtx layout.Context, badges []hdrBadge) layout.Dimensions {
	if len(badges) == 0 {
		return layout.Dimensions{}
	}
	sz := gtx.Dp(unit.Dp(14))
	children := make([]layout.FlexChild, 0, len(badges))
	for i := range badges {
		i := i
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Left: unit.Dp(5), Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				gtx.Constraints = layout.Constraints{Max: image.Pt(sz, sz), Min: image.Pt(0, 0)}
				if badges[i].icon == nil {
					return layout.Dimensions{Size: image.Pt(sz, sz)}
				}
				d := badges[i].icon.Layout(gtx, badges[i].col)
				return d
			})
		}))
	}
	return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx, children...)
}

// presenceSubtitle derives the DM header line from the peer's presence.
// The bool reports "online" (accent color like AyuGram).
func presenceSubtitle(p *engine.CachedUser) (string, bool) {
	if p == nil {
		return "", false
	}
	if p.IsOnline {
		return "online", true
	}
	if p.IsBot {
		return "bot", false
	}
	return headerLastSeen(p.LastSeenKind, p.LastSeen), false
}

// headerLastSeen renders a last-seen label; "exact" gets a timestamp,
// other kinds reuse the profile panel wording.
func headerLastSeen(kind string, ms int64) string {
	if kind != "exact" {
		return lastSeenLabel(kind)
	}
	t := time.UnixMilli(ms)
	now := time.Now()
	if sameCalendarDay(now, t) {
		return "last seen at " + t.Format("15:04")
	}
	return "last seen on " + t.Format("Jan 2")
}

// sameCalendarDay reports whether two times fall on the same local date.
func sameCalendarDay(a, b time.Time) bool {
	ay, am, ad := a.Date()
	by, bm, bd := b.Date()
	return ay == by && am == bm && ad == bd
}
