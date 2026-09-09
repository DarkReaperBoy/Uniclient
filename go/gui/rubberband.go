package gui

import (
	"image"

	"gioui.org/io/event"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
)

// Rubber-band selection (AyuGram §3 "Message selection mode", slice 84):
// in selection mode, dragging over the message list marks every visible
// row the rectangle touches. The overlay passes pointer events through
// (bubbles keep their tap-to-toggle; the list keeps wheel scrolling —
// desktop mouse drags do not scroll a Gio List, so there is no fight).

var (
	rubberTag   = new(struct{})
	rubberOn    bool // gesture in progress (frame-loop only)
	rubberStart image.Point
	rubberCur   image.Point
)

// rubberSelectRect normalizes the gesture's points into a rectangle —
// drags in any direction (up-left, down-right…) produce the same rect.
// Pure — locked by tests.
func rubberSelectRect(start, cur image.Point) image.Rectangle {
	r := image.Rectangle{Min: start, Max: cur}
	if r.Min.X > r.Max.X {
		r.Min.X, r.Max.X = r.Max.X, r.Min.X
	}
	if r.Min.Y > r.Max.Y {
		r.Min.Y, r.Max.Y = r.Max.Y, r.Min.Y
	}
	return r.Canon()
}

// rubberHits returns the row indexes whose bounds intersect the rect.
// Zero-area rects (plain taps) hit nothing. Pure — locked by tests.
func rubberHits(bounds map[int]image.Rectangle, rect image.Rectangle) []int {
	if rect.Dx() <= 0 && rect.Dy() <= 0 {
		return nil
	}
	var hits []int
	for i, b := range bounds {
		if b.Overlaps(rect) {
			hits = append(hits, i)
		}
	}
	return hits
}

// rubberBandOverlay registers the drag gesture over the message viewport
// and draws the selection rectangle while active. Called after the list
// laid out (this frame's rowBounds are filled). Points are converted to
// pane coordinates (rowBounds are pane-absolute).
func (a *App) rubberBandOverlay(gtx layout.Context, f frame, size image.Point) {
	if !f.selOn {
		// Selection mode left mid-drag: drop the gesture.
		rubberOn = false
		return
	}

	// Pass-through hit node (bubbles underneath keep their tap-to-toggle;
	// the list keeps wheel scrolling — desktop mouse drags do not scroll
	// a Gio List, so there is no gesture fight).
	defer pointer.PassOp{}.Push(gtx.Ops).Pop()
	{
		stack := clip.Rect{Max: size}.Push(gtx.Ops)
		event.Op(gtx.Ops, rubberTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(pointer.Filter{
			Target: rubberTag,
			Kinds:  pointer.Press | pointer.Drag | pointer.Release | pointer.Cancel,
		})
		if !ok {
			break
		}
		e, is := ev.(pointer.Event)
		if !is {
			continue
		}
		switch e.Kind {
		case pointer.Press:
			if e.Buttons == pointer.ButtonPrimary {
				rubberOn = true
				rubberStart = e.Position.Round().Add(image.Pt(0, a.listTop))
				rubberCur = rubberStart
			}
		case pointer.Drag:
			if rubberOn {
				rubberCur = e.Position.Round().Add(image.Pt(0, a.listTop))
			}
		case pointer.Release, pointer.Cancel:
			if rubberOn {
				rect := rubberSelectRect(rubberStart, rubberCur)
				a.rubberApply(f, rubberHits(a.rowBounds, rect))
				rubberOn = false
			}
		}
	}

	if rubberOn {
		rect := rubberSelectRect(rubberStart, rubberCur)
		// Pane coords → this overlay's local space.
		r := rect.Sub(image.Pt(0, a.listTop))
		defer op.Offset(r.Min).Push(gtx.Ops).Pop()
		sz := r.Max.Sub(r.Min)
		defer clip.Rect{Max: sz}.Push(gtx.Ops).Pop()
		paint.FillShape(gtx.Ops, withAlpha(a.ui.p.Accent, 0x30), clip.Rect{Max: sz}.Op())
	}
}

// rubberApply marks the hit messages (row indexes → msg ids).
func (a *App) rubberApply(f frame, hits []int) {
	if len(hits) == 0 {
		return
	}
	a.mu.Lock()
	if a.sel == nil {
		a.sel = map[string]bool{}
	}
	for _, idx := range hits {
		if idx >= 0 && idx < len(f.messages) {
			a.sel[f.messages[idx].MsgID] = true
		}
	}
	a.selOn = true
	a.mu.Unlock()
	a.invalidate()
}
