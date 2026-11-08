package tests

import (
	"testing"

	. "uniclient/ui/app"
	"uniclient/ui/dialogs"
)

func toUpEntries(n int) []dialogs.Entry {
	rows := make([]dialogs.Entry, n)
	for i := range rows {
		rows[i] = dialogs.Entry{Name: "A", Date: "12:30"}
	}
	return rows
}

func toUpModel(t *testing.T, n int) Model {
	t.Helper()
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 400})
	m, _ = Update(m, DialogsLoaded{Rows: toUpEntries(n)})
	return m
}

func dialogsScrollTo(m Model, top, now int) Model {
	m, _ = Update(m, DialogsTick{Now: now})
	m, _ = Update(m, DialogsScrolled{DeltaY: top - m.DialogsScroll.Top})
	return m
}

func toUpShownAt(m Model) bool {
	return m.DialogsToUp.Shown
}

func TestDialogsToUpShowsOnScrollDown(t *testing.T) {
	m := toUpModel(t, 60)
	if m.Columns().Dialogs < 260 {
		t.Fatalf("test width: dialogs pane %d < 260, need wide pane", m.Columns().Dialogs)
	}
	m = dialogsScrollTo(m, 241, 1000)
	if !toUpShownAt(m) || !m.DialogsToUp.Anim || m.DialogsToUp.Progress != 0 {
		t.Fatalf("after scroll down 241: %+v, want shown animating from 0", m.DialogsToUp)
	}
	if !m.DialogsToUpActive() {
		t.Fatalf("DialogsToUpActive false while animating")
	}
}

func TestDialogsToUpAnimates(t *testing.T) {
	m := toUpModel(t, 60)
	m = dialogsScrollTo(m, 300, 1000)
	m, _ = Update(m, DialogsTick{Now: 1075})
	if m.DialogsToUp.Progress != 0.5 {
		t.Fatalf("mid progress = %v, want 0.5", m.DialogsToUp.Progress)
	}
	m, _ = Update(m, DialogsTick{Now: 1150})
	if m.DialogsToUp.Progress != 1 || m.DialogsToUp.Anim || m.DialogsToUpActive() {
		t.Fatalf("end: %+v, want progress 1 settled", m.DialogsToUp)
	}
	m = dialogsScrollTo(m, 0, 1200)
	m, _ = Update(m, DialogsTick{Now: 1350})
	if toUpShownAt(m) || m.DialogsToUp.Progress != 0 || m.DialogsToUp.Anim {
		t.Fatalf("after scroll back to top: %+v, want hidden settled", m.DialogsToUp)
	}
}

func TestDialogsToUpHiddenAtBottomAndTop(t *testing.T) {
	m := toUpModel(t, 60)
	max := m.Dialogs.MaxOffset(m.Columns().Dialogs, m.DialogsScroll.Height)
	if max <= 300 {
		t.Fatalf("test data too short: max = %d", max)
	}
	m = dialogsScrollTo(m, max, 1000)
	m, _ = Update(m, DialogsTick{Now: 1150})
	if toUpShownAt(m) {
		t.Fatalf("at bottom: shown, want hidden (top == max)")
	}
	m = dialogsScrollTo(m, 240, 1200)
	m, _ = Update(m, DialogsTick{Now: 1350})
	if toUpShownAt(m) {
		t.Fatalf("at 240: shown, want hidden (strict >)")
	}
}

func TestDialogsToUpNarrowPaneInstant(t *testing.T) {
	m, _ := Update(InitialModel(), Resized{Width: 250, Height: 400})
	m, _ = Update(m, DialogsLoaded{Rows: toUpEntries(60)})
	if m.Columns().Dialogs >= 260 {
		t.Fatalf("test width: dialogs pane %d >= 260, need narrow pane", m.Columns().Dialogs)
	}
	if m.Dialogs.MaxOffset(m.Columns().Dialogs, m.DialogsScroll.Height) <= 300 {
		t.Fatalf("test data too short at narrow width")
	}
	m = dialogsScrollTo(m, 300, 1000)
	if toUpShownAt(m) || m.DialogsToUp.Anim || m.DialogsToUp.Progress != 0 {
		t.Fatalf("narrow pane: %+v, want hidden with no animation", m.DialogsToUp)
	}
}

