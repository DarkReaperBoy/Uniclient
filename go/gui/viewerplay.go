package gui

// viewerplay.go — slice 221: in-app video playback in the media viewer,
// parity row 276 "Playback controls (video): play/pause/seek/volume/
// fullscreen".
//
// What is implemented: play, pause, scrub-to-seek, and the elapsed/total
// clocks, all against the pure-Go h264vid clip (GOP-aligned seek comes
// free from slice 219). The viewer itself is already the fullscreen
// surface.
//
// What is deliberately ABSENT: volume. Telegram ships H.264+AAC in MP4
// and there is still no AAC decoder, so a volume slider would control
// nothing at all — §1.10 forbids UI that fakes a capability, so the
// control simply is not drawn. The system-player handoff stays one tap
// away and carries the audio until AAC lands.

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

// ── pure helpers (unit-tested in viewerplay_test.go) ───────────────────

// inAppVideoExt reports whether a path is a container the H.264 pipeline
// might play. It is only a cheap pre-filter — h264vid.Parse decides for
// real, and its failure falls back to the system player, so an HEVC file
// inside an .mp4 never becomes a dead play button.
func inAppVideoExt(path string) bool {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".mp4", ".m4v":
		return true
	}
	return false
}

// viewerCanPlayInApp is the in-app-vs-system decision: a downloaded
// video (or round note) in a container we can attempt. Pure — unit-tested.
func viewerCanPlayInApp(it engine.SharedMediaItem) bool {
	return viewerIsVideo(it) && it.LocalPath != "" && inAppVideoExt(it.LocalPath)
}

// videoSeekFrac maps a playhead onto a 0..1 scrubber fraction, clamped at
// both ends and safe with missing metadata (no divide-by-zero).
// Pure — unit-tested.
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

// videoTimes returns the elapsed and total labels for the control bar,
// through fmtDur so an hour-long file reads 1:01:01 / 2:02:05 and a
// missing or negative clock degrades to "0:00". Pure — unit-tested.
func videoTimes(elapsed, total time.Duration) (string, string) {
	return fmtDur(secondsFloor(elapsed)), fmtDur(secondsFloor(total))
}

// secondsFloor converts a clock to whole seconds, never negative
// (fmtDur clamps too; flooring here keeps the intent explicit).
func secondsFloor(d time.Duration) int {
	if d <= 0 {
		return 0
	}
	return int(d / time.Second)
}

// seekTarget maps a 0..1 fraction onto a clip time, clamping to bounds.
// A clip without usable metadata yields 0 rather than a garbage position.
// Caller must hold the cache mutex (it dereferences p.video).
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

// ── cache additions (seeking) ──────────────────────────────────────────

// duration reports the clip length for the control bar's total label.
func (c *h264PlayerCache) duration(msgID string) time.Duration {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p := c.players[msgID]; p != nil && p.video != nil {
		return p.video.Total
	}
	return 0
}

// seek jumps the playhead to a fraction of the clip.
//
// Two phases on purpose: the decode restart (h264vid.Player.Seek, which
// rebuilds the decoder at a keyframe and can block) runs OFF the cache
// lock, then the GUI clock is rebased onto the same target. Rebasing is
// what makes scrubbing actually stick — without it FrameAt keeps painting
// from the old playhead and the picture snaps back on the next frame.
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

// ── viewer wiring ──────────────────────────────────────────────────────

// viewerVideoActive reports whether the current item has a live in-app
// player (playing OR paused) — used to hide the poster's big play badge,
// because the transport bar now owns start/stop.
func viewerVideoActive(it engine.SharedMediaItem) bool {
	if !viewerIsVideo(it) {
		return false
	}
	st, ok := h264Players.peek(it.MsgID)
	return ok && st.parsed && st.player != nil && st.video != nil
}

// viewerPlayVideo starts or toggles in-app playback for a viewer item.
// Either way the click does something real: an already-parsed clip
// toggles, a parse in flight is left alone (it repaints on publish), and
// a missing parse is kicked off with an honest fallback if it fails.
func (a *App) viewerPlayVideo(it engine.SharedMediaItem) {
	st, have := h264Players.peek(it.MsgID)
	var snap *h264PlayerState
	if have {
		snap = &st
	}
	switch noteTapAction(snap, viewerCanPlayInApp(it)) {
	case noteActionPlay:
		h264Players.resume(it.MsgID)
		a.invalidate()
		return
	case noteActionPause:
		h264Players.pause(it.MsgID)
		a.invalidate()
		return
	case noteActionWait:
		return // parse already in flight; the publish path repaints
	}
	// Nothing parsed yet: read+parse it. Round notes loop (they are
	// round by design); an ordinary video plays through and stops.
	// On failure say so and hand the file to the system player, which
	// also has the audio we cannot decode (§1.10: no dead play button).
	path := it.LocalPath
	loop := it.MediaType == engine.MediaVideoNote
	a.ensureH264Player(it.MsgID, path, loop, func() {
		a.setToast("Can't play this video in-app — opening system player")
		a.openMedia(path, true)
	})
}

// viewerVideoBar renders the transport controls (play/pause, scrubber,
// clocks) under the viewer's caption whenever the current item has an
// in-app player. Zero-height otherwise, so photo viewing is untouched.
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
					return a.videoTransportBtn(gtx, msgID, playing)
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
					})
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Left: unit.Dp(10)}.Layout(gtx,
						func(gtx layout.Context) layout.Dimensions {
							return videoClockLabel(gtx, a, toLabel)
						})
				}),
			)
		})

	// Keep the clocks and the scrubber in step with the playhead. The
	// frame itself re-arms through NextFrameIn; this tick covers the
	// paused case, where no frame re-arm is pending.
	gtx.Execute(op.InvalidateCmd{At: time.Now().Add(250 * time.Millisecond)})
	return dims
}

// videoClockLabel is the dim elapsed/total readout beside the scrubber.
func videoClockLabel(gtx layout.Context, a *App, s string) layout.Dimensions {
	lbl := a.ui.Label(unit.Sp(11), s)
	lbl.Color = color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xB0}
	return lbl.Layout(gtx)
}

// videoTransportBtn is the play/pause toggle at the head of the bar:
// accent while playing, neutral surface while paused.
func (a *App) videoTransportBtn(gtx layout.Context, msgID string, playing bool) layout.Dimensions {
	if a.wid.viewerVidPlayBtn.Clicked(gtx) {
		if playing {
			h264Players.pause(msgID)
		} else {
			h264Players.resume(msgID)
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
