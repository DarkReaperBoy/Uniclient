package tests

import (
	"math"
	"testing"

	. "uniclient/ui/dialogs"
	. "uniclient/ui/icons"
	. "uniclient/ui/tokens"
)

func TestMainMenuSurfaceTokens(t *testing.T) {
	if MainMenuWidth != 274 {
		t.Fatalf("menu width = %d, want 274 (mainMenuWidth, window_main_menu.style)", MainMenuWidth)
	}
	if MainMenuSlideDurationMs != 200 {
		t.Fatalf("menu slide duration = %d, want 200 (boxDuration, lib_ui layers.style)", MainMenuSlideDurationMs)
	}
	if MainMenuScrimAlpha != float32(0x7f)/255 {
		t.Fatalf("menu scrim alpha = %v, want 0x7f/255 (layerBg #0000007f, lib_ui colors.palette)", MainMenuScrimAlpha)
	}
	if MainMenuToggleSize != 40 {
		t.Fatalf("menu toggle size = %d, want 40 (dialogsMenuToggle, dialogs.style)", MainMenuToggleSize)
	}
	if MainMenuToggleX != DialogsFilterPadX {
		t.Fatalf("menu toggle x = %d, want %d (dialogsFilterPadding.x, dialogs_widget.cpp)", MainMenuToggleX, DialogsFilterPadX)
	}
	if MainMenuToggleY != (TopBarHeight-MainMenuToggleSize)/2 {
		t.Fatalf("menu toggle y = %d, want %d (vertically centered in the top bar band)", MainMenuToggleY, (TopBarHeight-MainMenuToggleSize)/2)
	}
	if MainMenuToggleY != 7 {
		t.Fatalf("menu toggle y = %d, want 7 (dialogsFilterPadding.y)", MainMenuToggleY)
	}
	if DialogsFilterLeftWithMenu != 54 {
		t.Fatalf("field left with menu = %d, want 54 (7 + 40 + 7, dialogs_widget.cpp filterLeft)", DialogsFilterLeftWithMenu)
	}
	if MainMenuShadowWidth != 8 {
		t.Fatalf("menu right-edge shadow width = %d, want 8 (boxRoundShadow roundShadowRadius8px)", MainMenuShadowWidth)
	}
}

func TestMainMenuAccountsTokens(t *testing.T) {
	if MainMenuAccountUserpicSize != 26 {
		t.Fatalf("account userpic size = %d, want 26 (mainMenuAccountSize, window.style)", MainMenuAccountUserpicSize)
	}
	if MainMenuAccountRingLine != 2 {
		t.Fatalf("account active ring line = %d, want 2 (mainMenuAccountLine, window.style)", MainMenuAccountRingLine)
	}
	if MainMenuAccountIconLeft != 23 {
		t.Fatalf("account icon left = %d, want 23 (mainMenuAddAccountButton.iconLeft, window.style)", MainMenuAccountIconLeft)
	}
	if MainMenuAccountRowHeight != 36 {
		t.Fatalf("account row height = %d, want 36 (padding 11+9 + 16dp semibold line)", MainMenuAccountRowHeight)
	}
	if MainMenuFooterVersionBottom != 17 {
		t.Fatalf("footer version bottom = %d, want 17 (mainMenuVersionBottom, window_main_menu.style)", MainMenuFooterVersionBottom)
	}
}

func TestEaseOutCirc(t *testing.T) {
	cases := []struct {
		t, want float32
	}{
		{0, 0},
		{0.25, float32(math.Sqrt(0.4375))},
		{0.5, float32(math.Sqrt(0.75))},
		{0.75, float32(math.Sqrt(0.9375))},
		{1, 1},
	}
	for _, c := range cases {
		if got := EaseOutCirc(c.t); abs32(got-c.want) > 0.0005 {
			t.Fatalf("easeOutCirc(%v) = %v, want %v (sqrt(1-(1-t)^2), lib_ui animation_value.cpp)", c.t, got, c.want)
		}
	}
	if got := EaseOutCirc(0.5); abs32(got-0.8660254) > 0.0005 {
		t.Fatalf("easeOutCirc(0.5) = %v, want 0.8660254", got)
	}
}

