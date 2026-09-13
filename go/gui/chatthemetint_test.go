package gui

// Chat-theme tint (slice 188): pure logic — the Telegram color-int
// conversion, luminance contrast, and the theme resolver's match order.

import (
	"image"
	"image/color"
	"testing"

	"uniclient/cores"
	"uniclient/engine"
)

func TestThemeColorInt(t *testing.T) {
	cases := []struct {
		in   int
		want color.NRGBA
	}{
		{0x2B5278, color.NRGBA{R: 0x2B, G: 0x52, B: 0x78, A: 0xFF}},
		{0xFFFFFF, color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF}},
		{0x00FF00, color.NRGBA{R: 0x00, G: 0xFF, B: 0x00, A: 0xFF}},
		{0xFF336699, color.NRGBA{R: 0x33, G: 0x66, B: 0x99, A: 0xFF}},
		{0x80102030, color.NRGBA{R: 0x10, G: 0x20, B: 0x30, A: 0x80}},
	}
	for _, c := range cases {
		if got := themeColorInt(c.in); got != c.want {
			t.Errorf("themeColorInt(%#x) = %+v, want %+v", c.in, got, c.want)
		}
	}
}

func TestNrgbALuma(t *testing.T) {
	if l := nrgbaLuma(color.NRGBA{R: 255, G: 255, B: 255, A: 255}); l < 0.99 {
		t.Errorf("white luma = %v", l)
	}
	if l := nrgbaLuma(color.NRGBA{R: 0, G: 0, B: 0, A: 255}); l > 0.01 {
		t.Errorf("black luma = %v", l)
	}
	// Green dominates perceived luminance.
	if nrgbaLuma(color.NRGBA{R: 0, G: 255, B: 0, A: 255}) <= nrgbaLuma(color.NRGBA{R: 255, G: 0, B: 0, A: 255}) {
		t.Error("green must outweigh red")
	}
}

// newTintFrame builds a frame with a preloaded account theme list.
func newTintFrame(accountID string, themes []cores.ChatThemeInfo, lightMode bool) frame {
	f := frame{}
	f.chatThemes = themes
	f.chatThemesFor = accountID
	if lightMode {
		f.cfg.Theme = "light"
	}
	return f
}

func TestActiveChatTheme(t *testing.T) {
	a := &App{ui: NewUI()}
	chat := engine.ChatInfo{AccountID: "a1", ChatID: "c1", ThemeEmoticon: "🎨"}
	themes := []cores.ChatThemeInfo{
		{Emoticon: "🎉", IsDark: true, MessageColors: []int{0x112233}},
		{Emoticon: "🎨", IsDark: true, MessageColors: []int{0x2B5278}},
		{Emoticon: "🎨", IsDark: false, MessageColors: []int{0xE3EFFA}},
	}

	// Dark app: the dark variant of 🎨 wins.
	f := newTintFrame("a1", themes, false)
	th := a.activeChatTheme(chat, f)
	if th == nil || th.MessageColors[0] != 0x2B5278 {
		t.Fatalf("dark app: resolved %+v", th)
	}
	if got := a.chatOutgoingBubble(chat, f); got != themeColorInt(0x2B5278) {
		t.Errorf("dark bubble = %+v", got)
	}

	// Light app: the light variant wins.
	f = newTintFrame("a1", themes, true)
	th = a.activeChatTheme(chat, f)
	if th == nil || th.MessageColors[0] != 0xE3EFFA {
		t.Fatalf("light app: resolved %+v", th)
	}
	// Light bubble → dark text (contrast).
	if got := a.chatOutgoingText(chat, f); got != (color.NRGBA{R: 0x1A, G: 0x2B, B: 0x3C, A: 0xFF}) {
		t.Errorf("light bubble text = %+v", got)
	}

	// No theme / list not loaded / foreign account: stock palette.
	bare := engine.ChatInfo{AccountID: "a1", ChatID: "c1"}
	if a.activeChatTheme(bare, f) != nil {
		t.Error("unthemed chat resolved a theme")
	}
	empty := engine.ChatInfo{AccountID: "a2", ChatID: "c9", ThemeEmoticon: "🎨"}
	if a.activeChatTheme(empty, f) != nil {
		t.Error("foreign account resolved a theme")
	}
	f2 := newTintFrame("a2", nil, false)
	if a.activeChatTheme(chat, f2) != nil {
		t.Error("unloaded list resolved a theme")
	}
	if got := a.chatOutgoingBubble(chat, f2); got != a.ui.p.AccentDim {
		t.Error("unloaded list changed the bubble color")
	}

	// Emoticon with only the opposite mode: the fallback wins (honest tint
	// beats none — tdesktop falls back to the theme's other settings).
	only := []cores.ChatThemeInfo{{Emoticon: "🎨", IsDark: true, MessageColors: []int{0x2B5278}}}
	f3 := newTintFrame("a1", only, true)
	if th := a.activeChatTheme(chat, f3); th == nil || th.IsDark != true {
		t.Fatalf("opposite-mode fallback = %+v", th)
	}
}

// TestPatternTilePlan (slice 198): the emoji-pattern grid — staggered
// rows, full coverage of the pane, honest degenerate inputs.
func TestPatternTilePlan(t *testing.T) {
	pts := patternTilePlan(300, 200, 40, 10)
	if len(pts) < 12 {
		t.Fatalf("tiles = %d, want the pane covered (>=12)", len(pts))
	}
	// Coverage: every pixel of the pane is within one tile of some origin
	// (the stagger keeps gaps under the step).
	step := 40 + 10
	for _, probe := range []image.Point{{0, 0}, {299, 0}, {0, 199}, {299, 199}, {150, 100}} {
		near := false
		for _, p := range pts {
			if abs(p.X-probe.X) <= step && abs(p.Y-probe.Y) <= step {
				near = true
				break
			}
		}
		if !near {
			t.Errorf("probe %v not covered by any tile", probe)
		}
	}
	// Degenerate inputs: nil, never panic.
	for _, tc := range []struct{ w, h, tile, sp int }{
		{0, 200, 40, 10}, {300, 0, 40, 10}, {300, 200, 0, 10}, {-1, -1, 40, 10},
	} {
		if got := patternTilePlan(tc.w, tc.h, tc.tile, tc.sp); got != nil {
			t.Errorf("patternTilePlan(%d,%d,%d,%d) = %v, want nil", tc.w, tc.h, tc.tile, tc.sp, got)
		}
	}
}

// TestPatternAlpha (slice 198): intensity → the subtle tile alpha.
func TestPatternAlpha(t *testing.T) {
	if got := patternAlpha(50); got != 63 { // 50*255/200
		t.Errorf("patternAlpha(50) = %d, want 63", got)
	}
	if got := patternAlpha(-50); got != 63 { // sign = rotation flip, not alpha
		t.Errorf("patternAlpha(-50) = %d, want 63", got)
	}
	if lo, hi := patternAlpha(0), patternAlpha(100); lo != 12 || hi != 114 {
		t.Errorf("clamps = %d/%d, want 12/114", lo, hi)
	}
	if got := patternAlpha(1000); got != 114 {
		t.Errorf("overflow clamp = %d, want 114", got)
	}
}
