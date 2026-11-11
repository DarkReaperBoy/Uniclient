package tests

import (
	"testing"

	. "uniclient/ui/app"
	chatrender "uniclient/ui/history/render"
	"uniclient/ui/material"
)

func downShownModel(t *testing.T) Model {
	t.Helper()
	m := downModel(t, downChatItems(40))
	m = chatScrollTo(m, 1880, 1000)
	m = settleDownAnim(m, 1150)
	m = chatScrollTo(m, 1380, 1200)
	m = settleDownAnim(m, 1350)
	if m.ChatDown.Progress != 1 {
		t.Fatalf("setup: down progress = %v, want 1", m.ChatDown.Progress)
	}
	return m
}

func TestChatCornerHoverFollowsPointer(t *testing.T) {
	m := downShownModel(t)
	if s := View(m); s.Chat.DownHover || s.Chat.MentionsHover || s.Chat.ReactionsHover {
		t.Fatalf("hover before any move: down=%v mentions=%v reactions=%v",
			s.Chat.DownHover, s.Chat.MentionsHover, s.Chat.ReactionsHover)
	}
	m, _ = Update(m, ChatDragged{X: 760, Y: 80, Now: 1400})
	s := View(m)
	if !s.Chat.DownHover || s.Chat.MentionsHover || s.Chat.ReactionsHover {
		t.Fatalf("mouse over the down button: down=%v mentions=%v reactions=%v",
			s.Chat.DownHover, s.Chat.MentionsHover, s.Chat.ReactionsHover)
	}
	m, _ = Update(m, ChatDragged{X: 400, Y: 60, Now: 1410})
	if s = View(m); s.Chat.DownHover {
		t.Fatalf("hover must clear when the pointer leaves the button")
	}
}

func TestChatCornerHoverIgnoresTouch(t *testing.T) {
	m := downShownModel(t)
	m, _ = Update(m, ChatDragged{X: 760, Y: 80, Now: 1400, Touch: true})
	if s := View(m); s.Chat.DownHover {
		t.Fatalf("touch move must not hover the button")
	}
}

func TestChatLeaveClearsHover(t *testing.T) {
	m := downShownModel(t)
	m, _ = Update(m, ChatDragged{X: 760, Y: 80, Now: 1400})
	if s := View(m); !s.Chat.DownHover {
		t.Fatalf("setup: hover must be set over the down button")
	}
	m, _ = Update(m, ChatLeft{})
	if s := View(m); s.Chat.DownHover {
		t.Fatalf("leaving the chat pane must clear hover")
	}
}

func TestDownRipplePressFadesOnRelease(t *testing.T) {
	m := downShownModel(t)
	m, _ = Update(m, ChatPressed{X: 750, Y: 80, Now: 1500})
	s := View(m)
	if s.Chat.DownRipple.OriginX != 9 || s.Chat.DownRipple.OriginY != 17 {
		t.Fatalf("ripple origin = %d,%d, want 9,17 (press point relative to the circle)",
			s.Chat.DownRipple.OriginX, s.Chat.DownRipple.OriginY)
	}
	if s.Chat.DownRipple.Alpha != 1 || s.Chat.DownRipple.Radius != 0 {
		t.Fatalf("ripple at press: %+v, want radius 0 alpha 1", s.Chat.DownRipple)
	}
	if !m.ChatRippleActive() {
		t.Fatalf("the ripple must drive the animation clock")
	}
	m, _ = Update(m, ChatTick{Now: 1825})
	s = View(m)
	if s.Chat.DownRipple.Radius <= 0 {
		t.Fatalf("mid-show radius must be positive, got %d", s.Chat.DownRipple.Radius)
	}
	m, _ = Update(m, ChatReleased{X: 750, Y: 80, Now: 1900})
	m, _ = Update(m, ChatTick{Now: 2000})
	s = View(m)
	if s.Chat.DownRipple.Alpha <= 0 || s.Chat.DownRipple.Alpha >= 1 {
		t.Fatalf("mid-fade alpha = %v, want strictly between 0 and 1", s.Chat.DownRipple.Alpha)
	}
	m, _ = Update(m, ChatTick{Now: 2100})
	if m.ChatRippleActive() {
		t.Fatalf("the ripple must clear after the fade completes")
	}
	if s = View(m); s.Chat.DownRipple.Radius != 0 || s.Chat.DownRipple.Alpha != 0 {
		t.Fatalf("cleared ripple projection: %+v, want zero", s.Chat.DownRipple)
	}
}

