package tests

import (
	"testing"

	. "uniclient/ui/app"
	"uniclient/ui/dialogs/render"
	"uniclient/ui/material"
)

func toUpShownModel(t *testing.T) Model {
	t.Helper()
	m := toUpModel(t, 60)
	m = dialogsScrollTo(m, 300, 1000)
	m, _ = Update(m, DialogsTick{Now: 1150})
	if m.DialogsToUp.Progress != 1 {
		t.Fatalf("setup: to-up progress = %v, want 1", m.DialogsToUp.Progress)
	}
	return m
}

func toUpPressPoint(m Model) (int, int) {
	pane := m.Columns().Dialogs
	return pane - 12 - 26, 306
}

func TestDialogsToUpHoverFollowsPointer(t *testing.T) {
	m := toUpShownModel(t)
	if s := View(m); s.Dialogs.ToUpHover {
		t.Fatalf("hover before any move: %v", s.Dialogs.ToUpHover)
	}
	bx, by := toUpPressPoint(m)
	m, _ = Update(m, DialogsDragged{X: bx, Y: by, Now: 1400})
	if s := View(m); !s.Dialogs.ToUpHover {
		t.Fatalf("mouse over the to-up button must hover")
	}
	m, _ = Update(m, DialogsDragged{X: 40, Y: 100, Now: 1410})
	if s := View(m); s.Dialogs.ToUpHover {
		t.Fatalf("hover must clear when the pointer leaves the button")
	}
}

func TestDialogsToUpHoverIgnoresTouch(t *testing.T) {
	m := toUpShownModel(t)
	bx, by := toUpPressPoint(m)
	m, _ = Update(m, DialogsDragged{X: bx, Y: by, Touch: true, Now: 1400})
	if s := View(m); s.Dialogs.ToUpHover {
		t.Fatalf("touch move must not hover the button")
	}
}

func TestDialogsLeaveClearsHover(t *testing.T) {
	m := toUpShownModel(t)
	bx, by := toUpPressPoint(m)
	m, _ = Update(m, DialogsDragged{X: bx, Y: by, Now: 1400})
	if s := View(m); !s.Dialogs.ToUpHover {
		t.Fatalf("setup: hover must be set over the button")
	}
	m, _ = Update(m, DialogsLeft{})
	if s := View(m); s.Dialogs.ToUpHover {
		t.Fatalf("leaving the dialogs pane must clear hover")
	}
}

func TestDialogsToUpRipplePressFadesOnRelease(t *testing.T) {
	m := toUpShownModel(t)
	bx, by := toUpPressPoint(m)
	m, _ = Update(m, DialogsPressed{X: bx, Y: by, Now: 1500})
	s := View(m)
	if s.Dialogs.ToUpRipple.OriginX != 21 || s.Dialogs.ToUpRipple.OriginY != 9 {
		t.Fatalf("ripple origin = %d,%d, want 21,9 (press point relative to the circle)",
			s.Dialogs.ToUpRipple.OriginX, s.Dialogs.ToUpRipple.OriginY)
	}
	if s.Dialogs.ToUpRipple.Alpha != 1 || s.Dialogs.ToUpRipple.Radius != 0 {
		t.Fatalf("ripple at press: %+v, want radius 0 alpha 1", s.Dialogs.ToUpRipple)
	}
	if !m.DialogsRippleActive() {
		t.Fatalf("the ripple must drive the dialogs tick clock")
	}
	m, _ = Update(m, DialogsTick{Now: 1825})
	s = View(m)
	if s.Dialogs.ToUpRipple.Radius <= 0 {
		t.Fatalf("mid-show radius must be positive, got %d", s.Dialogs.ToUpRipple.Radius)
	}
	m, _ = Update(m, DialogsReleased{X: bx, Y: by, Now: 1900})
	m, _ = Update(m, DialogsTick{Now: 2000})
	s = View(m)
	if s.Dialogs.ToUpRipple.Alpha <= 0 || s.Dialogs.ToUpRipple.Alpha >= 1 {
		t.Fatalf("mid-fade alpha = %v, want strictly between 0 and 1", s.Dialogs.ToUpRipple.Alpha)
	}
	m, _ = Update(m, DialogsTick{Now: 2100})
	if m.DialogsRippleActive() {
		t.Fatalf("the ripple must clear after the fade completes")
	}
	if s = View(m); s.Dialogs.ToUpRipple.Radius != 0 || s.Dialogs.ToUpRipple.Alpha != 0 {
		t.Fatalf("cleared ripple projection: %+v, want zero", s.Dialogs.ToUpRipple)
	}
}

func TestDialogsToUpRippleReleaseOutsideStillFades(t *testing.T) {
	m := toUpShownModel(t)
	bx, by := toUpPressPoint(m)
	m, _ = Update(m, DialogsPressed{X: bx, Y: by, Now: 1500})
	m, _ = Update(m, DialogsReleased{X: 40, Y: 100, Now: 1600})
	if m.DialogsScroll.Top != 300 {
		t.Fatalf("release outside the button moved top to %d, want 300", m.DialogsScroll.Top)
	}
	if !m.DialogsRippleActive() {
		t.Fatalf("a release outside the button must still fade the ripple, not clear it")
	}
	m, _ = Update(m, DialogsTick{Now: 1800})
	if m.DialogsRippleActive() {
		t.Fatalf("the ripple must be gone after the fade completes")
	}
}

func TestDialogsToUpRippleCancelClears(t *testing.T) {
	m := toUpShownModel(t)
	bx, by := toUpPressPoint(m)
	m, _ = Update(m, DialogsPressed{X: bx, Y: by, Now: 1500})
	m, _ = Update(m, DialogsPressCanceled{})
	if m.DialogsRippleActive() {
		t.Fatalf("cancel must clear the ripple instantly (clearState law)")
	}
}

func TestDialogsToUpRippleIgnoresPressOutsideButton(t *testing.T) {
	m := toUpShownModel(t)
	m, _ = Update(m, DialogsPressed{X: 40, Y: 100, Now: 1500})
	if m.DialogsRippleActive() {
		t.Fatalf("press on a row must not start a ripple")
	}
}

func TestDialogsToUpHoverRipplePaintJourney(t *testing.T) {
	m := toUpShownModel(t)
	bx, by := toUpPressPoint(m)
	m, _ = Update(m, DialogsDragged{X: bx, Y: by, Now: 1400})
	m, _ = Update(m, DialogsPressed{X: bx, Y: by, Now: 1500})
	m, _ = Update(m, DialogsTick{Now: 1825})
	scene := View(m)
	if !scene.Dialogs.ToUpHover || scene.Dialogs.ToUpRipple.Radius <= 0 {
		t.Fatalf("setup: hover=%v ripple radius=%d, want hover and a growing ripple",
			scene.Dialogs.ToUpHover, scene.Dialogs.ToUpRipple.Radius)
	}
	p := render.NewPainter()
	gtx := renderContext()
	p.PaintPane(gtx, scene.Dialogs, material.SchemeFor(material.Light))
}
