package window

import (
	"image"
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

	"uniclient/engine"
	"uniclient/ui/app"
	"uniclient/ui/appport"
	"uniclient/ui/dialogs/render"
	chatrender "uniclient/ui/history/render"
	"uniclient/ui/material"
	"uniclient/ui/tokens"
)

const msgQueueDepth = 64

const wheelScrollScale = 1 << 30

const engineEventQueueDepth = 256

func Run(eng *engine.Engine) error {
	w := new(gioapp.Window)
	w.Option(
		gioapp.Size(unit.Dp(tokens.WindowDefaultWidth), unit.Dp(tokens.WindowDefaultHeight)),
		gioapp.MinSize(unit.Dp(tokens.WindowMinWidth), unit.Dp(tokens.WindowMinHeight)),
	)
	msgs := make(chan app.Msg, msgQueueDepth)
	appModel := app.InitialModel().WithPort(appport.For(eng))
	painter := render.NewPainter()
	chatPainter := chatrender.NewChatPainter()
	events := make(chan []byte, engineEventQueueDepth)
	done := make(chan struct{})
	defer close(done)
	sub := eng.Subscribe(func(data []byte) {
		select {
		case events <- data:
		default:
		}
	})
	defer sub.Unsubscribe()
	go func() {
		for {
			select {
			case data := <-events:
				select {
				case msgs <- app.EngineEventMsg{Data: data}:
				case <-done:
					return
				}
				w.Invalidate()
			case <-done:
				return
			}
		}
	}()
	handle := func(msg app.Msg) {
		var cmd app.Cmd
		appModel, cmd = app.Update(appModel, msg)
		if cmd != nil {
			go func(c app.Cmd) {
				if msg := c(); msg != nil {
					msgs <- msg
				}
				w.Invalidate()
			}(cmd)
		}
	}
	var ops op.Ops
	var lastW, lastH int
	var chatPrimary bool
	var keyFocus bool
	var searchFocus bool
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
			if appModel.KineticActive() || appModel.ChatDateActive() || appModel.ChatDownActive() || appModel.ChatMentionsActive() || appModel.ChatReactionsActive() || appModel.ChatRippleActive() || appModel.DialogsRippleActive() || appModel.DialogsToUpActive() || appModel.MenuActive() || appModel.ChatComposeBlinkActive() || appModel.SearchBlinkActive() || appModel.SearchGlobalPending() {
				handle(app.DialogsTick{Now: int(time.Now().UnixMilli())})
				handle(app.ChatTick{Now: int(time.Now().UnixMilli())})
			}
			gtx := gioapp.NewContext(&ops, e)
			routeInput(gtx, painter.Input, e.Metric, appModel, handle)
			routeSearchKeys(gtx, painter.Input, appModel, &searchFocus, handle)
			if cols := appModel.Columns(); cols.Chat > 0 && cols.Dialogs < appModel.Width {
				routeChatInput(gtx, chatPainter.Input, e.Metric, appModel, cols.Dialogs, &chatPrimary, handle)
				routeComposeKeys(gtx, chatPainter.Input, appModel, &keyFocus, handle)
			}
			if appModel.ChatDirty {
				heights, hits := chatPainter.Measure(
					gtx, appModel.Chat.Items, appModel.Columns().Chat)
				handle(app.ChatMeasured{Heights: heights, Hits: hits})
			}
			scene := app.View(appModel)
			paint.Fill(gtx.Ops, scene.Background)
			painter.PaintPane(gtx, scene.Dialogs, material.SchemeFor(material.Light))
			if cols := appModel.Columns(); cols.Chat > 0 && cols.Dialogs < appModel.Width {
				stk := op.Offset(image.Pt(gtx.Dp(unit.Dp(cols.Dialogs)), 0)).Push(gtx.Ops)
				chatPainter.PaintChatPane(gtx, scene.Chat, material.SchemeFor(material.Light))
				stk.Pop()
			}
			painter.PaintMenu(gtx, scene.Menu, material.SchemeFor(material.Light))
			if !appModel.Running {
				w.Perform(system.ActionClose)
			}
			e.Frame(gtx.Ops)
			if appModel.KineticActive() || appModel.ChatDateActive() || appModel.ChatDownActive() || appModel.ChatMentionsActive() || appModel.ChatReactionsActive() || appModel.ChatRippleActive() || appModel.DialogsRippleActive() || appModel.DialogsToUpActive() || appModel.MenuActive() || appModel.ChatComposeBlinkActive() || appModel.SearchBlinkActive() || appModel.SearchGlobalPending() {
				w.Invalidate()
			}
		}
	}
}

