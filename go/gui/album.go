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
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

func (a *App) albumCellClickable(key string) *widget.Clickable {
	if c, ok := a.wid.albumCellClicks[key]; ok {
		return c
	}
	if len(a.wid.albumCellClicks) > 512 {
		a.wid.albumCellClicks = make(map[string]*widget.Clickable)
	}
	c := new(widget.Clickable)
	a.wid.albumCellClicks[key] = c
	return c
}

func albumCells(n, W, H, gap int) []image.Rectangle {
	if n <= 0 || W <= 0 || H <= 0 {
		return nil
	}
	if n > 4 {
		n = 4
	}
	halfW := (W - gap) / 2
	halfH := (H - gap) / 2
	switch n {
	case 1:
		return []image.Rectangle{image.Rect(0, 0, W, H)}
	case 2:
		return []image.Rectangle{
			image.Rect(0, 0, halfW, H),
			image.Rect(halfW+gap, 0, W, H),
		}
	case 3:
		return []image.Rectangle{
			image.Rect(0, 0, halfW, H),
			image.Rect(halfW+gap, 0, W, halfH),
			image.Rect(halfW+gap, halfH+gap, W, H),
		}
	default:
		return []image.Rectangle{
			image.Rect(0, 0, halfW, halfH),
			image.Rect(halfW+gap, 0, W, halfH),
			image.Rect(0, halfH+gap, halfW, H),
			image.Rect(halfW+gap, halfH+gap, W, H),
		}
	}
}

func albumOverCount(n int) int {
	if n <= 4 {
		return 0
	}
	return n - 4
}

func albumCaption(messages []engine.CachedMessage, idx []int) string {
	for _, i := range idx {
		if messages[i].ContentText != "" {
			return messages[i].ContentText
		}
	}
	return ""
}

func isAlbumMedia(m *engine.CachedMessage) bool {
	if !m.HasMedia || m.GroupedID == "" {
		return false
	}
	switch m.MediaType {
	case engine.MediaImage, engine.MediaGIF, engine.MediaVideo, engine.MediaVideoNote:
		return true
	}
	return false
}

func (a *App) albumRow(gtx layout.Context, f frame, messages []engine.CachedMessage, idx []int) layout.Dimensions {
	first := &messages[idx[0]]
	out := first.IsOutgoing

	maxW := gtx.Constraints.Max.X * 3 / 4
	if maxW > gtx.Dp(unit.Dp(300)) {
		maxW = gtx.Dp(unit.Dp(300))
	}
	pad := gtx.Constraints.Max.X - maxW

	boxW := maxW - gtx.Dp(unit.Dp(20))
	aspect := 4.0 / 3.0
	if first.MediaWidth != 0 && first.MediaHeight != 0 {
		aspect = float64(first.MediaWidth) / float64(first.MediaHeight)
		if aspect < 0.5 {
			aspect = 0.5
		}
		if aspect > 3 {
			aspect = 3
		}
	}
	boxH := int(float64(boxW)/aspect + 0.5)
	if boxH < gtx.Dp(unit.Dp(200)) {
		boxH = gtx.Dp(unit.Dp(200))
	}
	if boxH > gtx.Dp(unit.Dp(380)) {
		boxH = gtx.Dp(unit.Dp(380))
	}
	gap := gtx.Dp(unit.Dp(3))
	cells := albumCells(len(idx), boxW, boxH, gap)
	over := albumOverCount(len(idx))

	bubble := func(gtx layout.Context) layout.Dimensions {
		bg := a.ui.p.BubbleIn
		if out {
			bg = a.ui.p.AccentDim
		}
		return roundedFill(gtx, bg, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				caption := albumCaption(messages, idx)
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Stack{}.Layout(gtx,
							layout.Expanded(func(gtx layout.Context) layout.Dimensions {
								clipStack := clip.Rect{Max: image.Pt(boxW, boxH)}.Push(gtx.Ops)
								for ci := range cells {
									a.albumCell(gtx, f, &messages[idx[ci]], cells[ci], over, ci == len(cells)-1)
								}
								clipStack.Pop()
								return layout.Dimensions{Size: image.Pt(boxW, boxH)}
							}),
							layout.Stacked(func(gtx layout.Context) layout.Dimensions {
								return layout.Dimensions{Size: image.Pt(boxW, boxH)}
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if caption == "" {
							return layout.Dimensions{}
						}
						return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(15), caption)
							lbl.MaxLines = 30
							if out {
								lbl.Color = a.ui.p.Text
							}
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if len(first.Reactions) == 0 {
							return layout.Dimensions{}
						}
						return a.reactionStrip(gtx, f, first)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								meta := msgTimeLabel(first.Timestamp)
								if first.EditedAt != 0 {
									meta = "edited " + msgTimeLabel(first.EditedAt)
								}
								lbl := a.ui.Dim(unit.Sp(10), meta)
								lbl.Color = a.ui.p.TextFaint
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								if !out {
									return layout.Dimensions{}
								}
								return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return a.statusTicks(gtx, first.Status, f)
								})
							}),
						)
					}),
				)
			})
		})
	}

	if out {
		return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(pad)}.Layout(gtx, bubble)
	}
	return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Right: unit.Dp(pad)}.Layout(gtx, bubble)
}

