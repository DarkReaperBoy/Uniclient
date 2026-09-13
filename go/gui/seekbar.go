package gui

// Music seek bar (slice 185, parity row "Audio file"): the music bubble's
// thin draggable progress track. Press, drag and release all seek — the
// fraction is the pointer's x over the track width, clamped and throttled
// to half-percent steps so a drag does not spam the player with seeks at
// sub-sample granularity.

import (
        "image"

        "gioui.org/io/event"
        "gioui.org/io/pointer"
        "gioui.org/layout"
        "gioui.org/op/clip"
        "gioui.org/op/paint"
        "gioui.org/unit"
)

// seekFraction maps a pointer x (local track coords) to a clamped 0..1
// playback fraction. Degenerate widths pass the current position through
// unchanged. Pure — unit-tested.
func seekFraction(px float32, width int, cur float64) float64 {
        if width <= 0 {
                return cur
        }
        f := float64(px) / float64(width)
        if f < 0 {
                return 0
        }
        if f > 1 {
                return 1
        }
        return f
}

// seekBarTags / seekBarApplied keep one stable pointer tag and the last
// applied fraction per player target (same lifecycle as the play
// clickables — reset wholesale past 512 entries).
func (a *App) seekBarTag(key string) *struct{} {
        if t, ok := a.wid.seekBarTags[key]; ok {
                return t
        }
        if len(a.wid.seekBarTags) > 512 {
                a.wid.seekBarTags = make(map[string]*struct{})
                a.wid.seekBarApplied = make(map[string]float64)
        }
        t := new(struct{})
        a.wid.seekBarTags[key] = t
        return t
}

// seekBar renders the draggable progress track. frac is the currently
// displayed position fraction; key scopes the pointer tag. The track is
// 14 dp tall (generous grab area) with a 3 dp visual bar and an accent
// handle dot at the playhead.
func (a *App) seekBar(gtx layout.Context, key string, frac float64) layout.Dimensions {
        w := gtx.Constraints.Max.X
        if w <= 0 {
                w = gtx.Dp(unit.Dp(120))
        }
        h := gtx.Dp(unit.Dp(14))
        tag := a.seekBarTag(key)

        // Input area: the full-height strip.
        stack := clip.Rect{Max: image.Pt(w, h)}.Push(gtx.Ops)
        event.Op(gtx.Ops, tag)
        for {
                ev, ok := gtx.Source.Event(pointer.Filter{Target: tag, Kinds: pointer.Press | pointer.Drag | pointer.Release})
                if !ok {
                        break
                }
                pe, is := ev.(pointer.Event)
                if !is {
                        continue
                }
                switch pe.Kind {
                case pointer.Press, pointer.Drag, pointer.Release:
                        f := seekFraction(pe.Position.X, w, frac)
                        if last, ok := a.wid.seekBarApplied[key]; ok && absF64(f-last) < 0.005 && pe.Kind == pointer.Drag {
                                continue // throttle sub-half-percent drag moves
                        }
                        a.wid.seekBarApplied[key] = f
                        _ = a.eng.SeekMedia(f)
                        a.startPlaybackTickerIfNeeded()
                        a.invalidate()
                }
        }
        stack.Pop()

        // Visual bar: centered 3 dp hairline + accent fill + handle.
        barY := (h - 3) / 2
        track := clip.Rect{Min: image.Pt(0, barY), Max: image.Pt(w, barY+3)}.Push(gtx.Ops)
        paint.Fill(gtx.Ops, a.ui.p.SurfaceHi)
        track.Pop()
        fw := int(frac * float64(w))
        if fw < 0 {
                fw = 0
        }
        if fw > w {
                fw = w
        }
        if fw > 0 {
                fill := clip.Rect{Min: image.Pt(0, barY), Max: image.Pt(fw, barY+3)}.Push(gtx.Ops)
                paint.Fill(gtx.Ops, a.ui.p.Accent)
                fill.Pop()
        }
        // Playhead dot (6 dp) centered on the fill edge.
        d := gtx.Dp(unit.Dp(6))
        cx := fw - d/2
        if cx < 0 {
                cx = 0
        }
        if cx > w-d {
                cx = w - d
        }
        cy := h/2 - d/2
        handle := clip.Ellipse{Min: image.Pt(cx, cy), Max: image.Pt(cx+d, cy+d)}.Push(gtx.Ops)
        paint.Fill(gtx.Ops, a.ui.p.Accent)
        handle.Pop()

        return layout.Dimensions{Size: image.Pt(w, h)}
}

// absF64 is |x| without pulling math into every caller.
func absF64(x float64) float64 {
        if x < 0 {
                return -x
        }
        return x
}
