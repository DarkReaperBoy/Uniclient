package tests

import (
	"testing"

	. "uniclient/ui/app"
	"uniclient/ui/dialogs"
	"uniclient/ui/dialogs/render"
	"uniclient/ui/material"
	"uniclient/ui/tokens"
)

func headerModel(t *testing.T, w, h int) Model {
	t.Helper()
	m, _ := Update(InitialModel(), Resized{Width: w, Height: h})
	return m
}

func TestDialogsHeaderGeometry(t *testing.T) {
	m := headerModel(t, 1440, 900)
	paneW := m.Columns().Dialogs
	if paneW <= 0 {
		t.Fatalf("dialogs pane width = %d", paneW)
	}
	hd := View(m).Dialogs.Header
	if hd.Band != (dialogs.Rect{X: 0, Y: 0, W: paneW, H: tokens.TopBarHeight}) {
		t.Fatalf("band = %+v, want {0 0 %d %d}", hd.Band, paneW, tokens.TopBarHeight)
	}
	wantField := dialogs.Rect{
		X: tokens.DialogsFilterLeftWithMenu,
		Y: (tokens.TopBarHeight - tokens.DialogsFilterHeight) / 2,
		W: paneW - tokens.DialogsFilterLeftWithMenu - (tokens.DialogsFilterSkip + tokens.DialogsFilterPadX),
		H: tokens.DialogsFilterHeight,
	}
	if hd.Field != wantField {
		t.Fatalf("field = %+v, want %+v", hd.Field, wantField)
	}
	if wantField.H != 35 || wantField.X != 54 || wantField.Y != 9 {
		t.Fatalf("measured geometry drifted: %+v", wantField)
	}
	wantToggle := dialogs.Rect{
		X: tokens.MainMenuToggleX,
		Y: tokens.MainMenuToggleY,
		W: tokens.MainMenuToggleSize,
		H: tokens.MainMenuToggleSize,
	}
	if hd.Toggle != wantToggle {
		t.Fatalf("toggle = %+v, want %+v", hd.Toggle, wantToggle)
	}
	if wantToggle.X != 7 || wantToggle.Y != 7 || wantToggle.W != 40 || wantToggle.H != 40 {
		t.Fatalf("measured toggle geometry drifted: %+v", wantToggle)
	}
}

func TestDialogsHeaderGeometrySinglePane(t *testing.T) {
	m := headerModel(t, 390, 844)
	hd := View(m).Dialogs.Header
	if hd.Band.W != 390 || hd.Field.W != 390-65 {
		t.Fatalf("single pane: band %+v field %+v", hd.Band, hd.Field)
	}
}

func TestDialogsScrollHeightBelowHeader(t *testing.T) {
	m := headerModel(t, 400, 600)
	if m.DialogsScroll.Height != 600-tokens.TopBarHeight {
		t.Fatalf("scroll height = %d, want %d", m.DialogsScroll.Height, 600-tokens.TopBarHeight)
	}
	tiny, _ := Update(InitialModel(), Resized{Width: 400, Height: 10})
	if tiny.DialogsScroll.Height < 0 {
		t.Fatalf("negative scroll height %d", tiny.DialogsScroll.Height)
	}
}

func TestDialogsHeaderPressFocusesField(t *testing.T) {
	m := headerModel(t, 1440, 900)
	field := View(m).Dialogs.Header.Field
	m, _ = Update(m, DialogsHeaderPressed{X: field.X + 4, Y: field.Y + 10, Now: 1000})
	if !m.Search.Focused || !m.Search.CursorOn {
		t.Fatalf("after field press: %+v, want focused lit", m.Search)
	}
	if m.Search.NextBlinkAt != 1000+tokens.CursorFlashTimeMs/2 {
		t.Fatalf("blink deadline = %d, want %d", m.Search.NextBlinkAt, 1000+tokens.CursorFlashTimeMs/2)
	}
	m, _ = Update(m, DialogsHeaderPressed{X: field.X + 8, Y: field.Y + 12, Now: 1100})
	if !m.Search.Focused {
		t.Fatalf("second field press lost focus")
	}
	m, _ = Update(m, DialogsHeaderPressed{X: 2, Y: 2, Now: 1200})
	if m.Search.Focused || m.Search.CursorOn {
		t.Fatalf("band press outside field kept focus: %+v", m.Search)
	}
	m, _ = Update(m, DialogsHeaderPressed{X: field.X + 4, Y: field.Y + 10, Now: 1300})
	m, _ = Update(m, DialogsPressed{X: 10, Y: 100, Now: 1400})
	if m.Search.Focused || m.Search.CursorOn {
		t.Fatalf("list press kept search focus: %+v", m.Search)
	}
}

func TestDialogsHeaderPressLeavesListUntouched(t *testing.T) {
	m := headerModel(t, 800, 600)
	m, _ = Update(m, DialogsLoaded{Rows: toUpEntries(3)})
	m, _ = Update(m, DialogRowPressed{Index: 1})
	if m.Dialogs.Selected != 1 {
		t.Fatalf("setup: selected = %d", m.Dialogs.Selected)
	}
	m, _ = Update(m, DialogsHeaderPressed{X: 2, Y: 2, Now: 1000})
	if m.Dialogs.Selected != 1 || m.DialogsTouch.Active || m.DialogsBar.Dragging || m.DialogsToUpPress {
		t.Fatalf("band press touched list: sel=%d touch=%+v bar=%+v toUp=%v",
			m.Dialogs.Selected, m.DialogsTouch, m.DialogsBar, m.DialogsToUpPress)
	}
	if m.DialogsScroll.Top != 0 {
		t.Fatalf("band press scrolled to %d", m.DialogsScroll.Top)
	}
}

