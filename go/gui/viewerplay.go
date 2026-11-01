package gui

import (
	"image/color"
	"path/filepath"
	"strings"
	"time"

	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/unit"

	"uniclient/engine"
	"uniclient/h264vid"
)

func inAppVideoExt(path string) bool {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".mp4", ".m4v":
		return true
	}
	return false
}

func viewerCanPlayInApp(it engine.SharedMediaItem) bool {
	return viewerIsVideo(it) && it.LocalPath != "" && inAppVideoExt(it.LocalPath)
}

func videoSeekFrac(elapsed, total time.Duration) float64 {
	if total <= 0 {
		return 0
	}
	f := float64(elapsed) / float64(total)
	if f < 0 {
		return 0
	}
	if f > 1 {
		return 1
	}
	return f
}

func videoTimes(elapsed, total time.Duration) (string, string) {
	return fmtDur(secondsFloor(elapsed)), fmtDur(secondsFloor(total))
}

func secondsFloor(d time.Duration) int {
	if d <= 0 {
		return 0
	}
	return int(d / time.Second)
}

func seekTarget(p *h264Player, frac float64) time.Duration {
	if p == nil || p.video == nil || p.video.Total <= 0 {
		return 0
	}
	if frac < 0 {
		frac = 0
	}
	if frac > 1 {
		frac = 1
	}
	return time.Duration(frac * float64(p.video.Total))
}

func (c *h264PlayerCache) duration(msgID string) time.Duration {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p := c.players[msgID]; p != nil && p.video != nil {
		return p.video.Total
	}
	return 0
}

func (c *h264PlayerCache) seek(msgID string, frac float64) {
	var (
		pl    *h264vid.Player
		start time.Duration
	)
	c.mu.Lock()
	p := c.players[msgID]
	if p == nil {
		c.mu.Unlock()
		return
	}
	start = seekTarget(p, frac)
	pl = p.player
	c.mu.Unlock()

	if pl != nil {
		pl.Seek(start)
	}

	c.mu.Lock()
	if p := c.players[msgID]; p != nil {
		if p.playing {
			p.start = time.Now().Add(-start)
		} else {
			p.paused = start
		}
	}
	c.mu.Unlock()
}

func (a *App) viewerPopOut(gtx layout.Context, it engine.SharedMediaItem) {
	if !viewerVideoActive(it) {
		a.viewerPlayVideo(it)
	}
	vpW, vpH := a.vpW, a.vpH
	if vpW <= 0 || vpH <= 0 {
		vpW, vpH = gtx.Constraints.Max.X, gtx.Constraints.Max.Y
	}
	vidW, vidH := it.Width, it.Height
	if st, has := h264Players.peek(it.MsgID); has && st.video != nil {
		vidW, vidH = st.video.Width, st.video.Height
	}
	a.startPip(it.MsgID, vidW, vidH, vpW, vpH)
	a.closeViewer()
	a.invalidate()
}

func viewerVideoActive(it engine.SharedMediaItem) bool {
	if !viewerIsVideo(it) {
		return false
	}
	st, ok := h264Players.peek(it.MsgID)
	return ok && st.parsed && st.player != nil && st.video != nil
}

func (a *App) viewerPlayVideo(it engine.SharedMediaItem) {
	st, have := h264Players.peek(it.MsgID)
	var snap *h264PlayerState
	if have {
		snap = &st
	}
	switch noteTapAction(snap, viewerCanPlayInApp(it)) {
	case noteActionPlay:
		h264Players.resume(it.MsgID)
		a.viewerVideoAudioPlay(it)
		a.invalidate()
		return
	case noteActionPause:
		h264Players.pause(it.MsgID)
		a.videoAudioPause(it.MsgID)
		a.invalidate()
		return
	case noteActionWait:
		return
	}
	path := it.LocalPath
	loop := it.MediaType == engine.MediaVideoNote
	acct, chat := a.viewerIdent()
	a.ensureH264Player(acct, chat, it.MsgID, path, loop, func() {
		a.setToast("Can't play this video in-app — opening system player")
		a.openMedia(path, true)
	})
}

