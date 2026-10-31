package gui

import (
	"image"
	"testing"

	"gioui.org/io/input"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op"
)

// TestCtrlTabReachesAccountSwitchLoop pins the event-delivery order inside
// layoutShortcuts (R16): a key event is delivered to a handler once per
// frame, so a broader filter consumes events that narrower, later drains
// were meant to handle. Before R16 the generic `key.Filter{Required:
// key.ModCtrl}` drain ran BEFORE the Tab-specific drain — it dequeued
// Ctrl+Tab / Ctrl+Shift+Tab without acting on them and the account-scope
// cycling (slice 147) never fired.
//
// The drain below mirrors layoutShortcuts' Event() call sequence in the
// FIXED order (Tab-specific before generic Ctrl); a control assertion
// checks Ctrl+Up still reaches the generic loop (chat switching).
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

	// drain mirrors layoutShortcuts' loops in the FIXED order (R16): the
	// Tab-specific drain runs BEFORE the generic ModCtrl drain, because a
	// key event is delivered once per frame and the broader filter would
	// otherwise consume Tab presses without acting on them. Returns whether
	// the Tab-specific loop saw a press and whether the generic Ctrl loop
	// saw one at all.
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

	// Frame 1 declares the handlers so the queued press routes to this tag
	// next frame (the real frame cadence — mirrors keylayer_test.go).
	if tab, ctrl := frame(); tab || ctrl {
		t.Fatal("nothing queued yet; first frame must drain no key events")
	}

	// Ctrl+Tab press, then the next frame's drain.
	r.Queue(key.Event{Name: key.NameTab, State: key.Press, Modifiers: key.ModCtrl})
	tab, ctrl := frame()
	if !tab && !ctrl {
		t.Fatal("Ctrl+Tab press was not seen by any ctrl-filtered loop — delivery assumptions changed")
	}
	if !tab {
		t.Fatal("Ctrl+Tab never reaches the Tab-specific account-switch loop: a broader ModCtrl drain consumed it first (the R16 ordering regressed)")
	}

	// Control: a Ctrl+Up press must still reach the generic loop (chat
	// switching) — the fix must not starve it.
	r.Queue(key.Event{Name: key.NameUpArrow, State: key.Press, Modifiers: key.ModCtrl})
	if tab, ctrl := frame(); tab || !ctrl {
		t.Fatalf("control assertion failed: Ctrl+Up should reach the generic ctrl loop only (tab=%v ctrl=%v)", tab, ctrl)
	}
}
