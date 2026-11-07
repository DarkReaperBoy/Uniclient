package tests

import (
	"testing"

	. "uniclient/ui/app"
	"uniclient/ui/dialogs"
)

func scrolledModel(t *testing.T, w, h int, rows int) Model {
	t.Helper()
	m, _ := Update(InitialModel(), Resized{Width: w, Height: h})
	entries := make([]dialogs.Entry, rows)
	for i := range entries {
		entries[i] = dialogs.Entry{Name: "row"}
	}
	m, _ = Update(m, DialogsLoaded{Rows: entries})
	return m
}

func TestDialogsScrolledClampLaw(t *testing.T) {
	m := scrolledModel(t, 400, 300, 6)
	if m.DialogsScroll.Height != 300 || m.DialogsScroll.Top != 0 {
		t.Fatalf("viewport not initialized by resize/load: %+v", m.DialogsScroll)
	}
	m, _ = Update(m, DialogsScrolled{DeltaY: 5})
	if m.DialogsScroll.Top != 5 {
		t.Fatalf("scroll +5 = %d, want 5 (accumulate)", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsScrolled{DeltaY: 5})
	if m.DialogsScroll.Top != 10 {
		t.Fatalf("scroll +5+5 = %d, want 10", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsScrolled{DeltaY: 1000})
	if m.DialogsScroll.Top != 72 {
		t.Fatalf("scroll past end = %d, want 72 (max = 372 content - 300 view)",
			m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsScrolled{DeltaY: -20})
	if m.DialogsScroll.Top != 52 {
		t.Fatalf("scroll -20 from 72 = %d, want 52 (in-range pass-through)", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsScrolled{DeltaY: -1000})
	if m.DialogsScroll.Top != 0 {
		t.Fatalf("scroll above top = %d, want 0", m.DialogsScroll.Top)
	}
}

func TestDialogsScrolledReloadClamp(t *testing.T) {
	m := scrolledModel(t, 400, 300, 6)
	m, _ = Update(m, DialogsScrolled{DeltaY: 1000})
	if m.DialogsScroll.Top != 72 {
		t.Fatalf("setup: top = %d, want 72", m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsLoaded{Rows: []dialogs.Entry{{Name: "a"}, {Name: "b"}}})
	if m.DialogsScroll.Top != 0 {
		t.Fatalf("reload with shorter list: top = %d, want 0 (range clamps)",
			m.DialogsScroll.Top)
	}
	m, _ = Update(m, DialogsScrolled{DeltaY: 1000})
	if m.DialogsScroll.Top != 0 {
		t.Fatalf("124 content in 300 view: top = %d, want 0 (no scroll range)",
			m.DialogsScroll.Top)
	}
}

func TestResizedClampsDialogsScroll(t *testing.T) {
	m := scrolledModel(t, 400, 300, 6)
	m, _ = Update(m, DialogsScrolled{DeltaY: 1000})
	if m.DialogsScroll.Top != 72 {
		t.Fatalf("setup: top = %d, want 72", m.DialogsScroll.Top)
	}
	m, _ = Update(m, Resized{Width: 400, Height: 600})
	if m.DialogsScroll.Height != 600 {
		t.Fatalf("pane height not tracked: %d, want 600", m.DialogsScroll.Height)
	}
	if m.DialogsScroll.Top != 0 {
		t.Fatalf("taller view: top = %d, want 0 (range shrank to zero)", m.DialogsScroll.Top)
	}
}

func TestSceneDialogsPane(t *testing.T) {
	m := scrolledModel(t, 400, 300, 16)
	m, _ = Update(m, DialogsScrolled{DeltaY: 400})
	s := View(m)
	if s.Dialogs.Width != 400 {
		t.Fatalf("scene pane width = %d, want 400 (double-pane dialogs column)", s.Dialogs.Width)
	}
	if s.Dialogs.First != 6 || len(s.Dialogs.Rows) != 6 {
		t.Fatalf("scene pane at 400: first %d, %d rows — want 6, 6 (rows 6..11 in [400,700))",
			s.Dialogs.First, len(s.Dialogs.Rows))
	}
	if len(s.Dialogs.RowYs) != 6 || s.Dialogs.RowYs[0] != 372 || s.Dialogs.RowYs[5] != 682 {
		t.Fatalf("scene pane row ys = %v, want [372 ... 682] (absolute)", s.Dialogs.RowYs)
	}
	if s.Dialogs.Thumb.Hidden || s.Dialogs.Thumb.Y != 122 || s.Dialogs.Thumb.H != 88 {
		t.Fatalf("scene thumb at 400 = %+v, want (122, 88)", s.Dialogs.Thumb)
	}
	m, _ = Update(m, DialogRowPressed{Index: 6})
	s = View(m)
	if s.Dialogs.Selected != 6 {
		t.Fatalf("scene pane selected = %d, want 6", s.Dialogs.Selected)
	}
}

func TestSceneDialogsPaneHidden(t *testing.T) {
	m := scrolledModel(t, 400, 300, 4)
	s := View(m)
	if s.Dialogs.View.Top != 0 || s.Dialogs.View.Height != 300 {
		t.Fatalf("scene pane viewport = %+v, want echo of model", s.Dialogs.View)
	}
	if s.Dialogs.First != 0 || len(s.Dialogs.Rows) != 4 {
		t.Fatalf("scene pane full list visible: first %d, %d rows", s.Dialogs.First, len(s.Dialogs.Rows))
	}
	noDialogs := scrolledModel(t, 400, 300, 4)
	noDialogs.HasDialogs = false
	if s := View(noDialogs); s.Dialogs.Width != 0 || len(s.Dialogs.Rows) != 0 {
		t.Fatalf("no-dialogs model must yield an empty pane: %+v", s.Dialogs)
	}
}

func TestLoadMoreFiresPastPreloadLine(t *testing.T) {
	m := scrolledModel(t, 400, 300, 16)
	m, cmd := Update(m, DialogsScrolled{DeltaY: 91})
	if cmd != nil {
		t.Fatal("load-more fired at 91 (991 < 992 content — inside preload window)")
	}
	m, cmd = Update(m, DialogsScrolled{DeltaY: 1})
	if cmd == nil {
		t.Fatal("load-more did not fire at 92 (992 >= 992 — exactly at the line)")
	}
	if msg := cmd(); msg != (DialogsLoadMoreRequested{}) {
		t.Fatalf("load-more cmd returned %T, want DialogsLoadMoreRequested", msg)
	}
	m, _ = Update(m, Resized{Width: 400, Height: 200})
	if m.DialogsScroll.Height != 200 {
		t.Fatalf("resize height = %d, want 200", m.DialogsScroll.Height)
	}
	empty := scrolledModel(t, 400, 300, 0)
	_, cmd = Update(empty, DialogsLoaded{Rows: nil})
	if cmd == nil {
		t.Fatal("load-more must fire for an empty list (0 >= 0)")
	}
}

func TestDialogsLoadMoreRequestedNoOp(t *testing.T) {
	m := scrolledModel(t, 400, 300, 16)
	before := m
	after, cmd := Update(m, DialogsLoadMoreRequested{})
	if cmd != nil {
		t.Fatal("load-more echo must not chain another cmd")
	}
	if after.DialogsScroll != before.DialogsScroll || after.Dialogs.Selected != before.Dialogs.Selected {
		t.Fatal("load-more echo must not mutate the model")
	}
}