func TestDownRippleReleaseOutsideStillFades(t *testing.T) {
	m := downShownModel(t)
	m, _ = Update(m, ChatPressed{X: 750, Y: 80, Now: 1500})
	m, _ = Update(m, ChatReleased{X: 400, Y: 60, Now: 1600})
	if m.ChatScroll.Top != 1380 {
		t.Fatalf("release outside the button moved top to %d, want 1380", m.ChatScroll.Top)
	}
	if !m.ChatRippleActive() {
		t.Fatalf("a release outside the button must still fade the ripple, not clear it")
	}
	m, _ = Update(m, ChatTick{Now: 1800})
	if m.ChatRippleActive() {
		t.Fatalf("the ripple must be gone after the fade completes")
	}
}

func TestDownRippleCancelClears(t *testing.T) {
	m := downShownModel(t)
	m, _ = Update(m, ChatPressed{X: 750, Y: 80, Now: 1500})
	m, _ = Update(m, ChatPressCanceled{})
	if m.ChatRippleActive() {
		t.Fatalf("cancel must clear the ripple instantly (clearState law)")
	}
}

func TestDownRippleIgnoresPressOutsideButtons(t *testing.T) {
	m := downShownModel(t)
	m, _ = Update(m, ChatPressed{X: 400, Y: 60, Now: 1500})
	if m.ChatRippleActive() {
		t.Fatalf("press on a message must not start a ripple")
	}
}

func TestMentionsRippleStartsOnItsButton(t *testing.T) {
	m := mentionsModel(t, 12, 40)
	m, _ = Update(m, ChatTick{Now: 250})
	m = chatScrollTo(m, 1880, 300)
	m, _ = Update(m, ChatTick{Now: 450})
	m, _ = Update(m, ChatPressed{X: 750, Y: 80, Now: 500})
	s := View(m)
	if s.Chat.MentionsRipple.OriginX != 9 || s.Chat.MentionsRipple.OriginY != 17 {
		t.Fatalf("mentions ripple origin = %d,%d, want 9,17",
			s.Chat.MentionsRipple.OriginX, s.Chat.MentionsRipple.OriginY)
	}
	if s.Chat.MentionsRipple.Alpha != 1 {
		t.Fatalf("mentions ripple alpha = %v, want 1", s.Chat.MentionsRipple.Alpha)
	}
	if s.Chat.DownRipple.Radius != 0 || s.Chat.DownRipple.Alpha != 0 {
		t.Fatalf("the down button must carry no ripple: %+v", s.Chat.DownRipple)
	}
	m, _ = Update(m, ChatReleased{X: 750, Y: 80, Now: 510})
	m, _ = Update(m, ChatTick{Now: 720})
	if m.ChatRippleActive() {
		t.Fatalf("the mentions ripple must clear after its fade")
	}
}

func TestCornerStatesResetOnChatSwitch(t *testing.T) {
	m := downShownModel(t)
	m, _ = Update(m, ChatDragged{X: 760, Y: 80, Now: 1400})
	m, _ = Update(m, ChatPressed{X: 750, Y: 80, Now: 1500})
	m, _ = Update(m, ChatLoaded{Items: downChatItems(3)})
	if m.ChatRippleActive() {
		t.Fatalf("chat switch must reset the ripple")
	}
	if m.ChatHover != CornerNone {
		t.Fatalf("chat switch must reset hover, got %v", m.ChatHover)
	}
}

func TestCornerHoverRipplePaintJourney(t *testing.T) {
	m := downShownModel(t)
	m, _ = Update(m, ChatDragged{X: 760, Y: 80, Now: 1400})
	m, _ = Update(m, ChatPressed{X: 750, Y: 80, Now: 1500})
	m, _ = Update(m, ChatTick{Now: 1825})
	scene := View(m)
	if !scene.Chat.DownHover || scene.Chat.DownRipple.Radius <= 0 {
		t.Fatalf("setup: hover=%v ripple radius=%d, want hover and a growing ripple",
			scene.Chat.DownHover, scene.Chat.DownRipple.Radius)
	}
	cp := chatrender.NewChatPainter()
	gtx := renderContext()
	cp.PaintChatPane(gtx, scene.Chat, material.SchemeFor(material.Light))
}
