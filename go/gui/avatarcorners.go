package gui

// Avatar Corners (AyuGram userpic styling, slice 215): AyuGramDesktop's
// Appearance → "Avatar Corners" — a 24-step slider (0 = square, 23 =
// circle, AyuGram kMaxAvatarCorners) that reshapes every userpic in the
// app, plus the "Single Corner Radius" toggle that makes forum avatars
// match (they otherwise keep tdesktop's native 30% rounding). Semantics
// pinned 1:1 against ayu/ui/ayu_userpic.cpp ComputeRadius,
// settings_appearance.cpp mapRadius and tdesktop's
// ForumUserpicRadiusMultiplier — see research/avatar_corners.md.

import (
	"fmt"
	"image"
	"strconv"
	"time"

	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// avatarCornersMax mirrors AyuUiSettings::kMaxAvatarCorners (23): the
// slider's top step renders a full circle.
const avatarCornersMax = 23

// avatarCornerRadiusPx is AyuGram's ComputeRadius: corners >= max →
// circle (size/2), <= 0 → square, else a linear share of the half-size.
func avatarCornerRadiusPx(corners, sizePx int) int {
	if corners >= avatarCornersMax {
		return sizePx / 2
	}
	if corners <= 0 {
		return 0
	}
	return int(float64(corners) / float64(avatarCornersMax) * float64(sizePx) / 2.0)
}

// avatarCornersLabel is the pill beside the slider (mapRadius): SQUARE /
// CIRCLE / the numeric step.
func avatarCornersLabel(corners int) string {
	if corners <= 0 {
		return "SQUARE"
	}
	if corners >= avatarCornersMax {
		return "CIRCLE"
	}
	return strconv.Itoa(corners)
}

// forumAvatarRadiusPx is tdesktop's native forum-userpic rounding: 30%
// of the avatar size (ForumUserpicRadiusMultiplier).
func forumAvatarRadiusPx(sizePx int) int {
	return int(float64(sizePx) * 0.3)
}

// chatAvatarCornerRadius resolves the corner radius for one chat's
// avatar (AyuGram ShouldOverrideShape): normal chats always take the
// slider shape; forums keep their native 30% rounding unless the Single
// Corner Radius toggle is on.
func chatAvatarCornerRadius(corners int, single, isForum bool, sizePx int) int {
	if isForum && !single {
		return forumAvatarRadiusPx(sizePx)
	}
	return avatarCornerRadiusPx(corners, sizePx)
}

// avatarShapeClip builds the avatar outline for a corner radius: 0 =
// square, size/2 = circle, else a rounded square (AyuGram PaintShape).
func avatarShapeClip(ops *op.Ops, size, radius int) clip.Op {
	switch {
	case radius <= 0:
		return clip.Rect{Max: image.Pt(size, size)}.Op()
	case radius >= size/2:
		return clip.Ellipse{Min: image.Pt(0, 0), Max: image.Pt(size, size)}.Op(ops)
	default:
		return clip.UniformRRect(image.Rect(0, 0, size, size), radius).Op(ops)
	}
}

// avatarCornersFromSlider maps the slider's 0..1 float onto the 24 steps
// (half-up rounding, tdesktop's pseudo-discrete slider).
func avatarCornersFromSlider(v float32) int {
	n := int(v*float32(avatarCornersMax) + 0.5)
	if n < 0 {
		n = 0
	}
	if n > avatarCornersMax {
		n = avatarCornersMax
	}
	return n
}

// avatarCornersPreviewState is the live-preview row's pure state: a
// representative chat row whose avatar follows the current corner count
// (AyuGram's avatar_corners_preview repaints the same way).
type avatarCornersPreviewState struct {
	title   string
	sub     string
	corners int
}

func newAvatarCornersPreview(corners int) avatarCornersPreviewState {
	return avatarCornersPreviewState{
		title:   "Uniclient Releases",
		sub:     "Better late than never",
		corners: corners,
	}
}

// radiusPx resolves the preview avatar's corner radius at a pixel size.
func (s avatarCornersPreviewState) radiusPx(sizePx int) int {
	return avatarCornerRadiusPx(s.corners, sizePx)
}

// --- settings section ----------------------------------------------------

var (
	avatarCornersSlider widget.Float
	avatarCornersSeeded bool
	avatarCornersTimer  *time.Timer
)

// seedAvatarCornersSlider syncs the slider from the effective config
// once per settings session.
func seedAvatarCornersSlider(corners int) {
	if avatarCornersSeeded {
		return
	}
	avatarCornersSeeded = true
	avatarCornersSlider.Value = float32(corners) / float32(avatarCornersMax)
}

// applyAvatarCornersUI applies one slider step live and schedules the
// debounced persist (a drag must not hammer the config store).
func (a *App) applyAvatarCornersUI(corners int) {
	a.ui.applyAvatarCorners(corners)
	a.invalidate()
	if avatarCornersTimer != nil {
		avatarCornersTimer.Stop()
	}
	avatarCornersTimer = time.AfterFunc(600*time.Millisecond, func() {
		v := clampAvatarCornersGUI(corners)
		c := engine.ConfigChanges{AyuAvatarCorners: &v}
		if err := a.eng.UpdateConfigFromBridge(&c); err != nil {
			a.setToast("Avatar corners: " + err.Error())
			return
		}
		a.refreshConfig()
	})
}

// clampAvatarCornersGUI bounds the slider output (defensive twin of
// utils.ClampAvatarCorners for the GUI fast path). Pure.
func clampAvatarCornersGUI(v int) int {
	if v < 0 {
		return 0
	}
	if v > avatarCornersMax {
		return avatarCornersMax
	}
	return v
}

// layoutAvatarCornersRow renders the slider row: title + sub + the
// SQUARE/CIRCLE/step pill, the 24-step track below.
func (a *App) layoutAvatarCornersRow(gtx layout.Context, f frame) layout.Dimensions {
	seedAvatarCornersSlider(f.cfg.AyuAvatarCorners)
	if avatarCornersSlider.Update(gtx) {
		a.applyAvatarCornersUI(avatarCornersFromSlider(avatarCornersSlider.Value))
	}
	return layout.Inset{Top: unit.Dp(10), Bottom: unit.Dp(6), Left: unit.Dp(16), Right: unit.Dp(16)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), "Avatar corners")
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(12), "Userpic shape everywhere, square to circle")
								lbl.Color = a.ui.p.TextFaint
								return lbl.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(12), avatarCornersLabel(avatarCornersFromSlider(avatarCornersSlider.Value)))
						lbl.Color = a.ui.p.TextDim
						return lbl.Layout(gtx)
					}),
				)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					sl := material.Slider(a.ui.Theme, &avatarCornersSlider)
					sl.Color = a.ui.p.Accent
					return sl.Layout(gtx)
				})
			}),
		)
	})
}

// layoutAvatarCornersPreview renders the live preview row: a chat row
// whose avatar follows the current slider value (AyuGram's
// avatar_corners_preview). It is a settings preview control, not app
// content — the row is the standard chat-row geometry.
func (a *App) layoutAvatarCornersPreview(gtx layout.Context, f frame) layout.Dimensions {
	st := newAvatarCornersPreview(avatarCornersFromSlider(avatarCornersSlider.Value))
	return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(10), Left: unit.Dp(16), Right: unit.Dp(16)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return a.ui.AvatarShaped(gtx, st.title, unit.Dp(46), dotNone, st.radiusPx(gtx.Dp(unit.Dp(46))))
				})
			}),
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(15), st.title)
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(12), fmt.Sprintf("%s · preview", st.sub))
						lbl.Color = a.ui.p.TextFaint
						return lbl.Layout(gtx)
					}),
				)
			}),
		)
	})
}
