package tests

import (
	"testing"

	. "uniclient/ui/app"
)

func TestDialogsWheelNotch(t *testing.T) {
	m := scrolledModel(t, 400, 300, 16)
	m, _ = Update(m, DialogsWheel{AngleY: -120})
	if m.DialogsScroll.Top != 60 {
		t.Fatalf("wheel notch = %d, want 60", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsWheel{AngleY: -120})
	if m.DialogsScroll.Top != 120 {
		t.Fatalf("wheel notch x2 = %d, want 120", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsWheel{AngleY: -120, Accelerate: true})
	if m.DialogsScroll.Top != 270 {
		t.Fatalf("accelerated notch = %d, want 270 (120 + 150)", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsWheel{AngleX: -120, AngleY: -120})
	if m.DialogsScroll.Top != 270 {
		t.Fatalf("cross-axis wheel = %d, want 270 (ignored)", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsWheel{AngleY: -1000})
	if m.DialogsScroll.Top != 692 {
		t.Fatalf("wheel past end = %d, want 692 (clamped)", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsWheel{AngleY: 2000})
	if m.DialogsScroll.Top != 0 {
		t.Fatalf("wheel above top = %d, want 0 (clamped)", m.DialogsScroll.Top)
	}
}

func TestDialogsWheelLoadMore(t *testing.T) {
	m := scrolledModel(t, 400, 300, 16)
	m, cmd := Update(m, DialogsWheel{AngleY: -120})
	if cmd != nil {
		t.Fatal("load-more at 60 must not fire (960 < 992)")
	}
	m, cmd = Update(m, DialogsWheel{AngleY: -120})
	if cmd == nil {
		t.Fatal("load-more at 120 must fire (1020 >= 992)")
	}
}

func TestDialogsTrackpadScroll(t *testing.T) {
	m := scrolledModel(t, 400, 300, 16)
	m, _ = Update(m, DialogsTrackpadScrolled{PixelY: -40})
	if m.DialogsScroll.Top != 40 {
		t.Fatalf("trackpad dy = %d, want 40", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsTrackpadScrolled{PixelY: -40, Accelerate: true})
	if m.DialogsScroll.Top != 140 {
		t.Fatalf("trackpad accel = %d, want 140 (40 + 100)", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsTrackpadScrolled{PixelX: -50, PixelY: -40})
	if m.DialogsScroll.Top != 140 {
		t.Fatalf("trackpad cross-axis = %d, want 140 (ignored)", m.DialogsScroll.Top)
	}
}

func TestDialogsPressedMouseSelects(t *testing.T) {
	m := scrolledModel(t, 400, 300, 16)
	m, _ = Update(m, DialogsPressed{X: 10, Y: 125})
	if m.Dialogs.Selected != 2 {
		t.Fatalf("press y=125 = %d, want row 2", m.Dialogs.Selected)
	}
	m, _ = Update(m, DialogsPressed{X: 10, Y: 0})
	if m.Dialogs.Selected != 0 {
		t.Fatalf("press y=0 = %d, want row 0", m.Dialogs.Selected)
	}
	short := scrolledModel(t, 400, 300, 2)
	short, _ = Update(short, DialogsPressed{X: 10, Y: 200})
	if short.Dialogs.Selected != -1 {
		t.Fatalf("press below 2 rows = %d, want -1", short.Dialogs.Selected)
	}
	scrolled := scrolledModel(t, 400, 300, 16)
	scrolled, _ = Update(scrolled, DialogsScrolled{DeltaY: 124})
	scrolled, _ = Update(scrolled, DialogsPressed{X: 10, Y: 0})
	if scrolled.Dialogs.Selected != 2 {
		t.Fatalf("press at scrolled top = %d, want row 2 (hit-test adds viewport offset)",
			scrolled.Dialogs.Selected)
	}
}

func TestDialogsPressedBarJumpAndDrag(t *testing.T) {
	m := scrolledModel(t, 400, 300, 16)
	m, _ = Update(m, DialogsScrolled{DeltaY: 400})
	m, _ = Update(m, DialogsPressed{X: 398, Y: 150})
	if m.DialogsScroll.Top != 346 {
		t.Fatalf("track press off thumb = %d, want 346 (jump to middle)", m.DialogsScroll.Top)
	}
	if !m.DialogsBar.Dragging || m.DialogsBar.LastY != 150 {
		t.Fatalf("bar drag state = %+v, want dragging from 150", m.DialogsBar)
	}
	m, _ = Update(m, DialogsDragged{X: 398, Y: 160})
	if m.DialogsScroll.Top != 379 {
		t.Fatalf("drag +10 = %d, want 379 (346 + 33)", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsDragged{X: 398, Y: 170})
	if m.DialogsScroll.Top != 412 {
		t.Fatalf("drag +10 = %d, want 412", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsDragged{X: 398, Y: 270})
	if m.DialogsScroll.Top != 692 {
		t.Fatalf("drag past end = %d, want 692 (clamped)", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsReleased{X: 398, Y: 270})
	if m.DialogsBar.Dragging {
		t.Fatal("release must clear bar drag")
	}
	m, _ = Update(m, DialogsDragged{X: 398, Y: 280})
	if m.DialogsScroll.Top != 692 {
		t.Fatalf("drag after release = %d, want 692 (no-op)", m.DialogsScroll.Top)
	}
}

func TestDialogsPressedBarOnThumb(t *testing.T) {
	m := scrolledModel(t, 400, 300, 16)
	m, _ = Update(m, DialogsScrolled{DeltaY: 400})
	m, _ = Update(m, DialogsPressed{X: 393, Y: 150})
	if m.DialogsScroll.Top != 400 {
		t.Fatalf("press on thumb = %d, want 400 (no jump)", m.DialogsScroll.Top)
	}
	if !m.DialogsBar.Dragging {
		t.Fatal("press on thumb must still start the drag")
	}
	m, _ = Update(m, DialogsDragged{X: 393, Y: 160})
	if m.DialogsScroll.Top != 433 {
		t.Fatalf("thumb drag +10 = %d, want 433 (400 + 33)", m.DialogsScroll.Top)
	}
}

func TestDialogsPressedBarHidden(t *testing.T) {
	m := scrolledModel(t, 400, 300, 4)
	m, _ = Update(m, DialogsPressed{X: 395, Y: 100})
	if m.DialogsScroll.Top != 0 || m.DialogsBar.Dragging {
		t.Fatalf("press on hidden bar = top %d dragging %v, want 0 false", m.DialogsScroll.Top, m.DialogsBar.Dragging)
	}
	m, _ = Update(m, DialogsDragged{X: 395, Y: 150})
	m, _ = Update(m, DialogsReleased{X: 395, Y: 150})
	if m.DialogsScroll.Top != 0 {
		t.Fatalf("hidden bar interaction = %d, want 0", m.DialogsScroll.Top)
	}
}

func TestDialogsTouchTapSelects(t *testing.T) {
	m := scrolledModel(t, 400, 300, 16)
	m, _ = Update(m, DialogsPressed{X: 10, Y: 125, Touch: true})
	if m.Dialogs.Selected != -1 {
		t.Fatalf("touch press must not select yet, got %d", m.Dialogs.Selected)
	}
	if !m.DialogsTouch.Active {
		t.Fatal("touch press must record the drag anchor")
	}
	m, _ = Update(m, DialogsDragged{X: 13, Y: 128})
	m, _ = Update(m, DialogsReleased{X: 10, Y: 125})
	if m.Dialogs.Selected != 2 {
		t.Fatalf("tap release = %d, want row 2", m.Dialogs.Selected)
	}
	if m.DialogsTouch.Active {
		t.Fatal("release must clear touch state")
	}
}

func TestDialogsTouchDragScrolls(t *testing.T) {
	m := scrolledModel(t, 400, 300, 16)
	m, _ = Update(m, DialogsPressed{X: 200, Y: 100, Touch: true})
	m, _ = Update(m, DialogsDragged{X: 200, Y: 90})
	if m.DialogsScroll.Top != 0 {
		t.Fatalf("finger up 10 = %d, want 0 (threshold crossed, arm swallows the delta)",
			m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsDragged{X: 200, Y: 70})
	if m.DialogsScroll.Top != 20 {
		t.Fatalf("finger up 20 more = %d, want 20", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsReleased{X: 200, Y: 70})
	if m.Dialogs.Selected != -1 {
		t.Fatalf("release after scroll = %d, want -1 (no tap)", m.Dialogs.Selected)
	}
	if m.DialogsTouch.Active {
		t.Fatal("release must clear touch state")
	}
}

func TestDialogsTouchDragBelowThreshold(t *testing.T) {
	m := scrolledModel(t, 400, 300, 16)
	m, _ = Update(m, DialogsPressed{X: 200, Y: 100, Touch: true})
	m, _ = Update(m, DialogsDragged{X: 204, Y: 103})
	if m.DialogsScroll.Top != 0 {
		t.Fatalf("manhattan 7 = %d, want 0 (below threshold)", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsDragged{X: 204, Y: 104})
	if m.DialogsScroll.Top != 0 {
		t.Fatalf("manhattan 8 = %d, want 0 (below threshold)", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsReleased{X: 204, Y: 104})
	if m.Dialogs.Selected != 1 {
		t.Fatalf("tap at release position = %d, want row 1", m.Dialogs.Selected)
	}
}

func TestDialogsPressCanceled(t *testing.T) {
	m := scrolledModel(t, 400, 300, 16)
	m, _ = Update(m, DialogsScrolled{DeltaY: 400})
	m, _ = Update(m, DialogsPressed{X: 398, Y: 150})
	if !m.DialogsBar.Dragging {
		t.Fatal("setup: bar must be dragging")
	}
	m, _ = Update(m, DialogsDragged{X: 398, Y: 160})
	if m.DialogsScroll.Top != 379 {
		t.Fatalf("setup: top = %d, want 379", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsPressCanceled{})
	if m.DialogsBar.Dragging || m.DialogsTouch.Active {
		t.Fatal("cancel must clear interaction state")
	}
	m, _ = Update(m, DialogsDragged{X: 398, Y: 170})
	if m.DialogsScroll.Top != 379 {
		t.Fatalf("drag after cancel = %d, want 379 (no-op)", m.DialogsScroll.Top)
	}
}
