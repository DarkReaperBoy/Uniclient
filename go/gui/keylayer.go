package gui

import (
	"image"

	"gioui.org/io/event"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op/clip"
)

func keyLayer(gtx layout.Context, tag event.Tag) {
	pass := pointer.PassOp{}.Push(gtx.Ops)
	stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
	event.Op(gtx.Ops, tag)
	stack.Pop()
	pass.Pop()
}