func TestDialogsToUpClickJumpsToTop(t *testing.T) {
	m := toUpModel(t, 60)
	m = dialogsScrollTo(m, 300, 1000)
	m, _ = Update(m, DialogsTick{Now: 1150})
	pane := m.Columns().Dialogs
	bx := pane - 12 - 26
	m, _ = Update(m, DialogsPressed{X: bx, Y: 360, Now: 1200})
	if m.Dialogs.Selected >= 0 {
		t.Fatalf("press on button selected row %d, want no selection", m.Dialogs.Selected)
	}
	m, _ = Update(m, DialogsReleased{X: bx, Y: 360, Now: 1210})
	if m.DialogsScroll.Top != 0 {
		t.Fatalf("after click top = %d, want 0", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsTick{Now: 1360})
	if toUpShownAt(m) {
		t.Fatalf("after click to top: shown, want hidden")
	}
}

func TestDialogsToUpReleaseOutsideCancels(t *testing.T) {
	m := toUpModel(t, 60)
	m = dialogsScrollTo(m, 300, 1000)
	m, _ = Update(m, DialogsTick{Now: 1150})
	pane := m.Columns().Dialogs
	bx := pane - 12 - 26
	m, _ = Update(m, DialogsPressed{X: bx, Y: 360, Now: 1200})
	m, _ = Update(m, DialogsDragged{X: bx - 60, Y: 300, Now: 1220})
	m, _ = Update(m, DialogsReleased{X: bx - 60, Y: 300, Now: 1230})
	if m.DialogsScroll.Top != 300 {
		t.Fatalf("outside release scrolled to %d, want 300", m.DialogsScroll.Top)
	}
}

func TestDialogsToUpTouchTapJumps(t *testing.T) {
	m := toUpModel(t, 60)
	m = dialogsScrollTo(m, 300, 1000)
	m, _ = Update(m, DialogsTick{Now: 1150})
	pane := m.Columns().Dialogs
	bx := pane - 12 - 26
	m, _ = Update(m, DialogsPressed{X: bx, Y: 360, Touch: true, Now: 1200})
	if m.DialogsTouch.Active {
		t.Fatalf("touch press on button started touch drag, want button press only")
	}
	m, _ = Update(m, DialogsReleased{X: bx, Y: 360, Now: 1240})
	if m.DialogsScroll.Top != 0 {
		t.Fatalf("touch tap top = %d, want 0", m.DialogsScroll.Top)
	}
}

func TestDialogsToUpTouchDragFromButtonDoesNotScroll(t *testing.T) {
	m := toUpModel(t, 60)
	m = dialogsScrollTo(m, 300, 1000)
	m, _ = Update(m, DialogsTick{Now: 1150})
	pane := m.Columns().Dialogs
	bx := pane - 12 - 26
	m, _ = Update(m, DialogsPressed{X: bx, Y: 360, Touch: true, Now: 1200})
	m, _ = Update(m, DialogsDragged{X: bx, Y: 160, Now: 1260})
	m, _ = Update(m, DialogsReleased{X: bx, Y: 160, Now: 1300})
	if m.DialogsScroll.Top != 300 {
		t.Fatalf("touch drag from button scrolled to %d, want 300 (button grabs)", m.DialogsScroll.Top)
	}
}

func TestDialogsToUpPaneProgress(t *testing.T) {
	m := toUpModel(t, 60)
	m = dialogsScrollTo(m, 300, 1000)
	m, _ = Update(m, DialogsTick{Now: 1075})
	if s := View(m); s.Dialogs.ToUpProgress != m.DialogsToUp.Progress {
		t.Fatalf("pane progress = %v, want %v", s.Dialogs.ToUpProgress, m.DialogsToUp.Progress)
	}
}
