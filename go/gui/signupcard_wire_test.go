package gui

import (
	"image"
	"testing"

	"gioui.org/f32"
	"gioui.org/io/input"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op"

	"uniclient/engine"
)

func TestSignupStepRendersDedicatedCard(t *testing.T) {
	a := &App{ui: NewUI()}
	a.wid.init()
	signupFirstEd.SetText("")
	signupLastEd.SetText("")
	t.Cleanup(func() {
		signupFirstEd.SetText("")
		signupLastEd.SetText("")
		a.mu.Lock()
		a.toast = ""
		a.mu.Unlock()
	})
	toast := func() string {
		a.mu.Lock()
		defer a.mu.Unlock()
		return a.toast
	}

	var r input.Router
	var ops op.Ops
	gtx := layout.Context{
		Ops:         &ops,
		Source:      r.Source(),
		Constraints: layout.Exact(image.Pt(800, 600)),
	}
	st := &engine.AuthState{State: engine.AuthStateSignUp}
	f := frame{}

	a.authCard(gtx, f, st)
	r.Frame(&ops)

	for y := 280; y < 370 && toast() == ""; y += 20 {
		for x := 30; x < 770 && toast() == ""; x += 20 {
			pos := f32.Pt(float32(x), float32(y))
			r.Queue(
				pointer.Event{Kind: pointer.Press, Source: pointer.Mouse,
					Buttons: pointer.ButtonPrimary, Position: pos},
				pointer.Event{Kind: pointer.Release, Source: pointer.Mouse,
					Buttons: pointer.ButtonPrimary, Position: pos},
			)
			a.authCard(gtx, f, st)
			r.Frame(&ops)
		}
	}

	if got := toast(); got != "Enter your first name" {
		t.Fatalf("signup step did not render the dedicated card (toast=%q) — authCard has no AuthStateSignUp case, so the first/last split and photo circle are unreachable and last names merge again (B-13)", got)
	}
}
