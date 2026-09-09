package gui

import (
	"image"

	"gioui.org/io/event"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op/clip"
)

// keyLayer registers tag as a window-wide key-event listener that is
// transparent (pointer.PassOp) to pointer hit-testing. Full-window key
// grabs that must not intercept pointer events use this — a bare
// clip+event.Op registers an opaque hit node at the top of the hit tree
// which short-circuits the hit-test walk for every position and freezes
// ALL pointer input beneath it.
//
// Regression history (2026-09-09): the global shortcuts layer used the
// opaque form and froze every button, editor and list from the first
// frame it rendered — the welcome/picker screens (which skip it via an
// early return in Root) still worked, everything after adding an account
// was dead. TestShortcutsLayerDoesNotBlockPointerInput pins the fix.
//
// Modal layers that intentionally block input behind them (dialog scrims)
// must NOT use this; they keep their own opaque registration.
func keyLayer(gtx layout.Context, tag event.Tag) {
	pass := pointer.PassOp{}.Push(gtx.Ops)
	stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
	event.Op(gtx.Ops, tag)
	stack.Pop()
	pass.Pop()
}