func TestSearchTypedAndBackspace(t *testing.T) {
	m := headerModel(t, 800, 600)
	m, _ = Update(m, DialogsHeaderPressed{X: 100, Y: 26, Now: 1000})
	m, _ = Update(m, SearchTyped{Text: "te", Now: 1100})
	if m.Search.Text != "te" || m.Search.Cursor != 2 {
		t.Fatalf("typed: %+v", m.Search)
	}
	m, _ = Update(m, SearchBackspace{Now: 1200})
	if m.Search.Text != "t" || m.Search.Cursor != 1 {
		t.Fatalf("backspace: %+v", m.Search)
	}
	m, _ = Update(m, SearchTyped{Text: "x", Now: 1300})
	if m.Search.Text != "tx" || m.Search.Cursor != 2 {
		t.Fatalf("retyped: %+v", m.Search)
	}
	m, _ = Update(m, SearchBackspace{Now: 1400})
	m, _ = Update(m, SearchBackspace{Now: 1500})
	if m.Search.Text != "" || m.Search.Cursor != 0 {
		t.Fatalf("emptied: %+v", m.Search)
	}
	m, _ = Update(m, SearchBackspace{Now: 1600})
	if m.Search.Text != "" {
		t.Fatalf("backspace at empty cursor: %+v", m.Search)
	}
}

func TestSearchBlink(t *testing.T) {
	m := headerModel(t, 800, 600)
	m, _ = Update(m, DialogsHeaderPressed{X: 100, Y: 26, Now: 1000})
	if !m.Search.CursorOn || !m.SearchBlinkActive() {
		t.Fatalf("focus should light caret")
	}
	m, _ = Update(m, DialogsTick{Now: 1499})
	if !m.Search.CursorOn {
		t.Fatalf("blink toggled early")
	}
	m, _ = Update(m, DialogsTick{Now: 1500})
	if m.Search.CursorOn {
		t.Fatalf("blink did not toggle at deadline")
	}
	m, _ = Update(m, DialogsTick{Now: 1999})
	if m.Search.CursorOn {
		t.Fatalf("blink toggled early on second cycle")
	}
	m, _ = Update(m, DialogsTick{Now: 2000})
	if !m.Search.CursorOn {
		t.Fatalf("blink did not relight")
	}
	m, _ = Update(m, DialogsHeaderPressed{X: 2, Y: 2, Now: 2100})
	if m.Search.CursorOn || m.SearchBlinkActive() {
		t.Fatalf("blur left caret lit: %+v", m.Search)
	}
	m, _ = Update(m, DialogsTick{Now: 3000})
	if m.Search.CursorOn {
		t.Fatalf("blink ran while unfocused")
	}
}

func TestSearchFocusLostMsg(t *testing.T) {
	m := headerModel(t, 800, 600)
	m, _ = Update(m, DialogsHeaderPressed{X: 100, Y: 26, Now: 1000})
	m, _ = Update(m, SearchTyped{Text: "a", Now: 1100})
	m, _ = Update(m, SearchFocusLost{})
	if m.Search.Focused || m.Search.CursorOn {
		t.Fatalf("focus lost msg ignored: %+v", m.Search)
	}
	if m.Search.Text != "a" {
		t.Fatalf("focus lost cleared text: %+v", m.Search)
	}
}

func TestZeroAccountScenePaintsHeader(t *testing.T) {
	m := headerModel(t, 1440, 900)
	scene := View(m)
	if len(scene.Dialogs.Rows) != 0 {
		t.Fatalf("zero-account setup has rows")
	}
	if scene.Dialogs.Header.Field.W <= 0 || scene.Dialogs.Header.Field.H != tokens.DialogsFilterHeight {
		t.Fatalf("zero-account scene lacks header chrome: %+v", scene.Dialogs.Header)
	}
	if scene.Dialogs.Header.Placeholder == "" {
		t.Fatalf("placeholder copy missing")
	}
	hd := scene.Dialogs.Header
	if !dialogs.HeaderFieldHit(m.Columns().Dialogs, hd.Field.X+1, hd.Field.Y+1) {
		t.Fatalf("field hit test rejects interior point")
	}
	if dialogs.HeaderFieldHit(m.Columns().Dialogs, 1, 1) {
		t.Fatalf("field hit test accepts band point")
	}
}

func TestSearchViewProjection(t *testing.T) {
	m := headerModel(t, 800, 600)
	m, _ = Update(m, DialogsHeaderPressed{X: 100, Y: 26, Now: 1000})
	m, _ = Update(m, SearchTyped{Text: "ab", Now: 1100})
	m, _ = Update(m, DialogsTick{Now: 1500})
	hd := View(m).Dialogs.Header
	if hd.Text != "ab" || hd.Cursor != 2 || !hd.Focused || hd.CaretOn {
		t.Fatalf("header projection = %+v, want text ab cursor 2 focused caret-off", hd)
	}
}

func TestPaintDialogsHeaderRecordsWithoutPanic(t *testing.T) {
	p := render.NewPainter()
	gtx := renderContext()
	sch := material.SchemeFor(material.Light)
	m := headerModel(t, 800, 600)
	p.PaintPane(gtx, View(m).Dialogs, sch)
	m, _ = Update(m, DialogsHeaderPressed{X: 100, Y: 26, Now: 1000})
	m, _ = Update(m, SearchTyped{Text: "abc", Now: 1100})
	p.PaintPane(gtx, View(m).Dialogs, sch)
	m, _ = Update(m, DialogsLoaded{Rows: toUpEntries(30)})
	m = dialogsScrollTo(m, 100, 1200)
	p.PaintPane(gtx, View(m).Dialogs, sch)
	p.PaintPane(gtx, dialogs.Pane{}, sch)
}
