package gui

import (
	"image"
	"image/color"

	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"

	"uniclient/engine"
)

// Streamer mode (AyuGram parity, matrix "Streamer mode"): a drawer toggle
// that blurs identifying info while streaming — chat titles, sender names,
// forward headers, profile names and avatars get a translucent mask card
// over their footprint (layout stays stable, like AyuGram's blur), and
// real userpics fall back to a neutral person glyph. Persisted in the
// vault config (streamer_mode) and reloaded with the config snapshot.

// maskAlpha is how opaque the mask card over text is (0..255).
const maskAlpha = 232

// maskColor blends the row background toward an opaque "blur" tone.
func maskColor(bg color.NRGBA) color.NRGBA {
	return color.NRGBA{
		R: bg.R, G: bg.G, B: bg.B,
		A: maskAlpha,
	}
}

// masked paints w and then covers its footprint with a translucent card
// (AyuGram's streamer blur approximation). Keeps the original dimensions
// so surrounding layout does not move.
func (a *App) masked(gtx layout.Context, w layout.Widget) layout.Dimensions {
	d := w(gtx)
	r := gtx.Dp(unit.Dp(3))
	paint.FillShape(gtx.Ops, maskColor(a.ui.p.Surface), clip.RRect{
		Rect: image.Rect(0, 0, d.Size.X, d.Size.Y),
		NE:   r, NW: r, SE: r, SW: r,
	}.Op(gtx.Ops))
	return d
}

// streamerTitle lays out a chat/peer title, masked when streamer mode is on.
func (a *App) streamerTitle(gtx layout.Context, f frame, title string, size unit.Sp) layout.Dimensions {
	lbl := a.ui.Label(size, title)
	lbl.MaxLines = 1
	if !f.cfg.Streamer {
		return lbl.Layout(gtx)
	}
	return a.masked(gtx, lbl.Layout)
}

// streamerAvatar renders the chat avatar: a neutral person glyph while
// streamer mode is on (no photo, no initials — both identify), the real
// userpic otherwise.
func (a *App) streamerAvatar(gtx layout.Context, f frame, c engine.ChatInfo, sizeDp unit.Dp, dot connDot) layout.Dimensions {
	if f.cfg.Streamer {
		return a.personAvatar(gtx, sizeDp)
	}
	return a.chatAvatar(gtx, c, sizeDp, dot)
}

// streamerB64Avatar is the base64-thumb twin (profile/member rows).
func (a *App) streamerB64Avatar(gtx layout.Context, f frame, fallbackName, b64 string, sizeDp unit.Dp, dot connDot) layout.Dimensions {
	if f.cfg.Streamer {
		return a.personAvatar(gtx, sizeDp)
	}
	return a.b64Avatar(gtx, fallbackName, b64, sizeDp, dot)
}

// streamerAccountAvatar is the account-row twin.
func (a *App) streamerAccountAvatar(gtx layout.Context, f frame, acc engine.AccountInfo, sizeDp unit.Dp, dot connDot) layout.Dimensions {
	if f.cfg.Streamer {
		return a.personAvatar(gtx, sizeDp)
	}
	return a.accountAvatar(gtx, acc, sizeDp, dot)
}

// personAvatar draws a neutral silhouette: filled circle + person glyph.
func (a *App) personAvatar(gtx layout.Context, sizeDp unit.Dp) layout.Dimensions {
	sz := gtx.Dp(sizeDp)
	paint.FillShape(gtx.Ops, a.ui.p.SurfaceHi, clip.Ellipse{
		Min: image.Pt(0, 0), Max: image.Pt(sz, sz),
	}.Op(gtx.Ops))
	if iconSocialPerson != nil {
		inset := layout.Inset{
			Top: unit.Dp(sizeDp / 4), Bottom: unit.Dp(sizeDp / 4),
			Left: unit.Dp(sizeDp / 4), Right: unit.Dp(sizeDp / 4),
		}
		inset.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return iconSocialPerson.Layout(gtx, a.ui.p.TextFaint)
		})
	}
	return layout.Dimensions{Size: image.Pt(sz, sz)}
}

// applyStreamer persists the streamer-mode toggle (async, vault config).
func (a *App) applyStreamer(on bool) {
	go func() {
		c := engine.ConfigChanges{StreamerMode: &on}
		if err := a.eng.UpdateConfigFromBridge(&c); err != nil {
			a.setToast("Streamer mode: " + err.Error())
			return
		}
		a.refreshConfig()
	}()
}