func TestRippleMaxRadiusSquareBox(t *testing.T) {
	if r := RippleMaxRadiusIn(40, 40, 0, 0); r != 57 {
		t.Fatalf("corner origin radius = %d, want 57 (40*sqrt2 rounded)", r)
	}
	if r := RippleMaxRadiusIn(40, 40, 20, 20); r != 28 {
		t.Fatalf("center origin radius = %d, want 28 (20*sqrt2 rounded)", r)
	}
	if r := RippleMaxRadiusIn(40, 40, 18, 23); r != 32 {
		t.Fatalf("(18,23) origin radius = %d, want 32 (farthest corner (40,0): sqrt(22^2+23^2))", r)
	}
	if r := RippleMaxRadiusIn(40, 40, 44, 20); r != 48 {
		t.Fatalf("origin outside the box radius = %d, want 48 (farthest corner (0,0): sqrt(44^2+20^2))", r)
	}
	if r := RippleMaxRadius(21, 21); r != 30 {
		t.Fatalf("legacy circle-box API drifted: %d, want 30", r)
	}
}

func TestHeaderLayoutCarriesMenuToggle(t *testing.T) {
	hd := HeaderLayout(440)
	wantToggle := Rect{X: 7, Y: 7, W: 40, H: 40}
	if hd.Toggle != wantToggle {
		t.Fatalf("toggle = %+v, want %+v", hd.Toggle, wantToggle)
	}
	if hd.Field.X != 54 || hd.Field.W != 440-65 {
		t.Fatalf("field = %+v, want x 54 w %d (toggle layout: filterLeft 54, right 11)", hd.Field, 440-65)
	}
	if hd.Field.Y != 9 || hd.Field.H != 35 {
		t.Fatalf("field y/h drifted: %+v", hd.Field)
	}
	narrow := HeaderLayout(390)
	if narrow.Field.X != 54 || narrow.Field.W != 390-65 {
		t.Fatalf("narrow field = %+v, want x 54 w %d", narrow.Field, 390-65)
	}
}

func TestHeaderToggleHit(t *testing.T) {
	if !HeaderToggleHit(440, 7, 7) || !HeaderToggleHit(440, 46, 46) {
		t.Fatalf("inside the toggle must hit")
	}
	if HeaderToggleHit(440, 6, 7) || HeaderToggleHit(440, 47, 46) || HeaderToggleHit(440, 20, 50) {
		t.Fatalf("outside the toggle must not hit")
	}
	if HeaderToggleHit(440, 60, 20) {
		t.Fatalf("the field area is not the toggle")
	}
}

func TestDialogsMenuGlyph(t *testing.T) {
	minX, minY, maxX, maxY := DialogsMenu.Glyph.Bounds()
	if minX != 3 || maxX != 21 || minY != 6 || maxY != 18 {
		t.Fatalf("menu glyph bounds = %v,%v,%v,%v, want 3,6,21,18 (Material menu icon)", minX, minY, maxX, maxY)
	}
	if len(DialogsMenu.Glyph.Paths) != 3 {
		t.Fatalf("menu glyph paths = %d, want 3 bars", len(DialogsMenu.Glyph.Paths))
	}
	if DialogsMenu.Cell.W != 24 || DialogsMenu.Cell.H != 24 || DialogsMenu.Cell.X != 8 || DialogsMenu.Cell.Y != 8 {
		t.Fatalf("menu cell = %+v, want 24x24 at (8,8) centered in the 40dp button", DialogsMenu.Cell)
	}
}

func abs32(v float32) float32 {
	if v < 0 {
		return -v
	}
	return v
}
