package gui

// Layout tweak sliders (AyuGram appearance, matrix row 246, slice 93):
// bubble corner radius (0..18 dp, supersedes the slice-82 rounded/square
// toggle) and the bubble "wide multiplier" (0.70..1.00 of the chat pane).
// Both apply live to the UI and persist debounced (600 ms coalesce) so a
// drag does not hammer the config store.

import (
	"fmt"
	"time"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
	"uniclient/utils"
)

var (
	appearanceRadiusSlider widget.Float
	appearanceWideSlider   widget.Float
	layoutSliderSeeded     bool
	layoutPersistTimer     *time.Timer
)

// bubbleRadiusSliderLabel formats the radius row value. Pure.
func bubbleRadiusSliderLabel(dp int) string {
	return fmt.Sprintf("%d dp", dp)
}

// wideSliderLabel formats the width row value. Pure.
func wideSliderLabel(w float64) string {
	return fmt.Sprintf("%d%%", int(w*100+0.5))
}

// seedLayoutSliders syncs both sliders from the frame's effective config
// values once per settings session (GUI loop).
func seedLayoutSliders(dp int, wide float64) {
	if layoutSliderSeeded {
		return
	}
	layoutSliderSeeded = true
	appearanceRadiusSlider.Value = float32(dp) / 18
	appearanceWideSlider.Value = float32((wide - 0.70) / 0.30)
}

// applyLayoutTweaksUI applies one slider live (radiusDp < 0 or wide <= 0
// = "leave unchanged") and schedules the debounced persist.
func (a *App) applyLayoutTweaksUI(radiusDp int, wide float64) {
	r := a.ui.bubbleRadiusDp
	w := a.ui.wideMultiplier()
	if radiusDp >= 0 {
		r = utils.ClampBubbleRadius(radiusDp)
	}
	if wide > 0 {
		w = utils.ClampWideMultiplier(wide)
	}
	a.ui.applyLayoutTweaks(r, w)
	a.scheduleLayoutPersist(r, w)
	a.invalidate()
}

// scheduleLayoutPersist coalesces slider drags into one config write.
func (a *App) scheduleLayoutPersist(radiusDp int, wide float64) {
	if layoutPersistTimer != nil {
		layoutPersistTimer.Stop()
	}
	layoutPersistTimer = time.AfterFunc(600*time.Millisecond, func() {
		r := utils.ClampBubbleRadius(radiusDp)
		w := utils.ClampWideMultiplier(wide)
		c := engine.ConfigChanges{BubbleRadius: &r, WideMultiplier: &w}
		if err := a.eng.UpdateConfigFromBridge(&c); err != nil {
			a.setToast("Layout: " + err.Error())
			return
		}
		a.refreshConfig()
	})
}

// layoutSliderRow renders one labeled slider: title + sub on the left,
// the value on the right, the track below. toVal maps the 0..1 float to
// the setting; apply runs the live change (and schedules the persist).
// Seeding happens once per settings session via seedLayoutSliders.
func layoutSliderRow[T any](a *App, gtx layout.Context, f frame, fl *widget.Float, title, sub string,
	label func(T) string, toVal func(float32) T, apply func(T)) layout.Dimensions {
	seedLayoutSliders(f.cfg.BubbleRadius, f.cfg.WideMult)
	if fl.Update(gtx) {
		apply(toVal(fl.Value))
	}
	return layout.Inset{Top: unit.Dp(10), Bottom: unit.Dp(6), Left: unit.Dp(16), Right: unit.Dp(16)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), title)
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(12), sub)
								lbl.Color = a.ui.p.TextFaint
								return lbl.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(12), label(toVal(fl.Value)))
						lbl.Color = a.ui.p.TextDim
						return lbl.Layout(gtx)
					}),
				)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					sl := material.Slider(a.ui.Theme, fl)
					sl.Color = a.ui.p.Accent
					return sl.Layout(gtx)
				})
			}),
		)
	})
}
