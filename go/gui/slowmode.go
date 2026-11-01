package gui

import (
	"time"

	"gioui.org/layout"
	"gioui.org/unit"

	"uniclient/engine"
)

const composerRestrictedDefault = "You can't send messages in this chat"

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

func (a *App) slowmodeChip(gtx layout.Context, f frame, chat *engine.ChatInfo) layout.Dimensions {
	remain := slowmodeRemain(*chat, f.now)
	if remain <= 0 {
		return layout.Dimensions{}
	}
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

func (a *App) slowmodeToast(chat *engine.ChatInfo) {
	if chat == nil {
		return
	}
	remain := slowmodeRemain(*chat, time.Now())
	if label := slowmodeLabel(remain); label != "" {
		a.setToast(label + " — please wait")
	}
}
