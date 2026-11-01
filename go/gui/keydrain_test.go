package gui

import (
	"image"
	"testing"

	"gioui.org/io/input"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op"
)

func TestCtrlTabReachesAccountSwitchLoop(t *testing.T) {
	var (
		r   input.Router
		ops op.Ops
	)
	gtx := layout.Context{
		Ops:         &ops,
		Source:      r.Source(),
		Constraints: layout.Exact(image.Pt(800, 600)),
	}

	drain := func() (tabLoopSaw, ctrlLoopSaw bool) {
		for {
			if _, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape}); !ok {
				break
			}
		}
		for {
			if _, ok := gtx.Source.Event(key.Filter{Name: "F", Required: key.ModCtrl}); !ok {
				break
			}
		}
		for {
			ev, ok := gtx.Source.Event(key.Filter{Name: key.NameTab, Required: key.ModCtrl})
			if !ok {
				break
			}
			if ke, is := ev.(key.Event); is && ke.State == key.Press {
				tabLoopSaw = true
			}
		}
		for {
			ev, ok := gtx.Source.Event(key.Filter{Required: key.ModCtrl})
			if !ok {
				break
			}
			if ke, is := ev.(key.Event); is && ke.State == key.Press {
				ctrlLoopSaw = true
			}
		}
		for {
			if _, ok := gtx.Source.Event(key.Filter{Required: key.ModAlt}); !ok {
				break
			}
		}
		return
	}
	frame := func() (tabLoopSaw, ctrlLoopSaw bool) {
		gtx.Reset()
		keyLayer(gtx, shortcutKeyTag)
		tabLoopSaw, ctrlLoopSaw = drain()
		r.Frame(gtx.Ops)
		return
	}

	if tab, ctrl := frame(); tab || ctrl {
		t.Fatal("nothing queued yet; first frame must drain no key events")
	}

	r.Queue(key.Event{Name: key.NameTab, State: key.Press, Modifiers: key.ModCtrl})
	tab, ctrl := frame()
	if !tab && !ctrl {
		t.Fatal("Ctrl+Tab press was not seen by any ctrl-filtered loop — delivery assumptions changed")
	}
	if !tab {
		t.Fatal("Ctrl+Tab never reaches the Tab-specific account-switch loop: a broader ModCtrl drain consumed it first (the R16 ordering regressed)")
	}

	r.Queue(key.Event{Name: key.NameUpArrow, State: key.Press, Modifiers: key.ModCtrl})
	if tab, ctrl := frame(); tab || !ctrl {
		t.Fatalf("control assertion failed: Ctrl+Up should reach the generic ctrl loop only (tab=%v ctrl=%v)", tab, ctrl)
	}
}
