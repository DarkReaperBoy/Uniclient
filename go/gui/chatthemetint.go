package gui

// Per-chat server theme application (slice 188, parity row "Chat
// background"): the chat's active theme (chats.theme_emoticon, mirrored
// from the latest messageActionSetChatTheme service row) tints the chat
// locally — outgoing bubbles take the theme's message color and the
// message pane gets a soft vertical gradient from the theme's wallpaper
// background colors (tdesktop's peerTheme rendering, honest server data;
// the emoji-pattern wallpaper document stays out of scope). No theme =
// the stock palette, exactly as before.

import (
	"image"
	"image/color"

	"gioui.org/f32"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"

	"uniclient/cores"
	"uniclient/engine"
)

// themeColorInt converts a Telegram theme color int to NRGBA. Values
// above 0xFFFFFF carry alpha in the high byte (0xAARRGGBB); plain
// 0xRRGGBB gets full opacity. Pure — unit-tested.
func themeColorInt(c int) color.NRGBA {
	if c <= 0xFFFFFF {
		return color.NRGBA{R: uint8(c >> 16 & 0xFF), G: uint8(c >> 8 & 0xFF), B: uint8(c & 0xFF), A: 0xFF}
	}
	return color.NRGBA{A: uint8(c >> 24 & 0xFF), R: uint8(c >> 16 & 0xFF), G: uint8(c >> 8 & 0xFF), B: uint8(c & 0xFF)}
}

// themeWantsLight reports whether the app is in light mode this frame.
func themeWantsLight(f frame) bool { return f.cfg.Theme == "light" }

// activeChatTheme resolves the chat's server theme from the frame's
// theme-list snapshot (the picker cache, copied into the frame).
// nil when the chat has no theme or the list has not landed yet (the
// bubble/pane render the stock palette then, never a fake tint).
func (a *App) activeChatTheme(chat engine.ChatInfo, f frame) *cores.ChatThemeInfo {
	if chat.ThemeEmoticon == "" || f.chatThemesFor != chat.AccountID {
		return nil
	}
	lightMode := themeWantsLight(f)
	var fallback *cores.ChatThemeInfo
	for i := range f.chatThemes {
		th := &f.chatThemes[i]
		if th.Emoticon != chat.ThemeEmoticon {
			continue
		}
		// The app wants the variant matching its mode: dark app → dark
		// theme (IsDark=true). The opposite-mode entry is the fallback.
		if th.IsDark == lightMode {
			if fallback == nil {
				fallback = th
			}
			continue
		}
		return th
	}
	return fallback
}

// chatOutgoingBubble picks the outgoing bubble background: the theme's
// first message color when a chat theme is active (tdesktop tints
// outgoing bubbles), the palette accent otherwise.
func (a *App) chatOutgoingBubble(chat engine.ChatInfo, f frame) color.NRGBA {
	if th := a.activeChatTheme(chat, f); th != nil && len(th.MessageColors) > 0 {
		return themeColorInt(th.MessageColors[0])
	}
	return a.ui.p.AccentDim
}

// chatOutgoingText picks the outgoing text color with real contrast
// against the tinted bubble (luminance-based, tdesktop's choice of
// white/black label on themed bubbles).
func (a *App) chatOutgoingText(chat engine.ChatInfo, f frame) color.NRGBA {
	if th := a.activeChatTheme(chat, f); th != nil && len(th.MessageColors) > 0 {
		if nrgbaLuma(themeColorInt(th.MessageColors[0])) > 0.6 {
			return color.NRGBA{R: 0x1A, G: 0x2B, B: 0x3C, A: 0xFF}
		}
		return color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF}
	}
	return a.ui.p.Text
}

// nrgbaLuma is relative luminance (0..1). Pure — unit-tested.
func nrgbaLuma(c color.NRGBA) float32 {
	r := float32(c.R) / 255
	g := float32(c.G) / 255
	b := float32(c.B) / 255
	return 0.2126*r + 0.7152*g + 0.0722*b
}

// chatThemeBackground paints the themed message-pane background (a soft
// vertical gradient from the theme's wallpaper background colors) behind
// the message list. No theme / single color = a flat fill; no-op without
// any theme. Returns whether it painted (the caller may flat-fill).
func (a *App) chatThemeBackground(gtx layout.Context, chat engine.ChatInfo, f frame) {
	th := a.activeChatTheme(chat, f)
	if th == nil || len(th.BgColors) == 0 {
		return
	}
	w := gtx.Constraints.Max.X
	h := gtx.Constraints.Min.Y
	if h <= 0 {
		h = gtx.Constraints.Max.Y
	}
	if w <= 0 || h <= 0 {
		return
	}
	// Soften: the wallpaper colors are strong — tdesktop composes them
	// with the base theme; blend toward the app background by half.
	base := a.ui.p.Background
	c1 := mixNRGBA(themeColorInt(th.BgColors[0]), base, 0.5)
	c2 := c1
	if len(th.BgColors) > 1 {
		c2 = mixNRGBA(themeColorInt(th.BgColors[1]), base, 0.5)
	}
	stack := clip.Rect{Max: image.Pt(w, h)}.Push(gtx.Ops)
	paint.LinearGradientOp{
		Stop1:  f32.Pt(0, 0),
		Color1: c1,
		Stop2:  f32.Pt(0, float32(h)),
		Color2: c2,
	}.Add(gtx.Ops)
	paint.PaintOp{}.Add(gtx.Ops)
	stack.Pop()
}

// ensureChatThemeList loads the account's chat themes once so themed
// chats can resolve their colors (the picker shares the cache).
func (a *App) ensureChatThemeList(accountID string) {
	a.mu.Lock()
	loaded := a.chatThemesFor == accountID
	a.mu.Unlock()
	if loaded {
		return
	}
	go a.loadChatThemes(accountID)
}
