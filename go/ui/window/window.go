package window

import (
	"math"
	"runtime"
	"time"

	gioapp "gioui.org/app"
	"gioui.org/io/key"
	"gioui.org/io/pointer"
	"gioui.org/io/system"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/paint"
	"gioui.org/unit"

	"uniclient/ui/app"
	"uniclient/ui/dialogs/render"
	"uniclient/ui/material"
	"uniclient/ui/tokens"
)

const msgQueueDepth = 64

const wheelScrollScale = 1 << 30

func Run() error {
	w := new(gioapp.Window)
	w.Option(
		gioapp.Size(unit.Dp(tokens.WindowDefaultWidth), unit.Dp(tokens.WindowDefaultHeight)),
		gioapp.MinSize(unit.Dp(tokens.WindowMinWidth), unit.Dp(tokens.WindowMinHeight)),
	)
	msgs := make(chan app.Msg, msgQueueDepth)
	appModel := app.InitialModel()
	painter := render.NewPainter()
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
			if appModel.KineticActive() {
				handle(app.DialogsTick{Now: int(time.Now().UnixMilli())})
			}
			gtx := gioapp.NewContext(&ops, e)
			routeInput(gtx, painter.Input, e.Metric, handle)
			scene := app.View(appModel)
			paint.Fill(gtx.Ops, scene.Background)
			painter.PaintPane(gtx, scene.Dialogs, material.SchemeFor(material.Light))
			if !appModel.Running {
				w.Perform(system.ActionClose)
			}
			e.Frame(gtx.Ops)
			if appModel.KineticActive() {
				w.Invalidate()
			}
		}
	}
}

func pxToDp(metric unit.Metric, v float32) int {
	return int(metric.PxToDp(int(math.Round(float64(v)))))
}

func routeInput(gtx layout.Context, tag *render.InputArea, metric unit.Metric, handle func(app.Msg)) {
	filter := pointer.Filter{
		Target:  tag,
		Kinds:   pointer.Press | pointer.Move | pointer.Drag | pointer.Release | pointer.Scroll | pointer.Cancel,
		ScrollX: pointer.ScrollRange{Min: -wheelScrollScale, Max: wheelScrollScale},
		ScrollY: pointer.ScrollRange{Min: -wheelScrollScale, Max: wheelScrollScale},
	}
	for {
		ev, ok := gtx.Event(filter)
		if !ok {
			return
		}
		e, ok := ev.(pointer.Event)
		if !ok {
			continue
		}
		switch e.Kind {
		case pointer.Press:
			gtx.Execute(pointer.GrabCmd{Tag: tag, ID: e.PointerID})
			handle(app.DialogsPressed{
				X:     pxToDp(metric, e.Position.X),
				Y:     pxToDp(metric, e.Position.Y),
				Touch: e.Source == pointer.Touch,
				Now:   int(time.Now().UnixMilli()),
			})
		case pointer.Move, pointer.Drag:
			handle(app.DialogsDragged{X: pxToDp(metric, e.Position.X), Y: pxToDp(metric, e.Position.Y), Now: int(time.Now().UnixMilli())})
		case pointer.Release:
			handle(app.DialogsReleased{X: pxToDp(metric, e.Position.X), Y: pxToDp(metric, e.Position.Y), Now: int(time.Now().UnixMilli())})
		case pointer.Cancel:
			handle(app.DialogsPressCanceled{})
		case pointer.Scroll:
			handle(scrollMessage(e, metric))
		}
	}
}

func scrollMessage(e pointer.Event, metric unit.Metric) app.Msg {
	accel := e.Modifiers&(key.ModCtrl|key.ModShift) != 0
	now := int(time.Now().UnixMilli())
	if runtime.GOOS == "windows" {
		return app.DialogsWheel{
			AngleX:     -int(e.Scroll.X),
			AngleY:     -int(e.Scroll.Y),
			Accelerate: accel,
			Now:        now,
		}
	}
	perDp := metric.PxPerDp
	if perDp <= 0 {
		perDp = 1
	}
	toDp := func(v float32) int {
		return int(math.Round(float64(v) / float64(perDp)))
	}
	return app.DialogsTrackpadScrolled{
		PixelX:     -toDp(e.Scroll.X),
		PixelY:     -toDp(e.Scroll.Y),
		Accelerate: accel,
		Now:        now,
	}
}
