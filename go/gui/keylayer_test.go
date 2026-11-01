package gui

import (
	"image"
	"testing"

	"gioui.org/f32"
	"gioui.org/io/input"
	"gioui.org/io/key"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/widget"
)

func TestShortcutsLayerDoesNotBlockPointerInput(t *testing.T) {
	var (
		r   input.Router
		ops op.Ops
		btn widget.Clickable
	)
	gtx := layout.Context{
		Ops:         &ops,
		Source:      r.Source(),
		Constraints: layout.Exact(image.Pt(800, 600)),
	}
	layoutFrame := func() {
		btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Dimensions{Size: image.Pt(100, 100)}
		})
		keyLayer(gtx, shortcutKeyTag)
	}
	layoutFrame()
	r.Frame(gtx.Ops)
	r.Queue(
		pointer.Event{Kind: pointer.Press, Source: pointer.Mouse, Buttons: pointer.ButtonPrimary, Position: f32.Pt(50, 50)},
		pointer.Event{Kind: pointer.Release, Source: pointer.Mouse, Buttons: pointer.ButtonPrimary, Position: f32.Pt(50, 50)},
	)
	if !btn.Clicked(gtx) {
		t.Fatal("pointer input blocked by the window-wide keyboard layer: button beneath it did not receive the click (input-freeze regression)")
	}
}

func TestShortcutsEscapeReachesLayer(t *testing.T) {
	var (
		r   input.Router
		ops op.Ops
	)
	gtx := layout.Context{
		Ops:         &ops,
		Source:      r.Source(),
		Constraints: layout.Exact(image.Pt(800, 600)),
	}
	drain := func() (got bool) {
		for {
			ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
			if !ok {
				break
			}
			if ke, is := ev.(key.Event); is && ke.State == key.Press {
				got = true
			}
		}
		return
	}
	frame := func() bool {
		gtx.Reset()
		keyLayer(gtx, shortcutKeyTag)
		got := drain()
		r.Frame(gtx.Ops)
		return got
	}
	if frame() {
		t.Fatal("no event queued yet; first frame should drain nothing")
	}
	r.Queue(key.Event{Name: key.NameEscape, State: key.Press})
	if !frame() {
		t.Fatal("keyboard layer did not receive the Escape press routed between frames")
	}
}
