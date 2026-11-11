package tests

import (
	"testing"

	. "uniclient/ui/app"
	"uniclient/ui/dialogs/render"
	"uniclient/ui/material"
	"uniclient/ui/tokens"
)

func menuModel(t *testing.T, w, h int) Model {
	t.Helper()
	m, _ := Update(InitialModel(), Resized{Width: w, Height: h})
	return m
}

func menuOpenModel(t *testing.T, now int) Model {
	t.Helper()
	m := menuModel(t, 1440, 900)
	m, _ = Update(m, DialogsHeaderPressed{X: 25, Y: 30, Now: now})
	m, _ = Update(m, DialogsReleased{X: 25, Y: 30 - tokens.TopBarHeight, Now: now})
	m, _ = Update(m, DialogsTick{Now: now + tokens.MainMenuSlideDurationMs})
	if !m.Menu.Open || m.Menu.Progress != 1 {
		t.Fatalf("setup: menu open state %v progress %v", m.Menu.Open, m.Menu.Progress)
	}
	return m
}

func TestMenuHeaderPressStartsRipple(t *testing.T) {
	m := menuModel(t, 1440, 900)
	m, _ = Update(m, DialogsHeaderPressed{X: 25, Y: 30, Now: 1000})
	if !m.MenuTogglePress {
		t.Fatalf("press on the toggle must arm the toggle press")
	}
	if m.MenuToggleRipple.OriginX != 25-tokens.MainMenuToggleX || m.MenuToggleRipple.OriginY != 30-tokens.MainMenuToggleY {
		t.Fatalf("ripple origin = %d,%d, want toggle-box-relative press point",
			m.MenuToggleRipple.OriginX, m.MenuToggleRipple.OriginY)
	}
	if m.MenuToggleRipple.Started != 1000 || m.MenuToggleRipple.Fading {
		t.Fatalf("ripple state = %+v, want started 1000 not fading", m.MenuToggleRipple)
	}
	if !m.MenuActive() {
		t.Fatalf("the toggle ripple must drive the tick clock")
	}
	if m.Menu.Open {
		t.Fatalf("press alone must not open the menu")
	}
	if m.Search.Focused {
		t.Fatalf("pressing the toggle must blur the search field")
	}
}

func TestMenuHeaderPressOutsideToggleFocusesField(t *testing.T) {
	m := menuModel(t, 1440, 900)
	m, _ = Update(m, DialogsHeaderPressed{X: 100, Y: 26, Now: 1000})
	if m.MenuTogglePress || m.MenuToggleRipple != (tokens.RippleState{}) {
		t.Fatalf("press on the field must not touch the toggle, got press %v ripple %+v",
			m.MenuTogglePress, m.MenuToggleRipple)
	}
	if !m.Search.Focused {
		t.Fatalf("press on the field must focus it")
	}
}

func TestMenuToggleReleaseOpensPanel(t *testing.T) {
	m := menuModel(t, 1440, 900)
	m, _ = Update(m, DialogsHeaderPressed{X: 25, Y: 30, Now: 1000})
	m, _ = Update(m, DialogsReleased{X: 46, Y: 40 - tokens.TopBarHeight, Now: 1030})
	if !m.Menu.Open {
		t.Fatalf("release inside the toggle must open the menu")
	}
	if !m.Menu.Anim || m.Menu.From != 0 || m.Menu.To != 1 {
		t.Fatalf("open anim = %+v, want animating 0 -> 1", m.Menu)
	}
	if m.Menu.Progress != 0 {
		t.Fatalf("progress at release = %v, want 0 (animation starts on the next tick)", m.Menu.Progress)
	}
	if !m.MenuActive() {
		t.Fatalf("the slide must drive the tick clock")
	}
	m, _ = Update(m, DialogsTick{Now: 1130})
	if m.Menu.Progress <= 0.86 || m.Menu.Progress >= 0.87 {
		t.Fatalf("slide at half = %v, want 0.866 (easeOutCirc(0.5))", m.Menu.Progress)
	}
	if m.Menu.FadeProgress <= 0.86 || m.Menu.FadeProgress >= 0.87 {
		t.Fatalf("fade at half = %v, want 0.866 (easeOutCirc on show)", m.Menu.FadeProgress)
	}
	m, _ = Update(m, DialogsTick{Now: 1230})
	if m.Menu.Progress != 1 || m.Menu.FadeProgress != 1 || m.Menu.Anim {
		t.Fatalf("slide end = %v fade %v anim %v, want 1 1 done", m.Menu.Progress, m.Menu.FadeProgress, m.Menu.Anim)
	}
}

