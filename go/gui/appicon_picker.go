package gui

// appicon_picker.go — slice 170: the Ayu · App icon settings section —
// a 4-column preview grid (AyuGram icon_picker.cpp: kColumns = 4),
// apply-on-click, selection ring like the accent swatches. Only offered
// where the icon can actually be re-applied at runtime (linux+windows);
// the web/Android builds hide the whole section (§1.10).

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

	"uniclient/engine"
)

// picker widget state (package-level, the settings-page convention).
var (
	appIconCells    []widget.Clickable
	appIconPreviews = map[string]*image.RGBA{} // per-set cached preview
)

// layoutAppIconPicker renders the icon-set grid. Previews render once
// per set (cached); the selected cell carries the accent ring.
func (a *App) layoutAppIconPicker(gtx layout.Context, f frame) layout.Dimensions {
	sets := appIconSets()
	growClickables(&appIconCells, len(sets))

	// Click handling first (the settings-row convention).
	for i := range sets {
		if appIconCells[i].Clicked(gtx) {
			id := sets[i].ID
			if id != f.cfg.AyuAppIcon {
				a.applyAppIconChoice(id)
			}
		}
	}

	return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(12), Left: unit.Dp(16), Right: unit.Dp(16)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		sz := gtx.Dp(unit.Dp(52))
		rows := appIconGridRows(len(sets))
		var children []layout.FlexChild
		for r := 0; r < rows; r++ {
			r := r
			cols := appIconGridColumns
			if rem := len(sets) - r*cols; rem < cols {
				cols = rem
			}
			var rowChildren []layout.FlexChild
			for c := 0; c < cols; c++ {
				i := r*appIconGridColumns + c
				set := sets[i]
				rowChildren = append(rowChildren, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return appIconCellLayout(a, gtx, &appIconCells[i], set, f.cfg, sz)
				}))
			}
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, rowChildren...)
			}))
		}
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
	})
}

// appIconCellLayout draws one preview tile: the set's rendered icon at
// 52dp with the accent selection ring when active, plus the label
// caption below (AyuGram shows a bare grid; the labels keep the choice
// nameable for accessibility).
func appIconCellLayout(a *App, gtx layout.Context, btn *widget.Clickable, set appIconSet, cfg cfgSnapshot, sz int) layout.Dimensions {
	active := appIconIsSelected(set, cfg)
	preview := appIconPreview(set)

	return layout.Inset{Right: unit.Dp(12), Bottom: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				// Hit area + ripple tile.
				return btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					gtx.Constraints.Max = image.Pt(sz, sz)
					gtx.Constraints.Min = image.Pt(sz, sz)

					// Icon: painted scaled to the tile (linear filter).
					imgSz := preview.Bounds().Dx()
					s := float32(sz) / float32(imgSz)
					trStack := op.Affine(f32.AffineId().Scale(f32.Point{}, f32.Pt(s, s))).Push(gtx.Ops)
					imgOp := paint.NewImageOp(preview)
					imgOp.Filter = paint.FilterLinear
					imgOp.Add(gtx.Ops)
					paint.PaintOp{}.Add(gtx.Ops)
					trStack.Pop()

					if active {
						pad := gtx.Dp(unit.Dp(3))
						ring := clip.Stroke{
							Width: float32(gtx.Dp(unit.Dp(2))),
							Path: clip.RRect{
								Rect: image.Rect(-pad, -pad, sz+pad, sz+pad),
								NE:   sz / 4, NW: sz / 4, SE: sz / 4, SW: sz / 4,
							}.Path(gtx.Ops),
						}.Op()
						paint.FillShape(gtx.Ops, a.ui.p.Accent, ring)
					}
					return layout.Dimensions{Size: image.Pt(sz, sz)}
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(10), set.Label)
				return lbl.Layout(gtx)
			}),
		)
	})
}

// appIconPreview returns (and caches) the per-set preview image. The
// default set previews with the standard Material accent stand-in so
// the swatch is stable regardless of theme state.
func appIconPreview(set appIconSet) *image.RGBA {
	if img, ok := appIconPreviews[set.ID]; ok {
		return img
	}
	tile := set.Tile
	if set.Tile == liveAccentTile {
		tile = color.NRGBA{R: 0x54, G: 0xA8, B: 0xF0, A: 0xFF}
	}
	rgba := imageToRGBA(renderAppIconRGBA(appIconSet{ID: set.ID, Label: set.Label, Tile: tile, Mark: set.Mark}, 104))
	appIconPreviews[set.ID] = rgba
	return rgba
}

// applyAppIconChoice persists the choice and lets refreshConfig's hook
// re-apply the runtime icon (engine first, then UI refresh).
func (a *App) applyAppIconChoice(id string) {
	go func() {
		c := engine.ConfigChanges{AyuAppIcon: &id}
		if err := a.eng.UpdateConfigFromBridge(&c); err != nil {
			a.setToast("App icon: " + err.Error())
			return
		}
		a.refreshConfig()
	}()
}
