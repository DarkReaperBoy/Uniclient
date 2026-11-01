package gui

import (
	"image"
	"image/color"

	"gioui.org/f32"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"

	"uniclient/cores"
	"uniclient/engine"
)

func themeColorInt(c int) color.NRGBA {
	if c <= 0xFFFFFF {
		return color.NRGBA{R: uint8(c >> 16 & 0xFF), G: uint8(c >> 8 & 0xFF), B: uint8(c & 0xFF), A: 0xFF}
	}
	return color.NRGBA{A: uint8(c >> 24 & 0xFF), R: uint8(c >> 16 & 0xFF), G: uint8(c >> 8 & 0xFF), B: uint8(c & 0xFF)}
}

func themeWantsLight(f frame) bool { return f.cfg.Theme == "light" }

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

func (a *App) chatOutgoingBubble(chat engine.ChatInfo, f frame) color.NRGBA {
	if th := a.activeChatTheme(chat, f); th != nil && len(th.MessageColors) > 0 {
		return themeColorInt(th.MessageColors[0])
	}
	return a.ui.p.AccentDim
}

func (a *App) chatOutgoingText(chat engine.ChatInfo, f frame) color.NRGBA {
	if th := a.activeChatTheme(chat, f); th != nil && len(th.MessageColors) > 0 {
		if nrgbaLuma(themeColorInt(th.MessageColors[0])) > 0.6 {
			return color.NRGBA{R: 0x1A, G: 0x2B, B: 0x3C, A: 0xFF}
		}
		return color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF}
	}
	return a.ui.p.Text
}

func nrgbaLuma(c color.NRGBA) float32 {
	r := float32(c.R) / 255
	g := float32(c.G) / 255
	b := float32(c.B) / 255
	return 0.2126*r + 0.7152*g + 0.0722*b
}

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
	a.chatThemePattern(gtx, th, w, h)
	stack.Pop()
}

func patternTilePlan(w, h, tile, spacing int) []image.Point {
	if w <= 0 || h <= 0 || tile <= 0 || spacing < 0 {
		return nil
	}
	step := tile + spacing
	if step <= 0 {
		return nil
	}
	var out []image.Point
	row := 0
	for y := spacing / 2; y < h; y += step {
		offset := 0
		if row%2 == 1 {
			offset = step / 2
		}
		for x := -tile/2 + offset; x < w; x += step {
			out = append(out, image.Pt(x, y))
		}
		row++
	}
	return out
}

func patternAlpha(intensity int) uint8 {
	if intensity < 0 {
		intensity = -intensity
	}
	if intensity < 10 {
		intensity = 10
	}
	if intensity > 90 {
		intensity = 90
	}
	return uint8(intensity * 255 / 200)
}

func (a *App) chatThemePattern(gtx layout.Context, th *cores.ChatThemeInfo, w, h int) {
	if th == nil || th.PatternIntensity == 0 || th.Emoticon == "" {
		return
	}
	alpha := patternAlpha(th.PatternIntensity)
	if alpha == 0 {
		return
	}
	tile := gtx.Dp(unit.Dp(44))
	spacing := gtx.Dp(unit.Dp(34))
	base := a.ui.p.Background
	pat := mixNRGBA(base, a.ui.p.Text, 0.55)
	pat.A = alpha
	for _, pt := range patternTilePlan(w, h, tile, spacing) {
		pt := pt
		op := op.Offset(image.Pt(pt.X, pt.Y)).Push(gtx.Ops)
		gtx2 := gtx
		gtx2.Constraints = layout.Exact(image.Pt(tile, tile))
		lbl := a.ui.Label(unit.Sp(30), th.Emoticon)
		lbl.Color = pat
		lbl.Layout(gtx2)
		op.Pop()
	}
}

func (a *App) ensureChatThemeList(accountID string) {
	a.mu.Lock()
	loaded := a.chatThemesFor == accountID
	a.mu.Unlock()
	if loaded {
		return
	}
	go a.loadChatThemes(accountID)
}
