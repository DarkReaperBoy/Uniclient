package gui

import (
	"image"
	"image/color"
	"sync"
	"sync/atomic"
	"time"
	"unicode"

	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

var msgShowSeconds atomic.Bool

func setMsgShowSeconds(on bool) { msgShowSeconds.Store(on) }

func msgTimeLabel(ms int64) string {
	if ms == 0 {
		return ""
	}
	if msgShowSeconds.Load() {
		return time.UnixMilli(ms).Format("15:04:05")
	}
	return time.UnixMilli(ms).Format("15:04")
}

func isBidiControl(r rune) bool {
	switch {
	case r >= 0x202A && r <= 0x202E,
		r >= 0x2066 && r <= 0x2069,
		r == 0x200E, r == 0x200F,
		r == 0x061C:
		return true
	}
	return false
}

func stripZalgo(s string) string {
	dirty := false
	combos := 0
	for _, r := range s {
		if isBidiControl(r) {
			dirty = true
			break
		}
		if unicode.Is(unicode.Mn, r) {
			combos++
			if combos >= 3 {
				dirty = true
				break
			}
		} else {
			combos = 0
		}
	}
	if !dirty {
		return s
	}

	var b []rune
	run := 0
	for _, r := range s {
		if isBidiControl(r) {
			run = 0
			continue
		}
		if unicode.Is(unicode.Mn, r) {
			run++
			if run > 2 {
				continue
			}
		} else {
			run = 0
		}
		b = append(b, r)
	}
	return string(b)
}

func ayuFilterText(s string, on bool) string {
	if !on || s == "" {
		return s
	}
	return stripZalgo(s)
}

func reactionsVisible(chat engine.ChatInfo, cfg cfgSnapshot) bool {
	switch chat.Type {
	case engine.ChatTypeChanVal:
		return cfg.AyuReactChannels
	case engine.ChatTypeGroupVal, engine.ChatTypeTopicVal:
		return cfg.AyuReactGroups
	default:
		return cfg.AyuReactPrivate
	}
}

type mediaConfirmState struct {
	kind      string
	send      func()
	ok        *widget.Clickable
	cancelBtn *widget.Clickable
}

var (
	mediaConfirmMu sync.Mutex
	mediaConfirm   *mediaConfirmState
)

func confirmKindTitle(kind string) string {
	switch kind {
	case "sticker":
		return "Send this sticker?"
	case "gif":
		return "Send this GIF?"
	case "voice":
		return "Send this voice message?"
	}
	return "Send this?"
}

func (a *App) maybeConfirmMedia(kind string, on bool, send func()) {
	if !on {
		send()
		return
	}
	mediaConfirmMu.Lock()
	mediaConfirm = &mediaConfirmState{
		kind:      kind,
		send:      send,
		ok:        new(widget.Clickable),
		cancelBtn: new(widget.Clickable),
	}
	mediaConfirmMu.Unlock()
	a.invalidate()
}

func mediaConfirmActive() bool {
	mediaConfirmMu.Lock()
	defer mediaConfirmMu.Unlock()
	return mediaConfirm != nil
}

func (a *App) layoutMediaConfirm(gtx layout.Context) layout.Dimensions {
	mediaConfirmMu.Lock()
	mc := mediaConfirm
	mediaConfirmMu.Unlock()
	if mc == nil {
		return layout.Dimensions{}
	}
	if mc.ok.Clicked(gtx) {
		mediaConfirmMu.Lock()
		mediaConfirm = nil
		mediaConfirmMu.Unlock()
		go mc.send()
		a.invalidate()
		return layout.Dimensions{}
	}
	if mc.cancelBtn.Clicked(gtx) {
		mediaConfirmMu.Lock()
		mediaConfirm = nil
		mediaConfirmMu.Unlock()
		a.invalidate()
		return layout.Dimensions{}
	}

	paint.FillShape(gtx.Ops, color.NRGBA{R: 0, G: 0, B: 0, A: 0x66},
		clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Op())

	cardW := gtx.Dp(unit.Dp(340))
	if cardW > gtx.Constraints.Max.X {
		cardW = gtx.Constraints.Max.X
	}
	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = cardW
		return roundedFill(gtx, a.ui.p.Surface, 14, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(18)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.ui.H3(confirmKindTitle(mc.kind)).Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(13), "AyuGram send confirmation")
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								return layout.Dimensions{Size: image.Pt(gtx.Constraints.Max.X, 1)}
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									btn := material.Button(a.ui.Theme, mc.cancelBtn, "Cancel")
									btn.Background = a.ui.p.SurfaceHi
									btn.Color = a.ui.p.Text
									return btn.Layout(gtx)
								})
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								btn := material.Button(a.ui.Theme, mc.ok, "Send")
								btn.Background = a.ui.p.Accent
								return btn.Layout(gtx)
							}),
						)
					}),
				)
			})
		})
	})
}
