package gui

import (
	"image/color"
	"testing"

	"uniclient/cores"
	"uniclient/engine"
)

// chatThemeSwatch converts the theme's first message color (Telegram
// 0xAARRGGBB) into a chip surface, falling back when absent (slice 65).
func TestChatThemeSwatch(t *testing.T) {
	th := cores.ChatThemeInfo{Emoticon: "🎉", MessageColors: []int{0xFF40A0E0}}
	got := chatThemeSwatch(th, color.NRGBA{R: 1, G: 2, B: 3, A: 4})
	if got.R != 0x40 || got.G != 0xA0 || got.B != 0xE0 || got.A != 255 {
		t.Errorf("swatch = %+v", got)
	}
	if got := chatThemeSwatch(cores.ChatThemeInfo{Emoticon: "❤️"}, color.NRGBA{R: 9}); got.R != 9 {
		t.Errorf("fallback = %+v", got)
	}
}

// The picker dialog state carries the chat it edits (slice 65).
func TestChatThemeDlgStateFields(t *testing.T) {
	st := &chatThemeDlgState{accountID: "a1", chatID: "u7", title: "Alice"}
	if st.accountID != "a1" || st.chatID != "u7" || st.title != "Alice" {
		t.Fatalf("state = %+v", st)
	}
}

// The DM ⋮ menu offers "Change colors…" but group/channel menus don't
// (slice 65).
func TestHeaderMenuHasThemeItem(t *testing.T) {
	if !containsAction(headerMenuItems(dmChat(), false, false), "theme") {
		t.Fatal("DM menu missing Change colors")
	}
	g := engine.ChatInfo{AccountID: "a", ChatID: "g1", Type: engine.ChatTypeGroupVal}
	if containsAction(headerMenuItems(g, false, false), "theme") {
		t.Fatal("group menu should not offer Change colors")
	}
}