func pxToDp(metric unit.Metric, v float32) int {
	return int(metric.PxToDp(int(math.Round(float64(v)))))
}

func routeInput(gtx layout.Context, tag *render.InputArea, metric unit.Metric, model app.Model, handle func(app.Msg)) {
	filter := pointer.Filter{
		Target:  tag,
		Kinds:   pointer.Press | pointer.Move | pointer.Drag | pointer.Release | pointer.Scroll | pointer.Cancel | pointer.Leave,
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
			x, y := pxToDp(metric, e.Position.X), pxToDp(metric, e.Position.Y)
			now := int(time.Now().UnixMilli())
			if scrim, eat := model.MenuPressRoute(x, y); scrim || eat {
				if scrim {
					handle(app.MenuScrimPressed{Now: now})
				}
				continue
			}
			gtx.Execute(pointer.GrabCmd{Tag: tag, ID: e.PointerID})
			if y < tokens.TopBarHeight {
				handle(app.DialogsHeaderPressed{X: x, Y: y, Now: now})
				continue
			}
			handle(app.DialogsPressed{
				X:     x,
				Y:     y - tokens.TopBarHeight,
				Touch: e.Source == pointer.Touch,
				Now:   now,
			})
		case pointer.Move, pointer.Drag:
			handle(app.DialogsDragged{X: pxToDp(metric, e.Position.X), Y: pxToDp(metric, e.Position.Y) - tokens.TopBarHeight, Touch: e.Source == pointer.Touch, Now: int(time.Now().UnixMilli())})
		case pointer.Leave:
			handle(app.DialogsLeft{})
		case pointer.Release:
			handle(app.DialogsReleased{X: pxToDp(metric, e.Position.X), Y: pxToDp(metric, e.Position.Y) - tokens.TopBarHeight, Now: int(time.Now().UnixMilli())})
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

func routeChatInput(gtx layout.Context, tag *chatrender.InputArea, metric unit.Metric, model app.Model, dialogsDp int, chatPrimary *bool, handle func(app.Msg)) {
	filter := pointer.Filter{
		Target:  tag,
		Kinds:   pointer.Press | pointer.Move | pointer.Drag | pointer.Release | pointer.Scroll | pointer.Cancel | pointer.Leave,
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
			if scrim, eat := model.MenuPressRoute(pxToDp(metric, e.Position.X), pxToDp(metric, e.Position.Y)); scrim || eat {
				if scrim {
					handle(app.MenuScrimPressed{Now: int(time.Now().UnixMilli())})
				}
				continue
			}
			if e.Source == pointer.Touch {
				gtx.Execute(pointer.GrabCmd{Tag: tag, ID: e.PointerID})
				handle(app.ChatPressed{
					X:     pxToDp(metric, e.Position.X) - dialogsDp,
					Y:     pxToDp(metric, e.Position.Y),
					Touch: true,
					Now:   int(time.Now().UnixMilli()),
				})
			} else if e.Buttons&pointer.ButtonPrimary != 0 {
				gtx.Execute(pointer.GrabCmd{Tag: tag, ID: e.PointerID})
				*chatPrimary = true
				handle(app.ChatPressed{
					X:     pxToDp(metric, e.Position.X) - dialogsDp,
					Y:     pxToDp(metric, e.Position.Y),
					Shift: e.Modifiers&key.ModShift != 0,
					Now:   int(time.Now().UnixMilli()),
				})
			}
		case pointer.Move, pointer.Drag:
			handle(app.ChatDragged{X: pxToDp(metric, e.Position.X) - dialogsDp, Y: pxToDp(metric, e.Position.Y), Touch: e.Source == pointer.Touch, Now: int(time.Now().UnixMilli())})
		case pointer.Leave:
			handle(app.ChatLeft{})
		case pointer.Release:
			if e.Source == pointer.Touch || *chatPrimary {
				if e.Source != pointer.Touch {
					*chatPrimary = false
				}
				handle(app.ChatReleased{X: pxToDp(metric, e.Position.X) - dialogsDp, Y: pxToDp(metric, e.Position.Y), Now: int(time.Now().UnixMilli())})
			}
		case pointer.Cancel:
			*chatPrimary = false
			handle(app.ChatPressCanceled{})
		case pointer.Scroll:
			handle(chatScrollMessage(e, metric))
		}
	}
}

func routeComposeKeys(gtx layout.Context, tag *chatrender.InputArea, model app.Model, focus *bool, handle func(app.Msg)) {
	want := model.ChatCompose.Focused && model.ChatCompose.CanSend
	if want != *focus {
		*focus = want
		if want {
			gtx.Execute(key.FocusCmd{Tag: tag})
		} else {
			gtx.Execute(key.FocusCmd{Tag: nil})
		}
		gtx.Execute(key.SoftKeyboardCmd{Show: want})
	}
	focusFilter := key.FocusFilter{Target: tag}
	for {
		ev, ok := gtx.Event(focusFilter)
		if !ok {
			break
		}
		switch e := ev.(type) {
		case key.EditEvent:
			if msg := app.ComposeEditMsg(e, int(time.Now().UnixMilli())); msg != nil {
				handle(msg)
			}
		case key.FocusEvent:
			if !e.Focus && *focus {
				*focus = false
				handle(app.ChatComposeFocusLost{})
			}
		}
	}
	keyFilter := key.Filter{Focus: tag, Optional: key.ModShift | key.ModCtrl}
	for {
		ev, ok := gtx.Event(keyFilter)
		if !ok {
			break
		}
		if e, ok := ev.(key.Event); ok {
			if msg := app.ComposeKeyMsg(e, int(time.Now().UnixMilli())); msg != nil {
				handle(msg)
			}
		}
	}
}

func routeSearchKeys(gtx layout.Context, tag *render.InputArea, model app.Model, focus *bool, handle func(app.Msg)) {
	want := model.Search.Focused
	if want != *focus {
		*focus = want
		if want {
			gtx.Execute(key.FocusCmd{Tag: tag})
		} else {
			gtx.Execute(key.FocusCmd{Tag: nil})
		}
		gtx.Execute(key.SoftKeyboardCmd{Show: want})
	}
	focusFilter := key.FocusFilter{Target: tag}
	for {
		ev, ok := gtx.Event(focusFilter)
		if !ok {
			break
		}
		switch e := ev.(type) {
		case key.EditEvent:
			if msg := app.SearchEditMsg(e, int(time.Now().UnixMilli())); msg != nil {
				handle(msg)
			}
		case key.FocusEvent:
			if !e.Focus && *focus {
				*focus = false
				handle(app.SearchFocusLost{})
			}
		}
	}
	keyFilter := key.Filter{Focus: tag, Optional: key.ModShift | key.ModCtrl}
	for {
		ev, ok := gtx.Event(keyFilter)
		if !ok {
			break
		}
		if e, ok := ev.(key.Event); ok {
			if msg := app.SearchKeyMsg(e, int(time.Now().UnixMilli())); msg != nil {
				handle(msg)
			}
		}
	}
}

func chatScrollMessage(e pointer.Event, metric unit.Metric) app.Msg {
	accel := e.Modifiers&(key.ModCtrl|key.ModShift) != 0
	now := int(time.Now().UnixMilli())
	y := pxToDp(metric, e.Position.Y)
	if runtime.GOOS == "windows" {
		return app.ChatWheel{
			AngleX:     -int(e.Scroll.X),
			AngleY:     -int(e.Scroll.Y),
			Accelerate: accel,
			Now:        now,
			Y:          y,
		}
	}
	perDp := metric.PxPerDp
	if perDp <= 0 {
		perDp = 1
	}
	toDp := func(v float32) int {
		return int(math.Round(float64(v) / float64(perDp)))
	}
	return app.ChatTrackpadScrolled{
		PixelX:     -toDp(e.Scroll.X),
		PixelY:     -toDp(e.Scroll.Y),
		Accelerate: accel,
		Now:        now,
		Y:          y,
	}
}