func TestMenuToggleReleaseOutsideDoesNotOpen(t *testing.T) {
	m := menuModel(t, 1440, 900)
	m, _ = Update(m, DialogsHeaderPressed{X: 25, Y: 30, Now: 1000})
	m, _ = Update(m, DialogsReleased{X: 200, Y: 30 - tokens.TopBarHeight, Now: 1030})
	if m.Menu.Open {
		t.Fatalf("release outside the toggle must not open the menu")
	}
	if !m.MenuToggleRipple.Fading {
		t.Fatalf("release outside still fades the ripple (the reference lastStop law)")
	}
	m, _ = Update(m, DialogsTick{Now: 1030 + tokens.HistoryToDownRippleHideMs})
	if m.MenuToggleRipple != (tokens.RippleState{}) {
		t.Fatalf("ripple must clear after the fade, got %+v", m.MenuToggleRipple)
	}
}

func TestMenuTogglePressCancelClearsRipple(t *testing.T) {
	m := menuModel(t, 1440, 900)
	m, _ = Update(m, DialogsHeaderPressed{X: 25, Y: 30, Now: 1000})
	m, _ = Update(m, DialogsPressCanceled{})
	if m.MenuToggleRipple != (tokens.RippleState{}) || m.MenuTogglePress {
		t.Fatalf("cancel must clear the ripple and the press instantly, got ripple %+v press %v",
			m.MenuToggleRipple, m.MenuTogglePress)
	}
}

func TestMenuRippleShowCurve(t *testing.T) {
	m := menuModel(t, 1440, 900)
	m, _ = Update(m, DialogsHeaderPressed{X: 25, Y: 30, Now: 1000})
	s := View(m)
	if s.Dialogs.Header.ToggleRipple.Alpha != 1 || s.Dialogs.Header.ToggleRipple.Radius != 0 {
		t.Fatalf("ripple at press = %+v, want radius 0 alpha 1", s.Dialogs.Header.ToggleRipple)
	}
	m, _ = Update(m, DialogsTick{Now: 1130})
	s = View(m)
	if s.Dialogs.Header.ToggleRipple.Radius != 22 {
		t.Fatalf("radius at 130ms = %d, want 22 (easeOutQuint 0.67232 * 32)", s.Dialogs.Header.ToggleRipple.Radius)
	}
}

func TestMenuScrimPressCloses(t *testing.T) {
	m := menuOpenModel(t, 1000)
	m, _ = Update(m, MenuScrimPressed{Now: 2000})
	if m.Menu.Open || !m.Menu.Anim || m.Menu.To != 0 {
		t.Fatalf("scrim press = %+v, want closing 1 -> 0", m.Menu)
	}
	m, _ = Update(m, DialogsTick{Now: 2100})
	if m.Menu.Progress <= 0.13 || m.Menu.Progress >= 0.14 {
		t.Fatalf("hide slide at half = %v, want 0.134 (1 - easeOutCirc(0.5))", m.Menu.Progress)
	}
	if m.Menu.FadeProgress != 0.5 {
		t.Fatalf("hide fade at half = %v, want 0.5 (linear on hide — the reference layer law)", m.Menu.FadeProgress)
	}
	m, _ = Update(m, DialogsTick{Now: 2200})
	if m.Menu.Progress != 0 || m.Menu.Anim {
		t.Fatalf("hide end = %v anim %v, want 0 done", m.Menu.Progress, m.Menu.Anim)
	}
}

