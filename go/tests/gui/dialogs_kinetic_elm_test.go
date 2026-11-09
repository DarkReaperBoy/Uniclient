package tests

import (
	"testing"

	. "uniclient/ui/app"
)

func TestDialogsTouchDragRubberBand(t *testing.T) {
	m := scrolledModel(t, 400, 300, 16)
	m, _ = Update(m, DialogsPressed{X: 200, Y: 100, Touch: true, Now: 1000})
	m, _ = Update(m, DialogsDragged{X: 200, Y: 90, Now: 1010})
	if m.DialogsScroll.Top != 0 {
		t.Fatalf("arm event = %d, want 0 (crossing delta swallowed)", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsDragged{X: 200, Y: 70, Now: 1020})
	if m.DialogsScroll.Top != 20 {
		t.Fatalf("follow 1 = %d, want 20", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsDragged{X: 200, Y: 30, Now: 1030})
	if m.DialogsScroll.Top != 60 {
		t.Fatalf("follow 2 = %d, want 60", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsDragged{X: 200, Y: -200, Now: 1040})
	if m.DialogsScroll.Top != 290 {
		t.Fatalf("in-range move = %d, want 290", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsDragged{X: 200, Y: -700, Now: 1050})
	if m.DialogsScroll.Top != 750 || m.DialogsOverscroll.Stretch != 4 || m.DialogsOverscroll.Accumulated != 88 {
		t.Fatalf("past edge = %d stretch %d acc %d, want 750/4/88 (44 leftover *2 /20)",
			m.DialogsScroll.Top, m.DialogsOverscroll.Stretch, m.DialogsOverscroll.Accumulated)
	}
	m, _ = Update(m, DialogsDragged{X: 200, Y: -800, Now: 1060})
	if m.DialogsScroll.Top != 760 || m.DialogsOverscroll.Stretch != 14 {
		t.Fatalf("deeper = %d stretch %d, want 760/14", m.DialogsScroll.Top, m.DialogsOverscroll.Stretch)
	}
	m, _ = Update(m, DialogsReleased{X: 200, Y: -800, Now: 1070})
	if m.DialogsTouch.Active || m.DialogsTouch.State == 0 {
		t.Fatalf("release = active %v state %d, want false/auto", m.DialogsTouch.Active, m.DialogsTouch.State)
	}
	m, _ = Update(m, DialogsTick{Now: 1085})
	if m.DialogsScroll.Top != 764 {
		t.Fatalf("fling feeds bounce = %d, want 764 (stretch 18)", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsTick{Now: 1100})
	if m.DialogsScroll.Top != 763 {
		t.Fatalf("spring claw = %d, want 763 (stretch 17)", m.DialogsScroll.Top)
	}
	for i := 0; i < 400 && m.KineticActive(); i++ {
		m, _ = Update(m, DialogsTick{Now: 1115 + 15*i})
	}
	if m.KineticActive() || m.DialogsOverscroll.Stretch != 0 || m.DialogsOverscroll.Returning {
		t.Fatalf("converged = active %v stretch %d returning %v", m.KineticActive(), m.DialogsOverscroll.Stretch, m.DialogsOverscroll.Returning)
	}
	if m.DialogsScroll.Top < 0 || m.DialogsScroll.Top > 746 {
		t.Fatalf("settled top = %d, want within [0,746]", m.DialogsScroll.Top)
	}
}

func TestDialogsTouchFlingInList(t *testing.T) {
	m := scrolledModel(t, 400, 300, 16)
	m, _ = Update(m, DialogsPressed{X: 200, Y: 100, Touch: true, Now: 1000})
	m, _ = Update(m, DialogsDragged{X: 200, Y: 90, Now: 1010})
	m, _ = Update(m, DialogsDragged{X: 200, Y: 70, Now: 1020})
	m, _ = Update(m, DialogsDragged{X: 200, Y: 50, Now: 1030})
	if m.DialogsScroll.Top != 40 {
		t.Fatalf("setup top = %d, want 40", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsReleased{X: 200, Y: 50, Now: 1040})
	m, _ = Update(m, DialogsTick{Now: 1055})
	if m.DialogsScroll.Top != 70 {
		t.Fatalf("fling tick 1 = %d, want 70 (-30 content)", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsTick{Now: 1070})
	if m.DialogsScroll.Top != 100 {
		t.Fatalf("fling tick 2 = %d, want 100 (-30 qRound: -1985*15/1000 = -29.775)", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsTick{Now: 1085})
	if m.DialogsScroll.Top != 130 {
		t.Fatalf("fling tick 3 = %d, want 130 (-29.55 rounds to -30)", m.DialogsScroll.Top)
	}
	for i := 0; i < 600 && m.KineticActive(); i++ {
		m, _ = Update(m, DialogsTick{Now: 1100 + 15*i})
	}
	if m.KineticActive() {
		t.Fatal("fling must converge")
	}
	if m.DialogsTouch.State != 0 || m.DialogsTouch.Scrolling {
		t.Fatalf("fling end state = %d scrolling %v, want manual/false", m.DialogsTouch.State, m.DialogsTouch.Scrolling)
	}
	if m.DialogsScroll.Top != 746 {
		t.Fatalf("settled top = %d, want 746 (fling reached bottom, bounce retracted)", m.DialogsScroll.Top)
	}
}

func TestDialogsTouchFlingStopByTouch(t *testing.T) {
	m := scrolledModel(t, 400, 300, 16)
	m, _ = Update(m, DialogsPressed{X: 200, Y: 100, Touch: true, Now: 1000})
	m, _ = Update(m, DialogsDragged{X: 200, Y: 90, Now: 1010})
	m, _ = Update(m, DialogsDragged{X: 200, Y: 70, Now: 1020})
	m, _ = Update(m, DialogsDragged{X: 200, Y: 50, Now: 1030})
	m, _ = Update(m, DialogsReleased{X: 200, Y: 50, Now: 1040})
	m, _ = Update(m, DialogsTick{Now: 1055})
	m, _ = Update(m, DialogsPressed{X: 200, Y: 200, Touch: true, Now: 1060})
	if m.DialogsTouch.State != 2 {
		t.Fatalf("press during fling = state %d, want acceleration (2)", m.DialogsTouch.State)
	}
	if !m.DialogsTouch.WaitingAcceleration {
		t.Fatal("press during fling must wait for the acceleration decision")
	}
	m, _ = Update(m, DialogsTick{Now: 1075})
	if m.DialogsScroll.Top != 110 {
		t.Fatalf("acceleration tick 1 = %d, want 110 (fling continues under finger, -39.7 rounds to -40)", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsTick{Now: 1090})
	if m.DialogsScroll.Top != 139 {
		t.Fatalf("acceleration tick 2 = %d, want 139 (-29.475 rounds to -29)", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsTick{Now: 1105})
	if m.DialogsTouch.State != 0 {
		t.Fatalf("40ms still = state %d, want manual (0)", m.DialogsTouch.State)
	}
	if m.DialogsScroll.Top != 139 {
		t.Fatalf("timeout top = %d, want 139", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsDragged{X: 200, Y: 130, Now: 1115})
	if m.DialogsScroll.Top != 209 {
		t.Fatalf("manual resume = %d, want 209 (139 + 70)", m.DialogsScroll.Top)
	}
}

func TestDialogsTouchReflingDuringAcceleration(t *testing.T) {
	m := scrolledModel(t, 400, 300, 16)
	m, _ = Update(m, DialogsPressed{X: 200, Y: 100, Touch: true, Now: 1000})
	m, _ = Update(m, DialogsDragged{X: 200, Y: 90, Now: 1010})
	m, _ = Update(m, DialogsDragged{X: 200, Y: 70, Now: 1020})
	m, _ = Update(m, DialogsDragged{X: 200, Y: 50, Now: 1030})
	m, _ = Update(m, DialogsReleased{X: 200, Y: 50, Now: 1040})
	m, _ = Update(m, DialogsTick{Now: 1055})
	m, _ = Update(m, DialogsPressed{X: 200, Y: 200, Touch: true, Now: 1060})
	m, _ = Update(m, DialogsDragged{X: 200, Y: 190, Now: 1070})
	if m.DialogsScroll.Top != 70 {
		t.Fatalf("acceleration move = %d, want 70 (no scroll while accelerating)", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsReleased{X: 200, Y: 190, Now: 1080})
	if m.DialogsTouch.State != 1 || m.DialogsTouch.WaitingAcceleration {
		t.Fatalf("re-release = state %d waiting %v, want auto (1) false", m.DialogsTouch.State, m.DialogsTouch.WaitingAcceleration)
	}
	m, _ = Update(m, DialogsTick{Now: 1095})
	if m.DialogsScroll.Top != 120 {
		t.Fatalf("re-fling = %d, want 120 (-49.84 rounds to -50 at manual-blend speed -1246)", m.DialogsScroll.Top)
	}
}

func TestDialogsWheelDuringOverscrollReturns(t *testing.T) {
	m := scrolledModel(t, 400, 300, 16)
	m, _ = Update(m, DialogsPressed{X: 200, Y: 100, Touch: true, Now: 1000})
	m, _ = Update(m, DialogsDragged{X: 200, Y: 90, Now: 1100})
	m, _ = Update(m, DialogsDragged{X: 200, Y: -700, Now: 1400})
	if m.DialogsScroll.Top != 750 || m.DialogsOverscroll.Stretch != 4 {
		t.Fatalf("setup = %d stretch %d, want 750/4", m.DialogsScroll.Top, m.DialogsOverscroll.Stretch)
	}
	m, _ = Update(m, DialogsWheel{AngleY: -120, Now: 1500})
	if m.DialogsScroll.Top != 750 {
		t.Fatalf("wheel during stretch = %d, want 750 (no scroll, only return)", m.DialogsScroll.Top)
	}
	if !m.DialogsOverscroll.Returning {
		t.Fatal("wheel during stretch must start the return spring")
	}
	m, _ = Update(m, DialogsTick{Now: 1515})
	if m.DialogsScroll.Top != 749 {
		t.Fatalf("return 15ms = %d, want 749 (stretch 3)", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsTick{Now: 1600})
	if m.DialogsScroll.Top != 747 {
		t.Fatalf("return 100ms = %d, want 747 (stretch 1)", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsTick{Now: 1700})
	if m.DialogsScroll.Top != 746 {
		t.Fatalf("return 200ms = %d, want 746 (stretch 0)", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsTick{Now: 1800})
	if m.DialogsScroll.Top != 746 || m.DialogsOverscroll.Stretch != 0 || m.KineticActive() {
		t.Fatalf("return 300ms = %d stretch %d active %v, want 746/0/false", m.DialogsScroll.Top, m.DialogsOverscroll.Stretch, m.KineticActive())
	}
}

func TestDialogsBarTouchPressDragsList(t *testing.T) {
	m := scrolledModel(t, 400, 300, 16)
	m, _ = Update(m, DialogsPressed{X: 398, Y: 150, Touch: true, Now: 1000})
	if m.DialogsBar.Dragging {
		t.Fatal("touch press on bar strip must not grab the bar (touch routes to the list)")
	}
	if !m.DialogsTouch.Active {
		t.Fatal("touch press on bar strip must start a list drag")
	}
	m, _ = Update(m, DialogsDragged{X: 398, Y: 130, Now: 1010})
	if m.DialogsScroll.Top != 0 {
		t.Fatalf("arm = %d, want 0", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsDragged{X: 398, Y: 110, Now: 1020})
	if m.DialogsScroll.Top != 20 {
		t.Fatalf("list drag = %d, want 20", m.DialogsScroll.Top)
	}
}

func TestDialogsTouchCancelFreezesStretch(t *testing.T) {
	m := scrolledModel(t, 400, 300, 16)
	m, _ = Update(m, DialogsPressed{X: 200, Y: 100, Touch: true, Now: 1000})
	m, _ = Update(m, DialogsDragged{X: 200, Y: 90, Now: 1010})
	m, _ = Update(m, DialogsDragged{X: 200, Y: -890, Now: 1020})
	if m.DialogsOverscroll.Stretch != 23 {
		t.Fatalf("setup stretch = %d, want 29", m.DialogsOverscroll.Stretch)
	}
	m, _ = Update(m, DialogsPressCanceled{})
	if m.DialogsTouch.Active || m.DialogsTouch.State != 0 {
		t.Fatalf("cancel = active %v state %d, want false/0", m.DialogsTouch.Active, m.DialogsTouch.State)
	}
	m, _ = Update(m, DialogsTick{Now: 1030})
	if m.DialogsOverscroll.Stretch != 23 {
		t.Fatalf("stretch after cancel = %d, want 23 (frozen, no spring)", m.DialogsOverscroll.Stretch)
	}
	m, _ = Update(m, DialogsDragged{X: 200, Y: -900, Now: 1040})
	if m.DialogsOverscroll.Stretch != 23 {
		t.Fatalf("stretch after stray drag = %d, want 23 (no touch active)", m.DialogsOverscroll.Stretch)
	}
	m, _ = Update(m, DialogsWheel{AngleY: 120, Now: 1050})
	if !m.DialogsOverscroll.Returning || m.DialogsOverscroll.Stretch != 23 {
		t.Fatalf("wheel after cancel = returning %v stretch %d, want true/23", m.DialogsOverscroll.Returning, m.DialogsOverscroll.Stretch)
	}
}