func (a *App) albumCell(gtx layout.Context, f frame, m *engine.CachedMessage, cell image.Rectangle, over int, last bool) layout.Dimensions {
	st, live := f.downloads[dlKey(m.AccountID, m.ChatID, m.MsgID, 0)]
	state := m.MediaDownloadState
	if live {
		state = st.state
	}

	btn := a.albumCellClickable(m.MsgID)
	if btn.Clicked(gtx) {
		a.actMedia(gtx, m, state)
	}

	w, h := cell.Dx(), cell.Dy()
	defer op.Offset(cell.Min).Push(gtx.Ops).Pop()
	cgtx := gtx
	cgtx.Constraints = layout.Constraints{Max: image.Pt(w, h), Min: image.Pt(w, h)}

	bl := material.ButtonLayout(a.ui.Theme, btn)
	bl.Background = color.NRGBA{}
	bl.CornerRadius = 5
	return bl.Layout(cgtx, func(gtx layout.Context) layout.Dimensions {
		var img *image.RGBA
		if state == engine.DownloadComplete && m.MediaLocalPath != "" && isDisplayableImage(m.MediaLocalPath) {
			key := "file:" + m.MediaLocalPath
			if img = mediaImgs.get(key); img == nil {
				a.decodeFileAsync(m.MediaLocalPath)
			}
		}
		if img == nil && m.MediaThumbB64 != "" {
			key := "thumb:" + m.MediaThumbB64
			if img = mediaImgs.get(key); img == nil {
				a.decodeThumbAsync(key, m.MediaThumbB64)
			}
		}

		clipStack := clip.RRect{Rect: image.Rect(0, 0, w, h), NE: 5, NW: 5, SE: 5, SW: 5}.Push(gtx.Ops)
		if img != nil {
			drawImageCover(gtx, img, w, h)
		} else {
			defer clip.Rect{Max: image.Pt(w, h)}.Push(gtx.Ops).Pop()
			paint.Fill(gtx.Ops, a.ui.p.SurfaceHi)
		}
		clipStack.Pop()

		if m.MediaType == engine.MediaVideo || m.MediaType == engine.MediaVideoNote {
			d := gtx.Dp(unit.Dp(40))
			dx := (w - d) / 2
			dy := (h - d) / 2
			off := op.Offset(image.Pt(dx, dy)).Push(gtx.Ops)
			drawPlayBadge(gtx, d)
			off.Pop()
		}

		if live && state == engine.DownloadInProgress {
			defer clip.Rect{Max: image.Pt(w, h)}.Push(gtx.Ops).Pop()
			paint.Fill(gtx.Ops, translucent(0x42))
		}

		if last && over > 0 {
			defer clip.Rect{Max: image.Pt(w, h)}.Push(gtx.Ops).Pop()
			paint.Fill(gtx.Ops, translucent(0x66))
			lbl := a.ui.Dim(unit.Sp(16), "+"+itoa(over))
			lbl.Color = a.ui.p.Text
			return centerLayout(gtx, lbl.Layout)
		}
		return layout.Dimensions{Size: image.Pt(w, h)}
	})
}

func translucent(alpha byte) color.NRGBA {
	return color.NRGBA{A: alpha}
}

func drawImageCover(gtx layout.Context, img *image.RGBA, w, h int) {
	w0, h0 := img.Bounds().Dx(), img.Bounds().Dy()
	if w0 <= 0 || h0 <= 0 || w <= 0 || h <= 0 {
		return
	}
	sx := float32(w) / float32(w0)
	sy := float32(h) / float32(h0)
	s := sx
	if sy > s {
		s = sy
	}
	sw, sh := float32(w0)*s, float32(h0)*s
	ox := (float32(w) - sw) / 2
	oy := (float32(h) - sh) / 2

	trStack := op.Affine(f32.AffineId().
		Offset(f32.Pt(ox, oy)).
		Scale(f32.Point{}, f32.Pt(s, s))).Push(gtx.Ops)
	imgOp := paint.NewImageOp(img)
	imgOp.Filter = paint.FilterLinear
	imgOp.Add(gtx.Ops)
	paint.PaintOp{}.Add(gtx.Ops)
	trStack.Pop()
}