func TestMenuPressRoutingWhileOpen(t *testing.T) {
	m := menuOpenModel(t, 1000)
	if scrim, eat := m.MenuPressRoute(300, 100); !scrim || eat {
		t.Fatalf("press beyond the panel: scrim=%v eat=%v, want scrim only", scrim, eat)
	}
	if scrim, eat := m.MenuPressRoute(100, 100); scrim || !eat {
		t.Fatalf("press on the panel: scrim=%v eat=%v, want eaten only", scrim, eat)
	}
	if scrim, eat := m.MenuPressRoute(25, 30); scrim || !eat {
		t.Fatalf("press on the covered toggle: scrim=%v eat=%v, want eaten (the panel covers the toggle)", scrim, eat)
	}
	closed := menuModel(t, 1440, 900)
	if scrim, eat := closed.MenuPressRoute(300, 100); scrim || eat {
		t.Fatalf("press with the menu closed: scrim=%v eat=%v, want neither", scrim, eat)
	}
}

func TestMenuToggleHoverJourneys(t *testing.T) {
	m := menuModel(t, 1440, 900)
	if s := View(m); s.Dialogs.Header.ToggleHover {
		t.Fatalf("hover before any move")
	}
	m, _ = Update(m, DialogsDragged{X: 25, Y: 30 - tokens.TopBarHeight, Touch: true, Now: 1000})
	if s := View(m); s.Dialogs.Header.ToggleHover {
		t.Fatalf("touch move must not hover")
	}
	m, _ = Update(m, DialogsDragged{X: 25, Y: 30 - tokens.TopBarHeight, Now: 1010})
	if s := View(m); !s.Dialogs.Header.ToggleHover {
		t.Fatalf("mouse over the toggle must hover")
	}
	m, _ = Update(m, DialogsDragged{X: 200, Y: 30 - tokens.TopBarHeight, Now: 1020})
	if s := View(m); s.Dialogs.Header.ToggleHover {
		t.Fatalf("hover must clear when the pointer leaves the toggle")
	}
	m, _ = Update(m, DialogsDragged{X: 25, Y: 30 - tokens.TopBarHeight, Now: 1030})
	m, _ = Update(m, DialogsLeft{})
	if s := View(m); s.Dialogs.Header.ToggleHover {
		t.Fatalf("leaving the pane must clear hover")
	}
}

func TestMenuOpenClearsToggleHover(t *testing.T) {
	m := menuModel(t, 1440, 900)
	m, _ = Update(m, DialogsDragged{X: 25, Y: 30 - tokens.TopBarHeight, Now: 1000})
	if s := View(m); !s.Dialogs.Header.ToggleHover {
		t.Fatalf("setup: hover must be set")
	}
	m, _ = Update(m, DialogsHeaderPressed{X: 25, Y: 30, Now: 1000})
	m, _ = Update(m, DialogsReleased{X: 25, Y: 30 - tokens.TopBarHeight, Now: 1000})
	if s := View(m); s.Dialogs.Header.ToggleHover {
		t.Fatalf("opening the menu clears the toggle hover (the panel covers it)")
	}
}

func TestMenuToggleHoverSilencedWhileOpen(t *testing.T) {
	m := menuOpenModel(t, 1000)
	m, _ = Update(m, DialogsDragged{X: 25, Y: 30 - tokens.TopBarHeight, Now: 1500})
	if s := View(m); s.Dialogs.Header.ToggleHover {
		t.Fatalf("moves over the covered toggle while the menu is open must not hover")
	}
}

func TestMenuCoverAndRowsFromAccounts(t *testing.T) {
	m := menuModel(t, 1440, 900)
	s := View(m)
	if s.Menu.CoverHasAccount || s.Menu.CoverName != "" || len(s.Menu.Rows) != 0 {
		t.Fatalf("zero accounts: cover must be empty, got %+v", s.Menu)
	}
	m = applyEngineEvent(t, m, accountListWire)
	s = View(m)
	if !s.Menu.CoverHasAccount || s.Menu.CoverName != "Pals" {
		t.Fatalf("cover name = %q, want Pals (first account is the default context)", s.Menu.CoverName)
	}
	if s.Menu.CoverStatus != "offline" {
		t.Fatalf("cover status = %q, want offline (conn_state 0)", s.Menu.CoverStatus)
	}
	if len(s.Menu.Rows) != 2 {
		t.Fatalf("rows = %d, want 2", len(s.Menu.Rows))
	}
	if s.Menu.Rows[0].Name != "Pals" || s.Menu.Rows[1].Name != "Work" {
		t.Fatalf("row names = %q %q, want Pals Work (sort order)", s.Menu.Rows[0].Name, s.Menu.Rows[1].Name)
	}
	if !s.Menu.Rows[0].Active || s.Menu.Rows[1].Active {
		t.Fatalf("active ring must mark the context account only")
	}
}

