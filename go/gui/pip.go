package gui

// pip.go — slice 222: picture-in-picture, parity row 279 — the matrix's
// ONLY MISSING row. The video keeps playing in a small floating panel
// while the rest of the app stays usable.
//
// Why a floating panel inside the window rather than a second OS window:
// Gio exposes no always-on-top option on our platforms (the one flag it
// has lives in the macOS backend, which §1.2 bans), and Gio allows extra
// native windows only on linux and windows — never on Android, which is
// a first-class target here (see separateWindowSupported). An OS window
// would either sit BEHIND the main window, making it useless, or not
// exist at all on Android. A panel drawn over every surface stays visible
// everywhere and works on both first-class platforms. That deviation from
// an OS-level window is reported rather than papered over (§1.10).
//
// It shares the slice-220/221 player cache, so popping out continues the
// same decode instead of starting a second one, and closing the media
// viewer does not stop playback.

import (
	"image"
	"image/color"
	"time"

	"gioui.org/io/event"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// pipMargin is the gap left between the panel and the window edge when it
// is first parked in the bottom-right corner.
const pipMargin = 16

// pipStripH is the height reserved for the transport strip under the video.
const pipStripDp = 34

// pipState is one floating panel. Field mutations are GUI-loop only (the
// drag handler and start/stop), exactly like viewerState: snapshot()
// hands frames the pointer and the frame goroutine reads through it.
type pipState struct {
	msgID string
	vidW  int
	vidH  int

	// Panel geometry in viewport pixels.
	x, y, w, h int

	// Drag: local pointer position at the previous event. Deltas are
	// used rather than an absolute target because the panel MOVES under
	// the pointer, so its local coordinates change on every event.
	lastX, lastY int
	dragging     bool
}

// ── pure geometry (unit-tested in pip_test.go) ─────────────────────────

// pipSize returns the panel box for a clip: the target width is clamped
// between a sixth and a third of the window, the height follows the
// clip's aspect ratio, and a short window caps the height (shrinking the
// width with it) so the panel can never overflow the window it floats in.
// Degenerate clip metadata falls back to 16:9; a non-positive viewport
// yields no panel at all. Pure — unit-tested.
func pipSize(targetW, vpW, vpH, vidW, vidH int) (int, int) {
	if vpW <= 0 || vpH <= 0 {
		return 0, 0
	}
	lo, hi := vpW/6, vpW/3
	if lo < 1 {
		lo = 1
	}
	if hi < lo {
		hi = lo
	}
	w := targetW
	if w < lo {
		w = lo
	}
	if w > hi {
		w = hi
	}
	if vidW <= 0 || vidH <= 0 {
		vidW, vidH = 16, 9
	}
	h := w * vidH / vidW
	if h < 1 {
		h = 1
	}
	if maxH := vpH / 2; maxH > 0 && h > maxH {
		w = w * maxH / h
		if w < 1 {
			w = 1
		}
		h = maxH
	}
	return w, h
}

// pipClamp keeps the panel fully inside the viewport, so it can always be
// grabbed again after a resize. Pure — unit-tested.
func pipClamp(x, y, w, h, vpW, vpH int) (int, int) {
	maxX, maxY := vpW-w, vpH-h
	if maxX < 0 {
		maxX = 0
	}
	if maxY < 0 {
		maxY = 0
	}
	if x < 0 {
		x = 0
	}
	if y < 0 {
		y = 0
	}
	if x > maxX {
		x = maxX
	}
	if y > maxY {
		y = maxY
	}
	return x, y
}

// pipPosAfterDrag applies a pointer delta to the panel origin and clamps
// it, so a drag can move the panel but never out of reach.
// Pure — unit-tested.
func pipPosAfterDrag(x, y, dx, dy, w, h, vpW, vpH int) (int, int) {
	return pipClamp(x+dx, y+dy, w, h, vpW, vpH)
}

// pipEligible reports whether an item can pop out: a video we can actually
// play in-app (downloaded, in a container h264vid might decode) — a photo
// or a not-yet-downloaded file must never open an empty panel.
// Pure — unit-tested.
func pipEligible(it engine.SharedMediaItem) bool {
	return viewerCanPlayInApp(it)
}

// ── state transitions ──────────────────────────────────────────────────

// startPip opens (or re-targets) the floating panel. The first open parks
// it bottom-right; reopening with another clip keeps the position so
// navigating videos does not teleport the panel across the window.
func (a *App) startPip(msgID string, vidW, vidH, vpW, vpH int) {
	if msgID == "" || vpW <= 0 || vpH <= 0 {
		return
	}
	w, h := pipSize(vpW/3, vpW, vpH, vidW, vidH)
	if w <= 0 || h <= 0 {
		return
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.pip == nil {
		a.pip = &pipState{msgID: msgID, vidW: vidW, vidH: vidH, w: w, h: h}
		a.pip.x, a.pip.y = pipClamp(vpW-w-pipMargin, vpH-h-pipMargin, w, h, vpW, vpH)
		return
	}
	a.pip.msgID, a.pip.vidW, a.pip.vidH = msgID, vidW, vidH
	a.pip.w, a.pip.h = w, h
	a.pip.x, a.pip.y = pipClamp(a.pip.x, a.pip.y, w, h, vpW, vpH)
}

// stopPip closes the panel and PAUSES its clip — an invisible panel must
// not keep burning decode CPU. Idempotent.
func (a *App) stopPip() {
	a.mu.Lock()
	p := a.pip
	a.pip = nil
	a.mu.Unlock()
	if p != nil {
		h264Players.pause(p.msgID)
	}
}

// ── rendering ──────────────────────────────────────────────────────────

// layoutPip draws the floating panel over everything except the toast and
// shortcut layers. Zero-cost when no panel is open.
func (a *App) layoutPip(gtx layout.Context, f frame) {
	p := f.pip
	if p == nil || p.w <= 0 || p.h <= 0 {
		return
	}
	vpW, vpH := gtx.Constraints.Max.X, gtx.Constraints.Max.Y
	if vpW <= 0 || vpH <= 0 {
		return
	}
	// The window may have shrunk under the panel, so re-clamp every frame
	// before drawing — a panel parked off-screen could never be grabbed.
	p.x, p.y = pipClamp(p.x, p.y, p.w, p.h, vpW, vpH)

	// Everything below is in panel-local coordinates.
	offset := op.Offset(image.Pt(p.x, p.y)).Push(gtx.Ops)
	defer offset.Pop()
	body := clip.Rect{Max: image.Pt(p.w, p.h)}.Push(gtx.Ops)
	defer body.Pop()

	// Body card.
	paint.Fill(gtx.Ops, a.ui.p.Surface)

	// Drag area covers the whole panel; registered BEFORE the buttons so
	// they win the hit test (a click must not start a drag).
	a.pipDrag(gtx, p, vpW, vpH)

	stripH := gtx.Dp(unit.Dp(pipStripDp))
	frameH := p.h - stripH
	if frameH < 0 {
		frameH = 0
	}
	a.pipFrame(gtx, p, frameH)
	a.pipControls(gtx, p, frameH, stripH)
}

// pipDrag moves the panel by pointer deltas while dragged. Delta-based
// rather than absolute because the panel travels with the pointer, so its
// local coordinates change on every event — an absolute target would run
// away from the cursor.
func (a *App) pipDrag(gtx layout.Context, p *pipState, vpW, vpH int) {
	if a.wid.pipTag == nil {
		a.wid.pipTag = new(struct{})
	}
	tag := a.wid.pipTag
	area := clip.Rect{Max: image.Pt(p.w, p.h)}.Push(gtx.Ops)
	event.Op(gtx.Ops, tag)
	for {
		ev, ok := gtx.Source.Event(pointer.Filter{
			Target: tag,
			Kinds:  pointer.Press | pointer.Drag | pointer.Release,
		})
		if !ok {
			break
		}
		pe, is := ev.(pointer.Event)
		if !is {
			continue
		}
		lx, ly := int(pe.Position.X), int(pe.Position.Y)
		switch pe.Kind {
		case pointer.Press:
			p.dragging = true
			p.lastX, p.lastY = lx, ly
		case pointer.Drag:
			if !p.dragging {
				continue
			}
			dx, dy := lx-p.lastX, ly-p.lastY
			p.lastX, p.lastY = lx, ly
			p.x, p.y = pipPosAfterDrag(p.x, p.y, dx, dy, p.w, p.h, vpW, vpH)
		case pointer.Release, pointer.Cancel:
			p.dragging = false
		}
	}
	area.Pop()
}

// pipFrame paints the current decoded frame (or holds a black box while
// the producer warms up) and re-arms the next repaint.
func (a *App) pipFrame(gtx layout.Context, p *pipState, frameH int) {
	if frameH <= 0 {
		return
	}
	defer clip.Rect{Max: image.Pt(p.w, frameH)}.Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, color.NRGBA{A: 0xFF})

	st, ok := h264Players.peek(p.msgID)
	if !ok || !st.playing || st.player == nil || st.video == nil {
		return
	}
	elapsed := h264Players.elapsed(p.msgID)
	fr := st.player.FrameAt(elapsed)
	if fr == nil {
		return
	}
	// Cover-fit so the panel is always filled, even if the clip's aspect
	// differs from the box (letterboxing a PiP panel looks broken).
	drawImageCover(gtx, fr, p.w, frameH)
	if !powerSavingBlocks(powerSaving.flags, powerSaving.forceAll, psClassVideo) {
		gtx.Execute(op.InvalidateCmd{At: time.Now().Add(st.player.NextFrameIn(elapsed))})
	}
}

// pipControls renders the transport strip: play/pause, the clocks, and a
// close button that also stops the decode.
func (a *App) pipControls(gtx layout.Context, p *pipState, frameH, stripH int) {
	st, has := h264Players.peek(p.msgID)
	playing := has && st.playing

	if a.wid.pipPlayBtn.Clicked(gtx) {
		if playing {
			h264Players.pause(p.msgID)
		} else {
			h264Players.resume(p.msgID)
		}
		a.invalidate()
	}
	if a.wid.pipCloseBtn.Clicked(gtx) {
		a.stopPip()
		a.invalidate()
		return
	}

	elLabel, toLabel := "0:00", "0:00"
	if has && st.video != nil {
		elLabel, toLabel = videoTimes(h264Players.elapsed(p.msgID), st.video.Total)
	}

	stack := op.Offset(image.Pt(0, frameH)).Push(gtx.Ops)
	defer stack.Pop()

	layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return a.pipButton(gtx, &a.wid.pipPlayBtn, transportGlyph(playing))
			})
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Left: unit.Dp(6), Right: unit.Dp(6)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(10), elLabel+" / "+toLabel)
					lbl.Color = color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xB0}
					return lbl.Layout(gtx)
				})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return a.pipButton(gtx, &a.wid.pipCloseBtn, "✕")
			})
		}),
	)
	_ = stripH
}

// transportGlyph is the play/pause mark shared by the viewer bar and the
// PiP strip.
func transportGlyph(playing bool) string {
	if playing {
		return "⏸"
	}
	return "▶"
}

// pipButton draws a round control. Its Clickable is laid out here so the
// input area exists — the Clicked checks in pipControls consume the event
// (one-shot), which is why they run before this draw.
func (a *App) pipButton(gtx layout.Context, btn *widget.Clickable, label string) layout.Dimensions {
	b := material.ButtonLayout(a.ui.Theme, btn)
	b.Background = a.ui.p.SurfaceHi
	b.CornerRadius = 14
	return b.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4), Left: unit.Dp(7), Right: unit.Dp(7)}.Layout(gtx,
			func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Label(unit.Sp(11), label)
				lbl.Color = color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xE0}
				return lbl.Layout(gtx)
			})
	})
}