func (a *App) viewerVideoBar(gtx layout.Context, f frame) layout.Dimensions {
	it, _, ok := a.viewerCurrent(f)
	if !ok {
		return layout.Dimensions{}
	}
	st, have := h264Players.peek(it.MsgID)
	if !have || !st.parsed || st.video == nil || st.player == nil {
		return layout.Dimensions{}
	}

	total := st.video.Total
	elapsed := h264Players.elapsed(it.MsgID)
	frac := videoSeekFrac(elapsed, total)
	elLabel, toLabel := videoTimes(elapsed, total)
	msgID, playing := it.MsgID, st.playing

	dims := layout.Inset{Left: unit.Dp(20), Right: unit.Dp(20), Bottom: unit.Dp(6)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.videoTransportBtn(gtx, it, playing)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Left: unit.Dp(10), Right: unit.Dp(10)}.Layout(gtx,
						func(gtx layout.Context) layout.Dimensions {
							return videoClockLabel(gtx, a, elLabel)
						})
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					return a.seekBarDo(gtx, "viewer|"+msgID, frac, func(fr float64) {
						h264Players.seek(msgID, fr)
						a.videoAudioSeek(msgID, fr)
					})
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Left: unit.Dp(10)}.Layout(gtx,
						func(gtx layout.Context) layout.Dimensions {
							return videoClockLabel(gtx, a, toLabel)
						})
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if !videoAudioAvailable() {
						return layout.Dimensions{}
					}
					return layout.Inset{Left: unit.Dp(10)}.Layout(gtx,
						func(gtx layout.Context) layout.Dimensions {
							vol := a.mediaVolume()
							glyph := iconAVVolumeUp
							if vol <= 0 {
								glyph = iconAVVolumeOff
							}
							icon := layoutIconPx(gtx, glyph, a.ui.p.TextFaint, gtx.Dp(unit.Dp(14)))
							slider := layout.Inset{Left: unit.Dp(6)}.Layout(gtx,
								func(gtx layout.Context) layout.Dimensions {
									gtx.Constraints.Min.X = gtx.Dp(64)
									gtx.Constraints.Max.X = gtx.Dp(64)
									return a.seekBarDo(gtx, "viewer|vol|"+msgID, vol, func(fr float64) {
										a.setMediaVolume(fr)
									})
								})
							return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions { return icon }),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions { return slider }),
							)
						})
				}),
			)
		})

	gtx.Execute(op.InvalidateCmd{At: time.Now().Add(250 * time.Millisecond)})
	return dims
}

func videoClockLabel(gtx layout.Context, a *App, s string) layout.Dimensions {
	lbl := a.ui.Label(unit.Sp(11), s)
	lbl.Color = color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xB0}
	return lbl.Layout(gtx)
}

func (a *App) videoTransportBtn(gtx layout.Context, it engine.SharedMediaItem, playing bool) layout.Dimensions {
	msgID := it.MsgID
	if a.wid.viewerVidPlayBtn.Clicked(gtx) {
		if playing {
			h264Players.pause(msgID)
			a.videoAudioPause(msgID)
		} else {
			h264Players.resume(msgID)
			a.viewerVideoAudioPlay(it)
		}
		a.invalidate()
	}
	bg := a.ui.p.SurfaceHi
	if playing {
		bg = a.ui.p.Accent
	}
	label := "▶"
	if playing {
		label = "⏸"
	}
	return roundedFill(gtx, bg, 15, func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6), Left: unit.Dp(9), Right: unit.Dp(9)}.Layout(gtx,
			func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Label(unit.Sp(12), label)
				lbl.Color = color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF}
				return lbl.Layout(gtx)
			})
	})
}