func TestMenuCoverFollowsOpenChatAccount(t *testing.T) {
	m := applyEngineEvent(t, feedsModel(t, 1440, 900).WithPort(&fakeChatPort{ok: true}),
		chatSnapshotWire("tele_02", badgeRowWire(2000, 5, 7), 2000))
	m, cmd := Update(m, DialogsPressed{X: 20, Y: 20, Now: 2100})
	if cmd == nil {
		t.Fatalf("setup: pressing the chat row must produce a load cmd")
	}
	m, _ = Update(m, cmd())
	s := View(m)
	if !s.Menu.CoverHasAccount || s.Menu.CoverName != "Work" {
		t.Fatalf("cover name = %q, want Work (the open chat's account)", s.Menu.CoverName)
	}
	if !s.Menu.Rows[1].Active || s.Menu.Rows[0].Active {
		t.Fatalf("the ring must follow the open chat's account")
	}
}

func TestMenuFooterPinned(t *testing.T) {
	m := menuModel(t, 1440, 900)
	s := View(m)
	if s.Menu.FooterName != "Uniclient" {
		t.Fatalf("footer name = %q, want Uniclient", s.Menu.FooterName)
	}
	if s.Menu.FooterVersion == "" {
		t.Fatalf("footer version must not be empty")
	}
}

func TestMenuViewProjectionWhileClosed(t *testing.T) {
	m := menuModel(t, 1440, 900)
	s := View(m)
	if s.Menu.Slide != 0 || s.Menu.Fade != 0 {
		t.Fatalf("closed menu projection = %+v, want zero slide/fade", s.Menu)
	}
	opened := menuOpenModel(t, 1000)
	s = View(opened)
	if s.Menu.Slide != 1 || s.Menu.Fade != 1 {
		t.Fatalf("open menu projection slide=%v fade=%v, want 1 1", s.Menu.Slide, s.Menu.Fade)
	}
	if s.Menu.Width != tokens.MainMenuWidth || s.Menu.Height != 900 {
		t.Fatalf("menu size = %dx%d, want %dx900", s.Menu.Width, s.Menu.Height, tokens.MainMenuWidth)
	}
}

func TestMenuAccountsUpdateLive(t *testing.T) {
	m := menuOpenModel(t, 1000)
	m = applyEngineEvent(t, m, accountListWire)
	s := View(m)
	if len(s.Menu.Rows) != 2 {
		t.Fatalf("rows must appear live while the menu is open, got %d", len(s.Menu.Rows))
	}
	m = applyEngineEvent(t, m, accountListEmptyWire)
	s = View(m)
	if len(s.Menu.Rows) != 0 || s.Menu.CoverHasAccount {
		t.Fatalf("rows must vanish live on an empty account list, got %d rows cover %v", len(s.Menu.Rows), s.Menu.CoverHasAccount)
	}
}

func TestMenuPaintJourney(t *testing.T) {
	m := menuOpenModel(t, 1000)
	m = applyEngineEvent(t, m, accountListWire)
	s := View(m)
	p := render.NewPainter()
	gtx := renderContext()
	p.PaintPane(gtx, s.Dialogs, material.SchemeFor(material.Light))
	p.PaintMenu(gtx, s.Menu, material.SchemeFor(material.Light))
	m, _ = Update(m, MenuScrimPressed{Now: 1200})
	m, _ = Update(m, DialogsTick{Now: 1300})
	s = View(m)
	p.PaintMenu(gtx, s.Menu, material.SchemeFor(material.Light))
}
