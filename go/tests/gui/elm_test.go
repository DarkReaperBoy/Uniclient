package tests

import (
	"image/color"
	"testing"

	. "uniclient/ui/app"
	"uniclient/ui/material"
)

func TestInitialModelBootsRunning(t *testing.T) {
	m := InitialModel()
	if !m.Running {
		t.Fatal("boot model not running")
	}
	if m.Width != 0 || m.Height != 0 {
		t.Fatalf("boot model carries size: %dx%d", m.Width, m.Height)
	}
	if !m.HasDialogs {
		t.Fatal("boot model must assume dialogs (measured default shape)")
	}
	if m.ThirdPane {
		t.Fatal("third pane is on-demand, default off (measured)")
	}
}

func TestUpdateRecordsResized(t *testing.T) {
	m, cmd := Update(InitialModel(), Resized{Width: 1024, Height: 768})
	if m.Width != 1024 || m.Height != 768 {
		t.Fatalf("resize not recorded: %dx%d", m.Width, m.Height)
	}
	if cmd != nil {
		t.Fatal("resize must not emit a cmd")
	}
	if !m.Running {
		t.Fatal("resize must not stop the loop")
	}
	neg, _ := Update(m, Resized{Width: -5, Height: -7})
	if neg.Width != 0 || neg.Height != 0 {
		t.Fatalf("negative resize not clamped: %dx%d", neg.Width, neg.Height)
	}
}

func TestUpdateIsPure(t *testing.T) {
	msg := Resized{Width: 932, Height: 600}
	a, _ := Update(InitialModel(), msg)
	b, _ := Update(InitialModel(), msg)
	if a != b {
		t.Fatalf("update not pure: %+v vs %+v", a, b)
	}
	q1, _ := Update(a, Quit{})
	q2, _ := Update(a, Quit{})
	if q1 != q2 {
		t.Fatalf("quit update not pure: %+v vs %+v", q1, q2)
	}
}

func TestQuitStopsTheLoop(t *testing.T) {
	m, cmd := Update(InitialModel(), Quit{})
	if m.Running {
		t.Fatal("quit must stop the loop")
	}
	if cmd != nil {
		t.Fatal("quit must not emit a cmd")
	}
}

func TestPaneModeBoundaries(t *testing.T) {
	cases := []struct {
		width      int
		third      bool
		hasDialogs bool
		want       PaneMode
	}{
		{0, false, true, PaneSingle},
		{639, false, true, PaneSingle},
		{640, false, true, PaneDouble},
		{931, false, true, PaneDouble},
		{932, false, true, PaneDouble},
		{640, true, true, PaneDouble},
		{931, true, true, PaneDouble},
		{932, true, true, PaneTriple},
		{639, false, false, PaneDouble},
		{671, true, false, PaneDouble},
		{672, true, false, PaneTriple},
	}
	for _, c := range cases {
		m := InitialModel()
		m.Width = c.width
		m.ThirdPane = c.third
		m.HasDialogs = c.hasDialogs
		if got := m.PaneMode(); got != c.want {
			t.Fatalf("width %d third=%v hasDialogs=%v: pane mode %d, want %d",
				c.width, c.third, c.hasDialogs, got, c.want)
		}
	}
}

func TestColumnsSinglePane(t *testing.T) {
	m := InitialModel()
	m.Width = 500
	m.Height = 480
	c := m.Columns()
	if c.Dialogs != 500 || c.Chat != 500 || c.Third != 0 {
		t.Fatalf("single-pane columns wrong: %+v", c)
	}
}

func TestColumnsDoublePane(t *testing.T) {
	cases := []struct {
		width       int
		wantDialogs int
		wantChat    int
	}{
		{640, 260, 380},
		{700, 260, 440},
		{800, 286, 514},
		{932, 333, 599},
	}
	for _, c := range cases {
		m := InitialModel()
		m.Width = c.width
		got := m.Columns()
		if got.Dialogs != c.wantDialogs || got.Chat != c.wantChat || got.Third != 0 {
			t.Fatalf("width %d: columns %+v, want dialogs %d chat %d",
				c.width, got, c.wantDialogs, c.wantChat)
		}
		if got.Dialogs+got.Chat != c.width {
			t.Fatalf("width %d: panes do not partition the body", c.width)
		}
	}
}

func TestColumnsTriplePane(t *testing.T) {
	m := InitialModel()
	m.Width = 932
	m.ThirdPane = true
	c := m.Columns()
	if c.Dialogs != 260 || c.Chat != 380 || c.Third != 292 {
		t.Fatalf("width 932 third-on: columns %+v, want 260/380/292", c)
	}
	if c.Dialogs+c.Chat+c.Third != 932 {
		t.Fatal("three panes do not partition the body at 932")
	}
	m.Width = 1400
	c = m.Columns()
	if c.Dialogs != 500 || c.Chat != 608 || c.Third != 292 {
		t.Fatalf("width 1400 third-on: columns %+v, want 500/608/292", c)
	}
}

func TestColumnsWithoutDialogs(t *testing.T) {
	m := InitialModel()
	m.HasDialogs = false
	m.Width = 500
	c := m.Columns()
	if c.Dialogs != 0 || c.Chat != 500 {
		t.Fatalf("no-dialogs width 500: columns %+v, want 0/500", c)
	}
	m.Width = 1000
	m.ThirdPane = true
	c = m.Columns()
	if c.Dialogs != 0 || c.Chat != 708 || c.Third != 292 {
		t.Fatalf("no-dialogs width 1000 third-on: columns %+v, want 0/708/292", c)
	}
}

func TestViewBootsOnMaterialSurface(t *testing.T) {
	s := View(InitialModel())
	if s.Background != (color.NRGBA{R: 0xFE, G: 0xF7, B: 0xFF, A: 0xFF}) {
		t.Fatalf("boot scene background %v, want material surface light", s.Background)
	}
	if s.Background != material.SchemeFor(material.Light).Surface {
		t.Fatal("boot scene background must be the material light surface")
	}
}

func TestResizeJourneyThroughPaneModes(t *testing.T) {
	m := InitialModel()
	steps := []struct {
		w    int
		want PaneMode
	}{
		{380, PaneSingle},
		{640, PaneDouble},
		{931, PaneDouble},
		{932, PaneDouble},
	}
	for _, s := range steps {
		m, _ = Update(m, Resized{Width: s.w, Height: 600})
		if got := m.PaneMode(); got != s.want {
			t.Fatalf("after resize to %d: pane mode %d, want %d", s.w, got, s.want)
		}
	}
	m, _ = Update(m, Resized{Width: 933, Height: 600})
	if m.PaneMode() != PaneDouble {
		t.Fatal("third pane must stay off until requested")
	}
	m.ThirdPane = true
	if m.PaneMode() != PaneTriple {
		t.Fatal("third pane must engage at 933 once requested")
	}
	m, _ = Update(m, Quit{})
	if m.Running {
		t.Fatal("journey must end stopped")
	}
}
