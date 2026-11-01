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

var rubberTag = new(struct{})

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

func (a *App) rubberBandOverlay(gtx layout.Context, f frame, size image.Point) {
	if !f.selOn {
		a.rubberOn = false
		return
	}

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
				a.rubberOn = true
				a.rubberStart = e.Position.Round().Add(image.Pt(0, a.listTop))
				a.rubberCur = a.rubberStart
			}
		case pointer.Drag:
			if a.rubberOn {
				a.rubberCur = e.Position.Round().Add(image.Pt(0, a.listTop))
			}
		case pointer.Release, pointer.Cancel:
			if a.rubberOn {
				rect := rubberSelectRect(a.rubberStart, a.rubberCur)
				a.rubberApply(f, rubberHits(a.rowBounds, rect))
				a.rubberOn = false
			}
		}
	}

	if a.rubberOn {
		rect := rubberSelectRect(a.rubberStart, a.rubberCur)
		r := rect.Sub(image.Pt(0, a.listTop))
		defer op.Offset(r.Min).Push(gtx.Ops).Pop()
		sz := r.Max.Sub(r.Min)
		defer clip.Rect{Max: sz}.Push(gtx.Ops).Pop()
		paint.FillShape(gtx.Ops, withAlpha(a.ui.p.Accent, 0x30), clip.Rect{Max: sz}.Op())
	}
}

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
