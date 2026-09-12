package gui

import (
	"time"

	"gioui.org/layout"
	"gioui.org/unit"

	"uniclient/engine"
)

// Composer gating (AyuGram parity slice 69): chats that the engine reports
// as write-restricted swap the a.wid.composer for an honest notice bar, and
// slow-mode chats show a live countdown that blocks sending until the wait
// expires. Both states come straight from ChatInfo — the engine keeps them
// in sync from the server.

const composerRestrictedDefault = "You can't send messages in this chat"

// composerRestricted reports whether the a.wid.composer must be replaced by a
// notice bar, and which label to show. Not-joined channel previews keep the
// JOIN bar (slice 19) — the two gates never overlap.
func composerRestricted(c engine.ChatInfo) (bool, string) {
	if c.NotJoined {
		return false, ""
	}
	if c.WriteRestrictionText != "" {
		return true, c.WriteRestrictionText
	}
	if c.WriteRestrictionType != 0 {
		return true, composerRestrictedDefault
	}
	return false, ""
}

// slowmodeRemain returns how long sending must wait. SlowmodeNextSendDate
// is the server's unix-seconds timestamp of the next allowed send.
func slowmodeRemain(c engine.ChatInfo, now time.Time) time.Duration {
	if c.SlowmodeSeconds <= 0 || c.SlowmodeNextSendDate <= 0 {
		return 0
	}
	next := time.Unix(c.SlowmodeNextSendDate, 0)
	d := next.Sub(now)
	if d <= 0 {
		return 0
	}
	return d
}

// slowmodeLabel renders the countdown chip text ("Slow mode: 12s").
func slowmodeLabel(d time.Duration) string {
	if d <= 0 {
		return ""
	}
	secs := int(d.Round(time.Second).Seconds())
	switch {
	case secs < 60:
		return "Slow mode: " + itoa(secs) + "s"
	case secs < 3600:
		return "Slow mode: " + itoa(secs/60) + "m " + itoa(secs%60) + "s"
	default:
		return "Slow mode: " + itoa(secs/3600) + "h " + itoa((secs%3600)/60) + "m"
	}
}

// restrictedBar replaces the a.wid.composer when writing is disallowed.
func (a *App) restrictedBar(gtx layout.Context, label string) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(10), Bottom: unit.Dp(10), Left: unit.Dp(16), Right: unit.Dp(16)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return iconActionLock.Layout(gtx, a.ui.p.TextFaint)
					})
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(13), label)
					lbl.MaxLines = 2
					return lbl.Layout(gtx)
				}),
			)
		})
}

var slowmodeSendBlocked bool // guards Enter-submission while waiting

// slowmodeChip renders the countdown pill shown inside the a.wid.composer while
// a slow-mode wait is active; it also requests the next-second redraw.
func (a *App) slowmodeChip(gtx layout.Context, f frame, chat *engine.ChatInfo) layout.Dimensions {
	remain := slowmodeRemain(*chat, f.now)
	if remain <= 0 {
		slowmodeSendBlocked = false
		return layout.Dimensions{}
	}
	slowmodeSendBlocked = true
	a.scheduleSlowTick(remain)
	return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.SurfaceHi, 9, func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3), Left: unit.Dp(8), Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Label(unit.Sp(11), slowmodeLabel(remain))
				lbl.Color = a.ui.p.Accent
				return lbl.Layout(gtx)
			})
		})
	})
}

// scheduleSlowTick asks for a redraw when the countdown's next second flips.
// One pending timer at a time; the frame guard keeps redraws cheap.
func (a *App) scheduleSlowTick(remain time.Duration) {
	a.mu.Lock()
	pending := a.slowTickPending
	a.mu.Unlock()
	if pending {
		return
	}
	a.mu.Lock()
	a.slowTickPending = true
	a.mu.Unlock()
	d := remain - time.Second
	if d < 200*time.Millisecond {
		d = 200 * time.Millisecond
	}
	time.AfterFunc(d, func() {
		a.mu.Lock()
		a.slowTickPending = false
		a.mu.Unlock()
		a.invalidate()
	})
}

// sendBlockedBySlowmode is consulted by the a.wid.composer's submit path.
func sendBlockedBySlowmode() bool { return slowmodeSendBlocked }

// slowmodeToast explains a blocked send attempt.
func (a *App) slowmodeToast(chat *engine.ChatInfo) {
	if chat == nil {
		return
	}
	remain := slowmodeRemain(*chat, time.Now())
	if label := slowmodeLabel(remain); label != "" {
		a.setToast(label + " — please wait")
	}
}
