package window

import (
	gioapp "gioui.org/app"
	"gioui.org/io/system"
	"gioui.org/op"
	"gioui.org/op/paint"
	"gioui.org/unit"

	"uniclient/ui/app"
	"uniclient/ui/tokens"
)

const msgQueueDepth = 64

func Run() error {
	w := new(gioapp.Window)
	w.Option(
		gioapp.Size(unit.Dp(tokens.WindowDefaultWidth), unit.Dp(tokens.WindowDefaultHeight)),
		gioapp.MinSize(unit.Dp(tokens.WindowMinWidth), unit.Dp(tokens.WindowMinHeight)),
	)
	msgs := make(chan app.Msg, msgQueueDepth)
	appModel := app.InitialModel()
	handle := func(msg app.Msg) {
		var cmd app.Cmd
		appModel, cmd = app.Update(appModel, msg)
		if cmd != nil {
			go func(c app.Cmd) {
				msgs <- c()
				w.Invalidate()
			}(cmd)
		}
	}
	var ops op.Ops
	var lastW, lastH int
	for {
		switch e := w.Event().(type) {
		case gioapp.DestroyEvent:
			return e.Err
		case gioapp.FrameEvent:
			draining := true
			for draining {
				select {
				case msg := <-msgs:
					handle(msg)
				default:
					draining = false
				}
			}
			if dpW, dpH := int(e.Metric.PxToDp(e.Size.X)), int(e.Metric.PxToDp(e.Size.Y)); dpW != lastW || dpH != lastH {
				lastW, lastH = dpW, dpH
				handle(app.Resized{Width: dpW, Height: dpH})
			}
			if !appModel.Running {
				w.Perform(system.ActionClose)
			}
			gtx := gioapp.NewContext(&ops, e)
			paint.Fill(gtx.Ops, app.View(appModel).Background)
			e.Frame(gtx.Ops)
		}
	}
}
