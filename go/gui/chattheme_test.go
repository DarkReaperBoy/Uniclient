package gui

import (
	"image/color"
	"testing"

	"uniclient/cores"
	"uniclient/engine"
)

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

func TestChatThemeDlgStateFields(t *testing.T) {
	st := &chatThemeDlgState{accountID: "a1", chatID: "u7", title: "Alice"}
	if st.accountID != "a1" || st.chatID != "u7" || st.title != "Alice" {
		t.Fatalf("state = %+v", st)
	}
}

func TestHeaderMenuHasThemeItem(t *testing.T) {
	if !containsAction(headerMenuItems(dmChat(), false, false, false, false, false), "theme") {
		t.Fatal("DM menu missing Change colors")
	}
	g := engine.ChatInfo{AccountID: "a", ChatID: "g1", Type: engine.ChatTypeGroupVal}
	if containsAction(headerMenuItems(g, false, false, false, false, false), "theme") {
		t.Fatal("group menu should not offer Change colors")
	}
}
