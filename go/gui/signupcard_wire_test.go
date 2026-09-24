package gui

// tests-first for BUGS.md B-13 — the AuthStateSignUp step must render
// the DEDICATED signup card (First/Last split + photo circle + Create
// account), not the generic single-line authInput.
//
// Slice 193 built signupcard.go and its pure helpers (tested in
// signupcard_test.go) and parity row 44 marked the feature PRESENT —
// but authCard never had a SignUp case (git -S: the call site never
// existed), so signup fell through to the default branch: one generic
// line, no split, no photo, and the pre-193 "last names silently
// merged" bug stayed live. This test drives the REAL authCard dispatch
// through the real input router and clicks the Create-account band:
// RED before the wiring.

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

// TestSignupStepRendersDedicatedCard: pressing Create account with an
// empty first name must produce the card's OWN validation toast
// ("Enter your first name" — signupSubmit's wording, which the generic
// authInput can never say).
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

	// Frame 1 registers the handlers.
	a.authCard(gtx, f, st)
	r.Frame(&ops)

	// Sweep the Create-account band (the card stacks ~330dp of photo
	// circle + two labeled editors before the full-width button, so the
	// button sits ≈ y 310..346 inside the 18dp card inset). Bounded on
	// purpose: the generic authInput's own Continue button sits much
	// higher (~y 150), so a pre-patch sweep must NOT trip it into a
	// misleading toast — the assertion is the card's exact wording.
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
