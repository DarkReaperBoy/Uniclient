package gui

import (
	"image"
	"image/draw"
	"os"

	"gioui.org/f32"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"

	"uniclient/engine"
)

func (a *App) chatAvatar(gtx layout.Context, c engine.ChatInfo, sizeDp unit.Dp, dot connDot) layout.Dimensions {
	a.mu.Lock()
	savedID := a.savedChatID[c.AccountID]
	cfg := a.cfg
	a.mu.Unlock()
	if savedID != "" && savedID == c.ChatID {
		return drawBookmarkAvatar(gtx, a.ui, sizeDp)
	}
	sizePx := gtx.Dp(sizeDp)
	radius := chatAvatarCornerRadius(cfg.AyuAvatarCorners, cfg.AyuSingleCornerRadius, c.IsForum, sizePx)
	var d layout.Dimensions
	if img := a.avatarImage(c.AvatarPath, ""); img != nil {
		d = avatarFromImage(gtx, a, img, sizeDp, dot, radius)
	} else {
		d = a.ui.AvatarShaped(gtx, c.Title, sizeDp, dot, radius)
	}
	if c.HasUnreadStory {
		paintAvatarRing(gtx, a.ui, d.Size.X)
	}
	return d
}

func (a *App) b64Avatar(gtx layout.Context, fallbackName, b64 string, sizeDp unit.Dp, dot connDot) layout.Dimensions {
	sizePx := gtx.Dp(sizeDp)
	if img := a.avatarImage("", b64); img != nil {
		return avatarFromImage(gtx, a, img, sizeDp, dot, a.ui.avatarRadiusPx(sizePx))
	}
	return a.ui.Avatar(gtx, fallbackName, sizeDp, dot)
}

func (a *App) accountAvatar(gtx layout.Context, acc engine.AccountInfo, sizeDp unit.Dp, dot connDot) layout.Dimensions {
	sizePx := gtx.Dp(sizeDp)
	if img := a.avatarImage(acc.AvatarPath, ""); img != nil {
		return avatarFromImage(gtx, a, img, sizeDp, dot, a.ui.avatarRadiusPx(sizePx))
	}
	return a.ui.Avatar(gtx, accountName(acc), sizeDp, dot)
}

func (a *App) avatarImage(path, b64 string) *image.RGBA {
	if path != "" {
		if _, err := os.Stat(path); err == nil {
			key := "file:" + path
			if img := mediaImgs.get(key); img != nil {
				return img
			}
			a.decodeFileAsync(path)
			return nil
		}
	}
	if b64 != "" {
		key := "thumb:" + b64
		if img := mediaImgs.get(key); img != nil {
			return img
		}
		a.decodeThumbAsync(key, b64)
	}
	return nil
}

func avatarFromImage(gtx layout.Context, a *App, img *image.RGBA, sizeDp unit.Dp, dot connDot, radiusPx int) layout.Dimensions {
	size := gtx.Dp(sizeDp)
	d := drawImageAvatarCover(gtx, img, size, radiusPx)
	if dot != dotNone {
		ov := op.Offset(image.Pt(d.Size.X-size/5, d.Size.Y-size/5)).Push(gtx.Ops)
		dd := size / 5
		paint.FillShape(gtx.Ops, a.ui.p.Background,
			clip.Ellipse{Min: image.Pt(0, 0), Max: image.Pt(dd, dd)}.Op(gtx.Ops))
		paint.FillShape(gtx.Ops, dot.color(),
			clip.Ellipse{Min: image.Pt(dd/6, dd/6), Max: image.Pt(dd+dd/6, dd+dd/6)}.Op(gtx.Ops))
		ov.Pop()
	}
	return d
}

func (a *App) mediaThumb(gtx layout.Context, b64 string, sizeDp unit.Dp) layout.Dimensions {
	size := gtx.Dp(sizeDp)
	if b64 == "" || size <= 0 {
		return layout.Dimensions{}
	}
	img := a.avatarImage("", b64)
	if img == nil {
		return layout.Dimensions{Size: image.Pt(size, size)}
	}
	return drawImageRRectCover(gtx, img, size)
}

func drawImageRRectCover(gtx layout.Context, img *image.RGBA, size int) layout.Dimensions {
	if size <= 0 || img == nil || img.Bounds().Empty() {
		return layout.Dimensions{}
	}
	crop := squareCrop(img)
	s := fitScale(crop.Bounds().Dx(), crop.Bounds().Dy(), size, size)

	clipStack := clip.UniformRRect(image.Rectangle{Max: image.Pt(size, size)}, size/6).Push(gtx.Ops)
	trStack := op.Affine(f32.AffineId().Scale(f32.Point{}, f32.Pt(s, s))).Push(gtx.Ops)
	imgOp := paint.NewImageOp(crop)
	imgOp.Filter = paint.FilterLinear
	imgOp.Add(gtx.Ops)
	paint.PaintOp{}.Add(gtx.Ops)
	trStack.Pop()
	clipStack.Pop()
	return layout.Dimensions{Size: image.Pt(size, size)}
}

func drawImageAvatarCover(gtx layout.Context, img *image.RGBA, size, radiusPx int) layout.Dimensions {
	if size <= 0 || img == nil || img.Bounds().Empty() {
		return layout.Dimensions{}
	}
	crop := squareCrop(img)
	s := fitScale(crop.Bounds().Dx(), crop.Bounds().Dy(), size, size)

	var clipStack clip.Stack
	switch {
	case radiusPx <= 0:
		clipStack = clip.Rect{Max: image.Pt(size, size)}.Push(gtx.Ops)
	case radiusPx >= size/2:
		clipStack = clip.Ellipse{Min: image.Pt(0, 0), Max: image.Pt(size, size)}.Push(gtx.Ops)
	default:
		clipStack = clip.UniformRRect(image.Rect(0, 0, size, size), radiusPx).Push(gtx.Ops)
	}
	trStack := op.Affine(f32.AffineId().Scale(f32.Point{}, f32.Pt(s, s))).Push(gtx.Ops)
	imgOp := paint.NewImageOp(crop)
	imgOp.Filter = paint.FilterLinear
	imgOp.Add(gtx.Ops)
	paint.PaintOp{}.Add(gtx.Ops)
	trStack.Pop()
	clipStack.Pop()
	return layout.Dimensions{Size: image.Pt(size, size)}
}

func squareCrop(img *image.RGBA) *image.RGBA {
	b := img.Bounds()
	side := b.Dx()
	if h := b.Dy(); h < side {
		side = h
	}
	x0 := b.Min.X + (b.Dx()-side)/2
	y0 := b.Min.Y + (b.Dy()-side)/2
	rect := image.Rect(x0, y0, x0+side, y0+side)
	sub, ok := img.SubImage(rect).(*image.RGBA)
	if ok {
		return sub
	}
	dst := image.NewRGBA(image.Rect(0, 0, side, side))
	draw.Draw(dst, dst.Bounds(), img, rect.Min, draw.Src)
	return dst
}
