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

// Real image avatars (AyuGram parity §2 "Chat row: image avatar"): render
// the downloaded userpic (ChatInfo.AvatarPath, engine avatars pipeline) or an
// inline base64 thumb (member/profile lists) as a circular avatar, falling
// back to the letter avatar. Decoding goes through the shared media image
// cache; the frame only looks up and kicks async decodes.

// chatAvatar renders the chat's real userpic when available (letter
// fallback), with the optional connection dot.
func (a *App) chatAvatar(gtx layout.Context, c engine.ChatInfo, sizeDp unit.Dp, dot connDot) layout.Dimensions {
	var d layout.Dimensions
	if img := a.avatarImage(c.AvatarPath, ""); img != nil {
		d = avatarFromImage(gtx, a, img, sizeDp, dot)
	} else {
		d = a.ui.Avatar(gtx, c.Title, sizeDp, dot)
	}
	if c.HasUnreadStory {
		paintAvatarRing(gtx, a.ui, d.Size.X) // unread-stories ring (AyuGram)
	}
	return d
}

// b64Avatar renders a base64 thumbnail avatar (member rows, profiles).
func (a *App) b64Avatar(gtx layout.Context, fallbackName, b64 string, sizeDp unit.Dp, dot connDot) layout.Dimensions {
	if img := a.avatarImage("", b64); img != nil {
		return avatarFromImage(gtx, a, img, sizeDp, dot)
	}
	return a.ui.Avatar(gtx, fallbackName, sizeDp, dot)
}

// accountAvatar renders an account's userpic when its path is populated.
func (a *App) accountAvatar(gtx layout.Context, acc engine.AccountInfo, sizeDp unit.Dp, dot connDot) layout.Dimensions {
	if img := a.avatarImage(acc.AvatarPath, ""); img != nil {
		return avatarFromImage(gtx, a, img, sizeDp, dot)
	}
	return a.ui.Avatar(gtx, accountName(acc), sizeDp, dot)
}

// avatarImage resolves an avatar source to a decoded image: local file first
// (engine saves userpics as jpg), then base64 thumb. Kicks async decodes for
// missing entries; nil when nothing is (yet) available.
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

// avatarFromImage paints img as a circle avatar (center-crop cover fit) with
// the optional status dot — the image twin of UI.Avatar.
func avatarFromImage(gtx layout.Context, a *App, img *image.RGBA, sizeDp unit.Dp, dot connDot) layout.Dimensions {
	size := gtx.Dp(sizeDp)
	d := drawImageEllipseCover(gtx, img, size)
	if dot != dotNone {
		// Overlay the status dot in the bottom-right corner.
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

// mediaThumb paints a small rounded-square media preview (chat-row thumbs).
func (a *App) mediaThumb(gtx layout.Context, b64 string, sizeDp unit.Dp) layout.Dimensions {
	size := gtx.Dp(sizeDp)
	if b64 == "" || size <= 0 {
		return layout.Dimensions{}
	}
	img := a.avatarImage("", b64)
	if img == nil {
		// Async decode in flight: reserve the box so rows don't jump.
		return layout.Dimensions{Size: image.Pt(size, size)}
	}
	return drawImageRRectCover(gtx, img, size)
}

// drawImageRRectCover center-crops img to a square and paints it clipped to
// a rounded rect (cover fit).
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

// drawImageEllipseCover center-crops img to a square and paints it clipped
// to a circle of the given pixel size (cover, not fit — no gaps).
func drawImageEllipseCover(gtx layout.Context, img *image.RGBA, size int) layout.Dimensions {
	if size <= 0 || img == nil || img.Bounds().Empty() {
		return layout.Dimensions{}
	}
	crop := squareCrop(img)
	s := fitScale(crop.Bounds().Dx(), crop.Bounds().Dy(), size, size)

	clipStack := clip.Ellipse{Min: image.Pt(0, 0), Max: image.Pt(size, size)}.Push(gtx.Ops)
	trStack := op.Affine(f32.AffineId().Scale(f32.Point{}, f32.Pt(s, s))).Push(gtx.Ops)
	imgOp := paint.NewImageOp(crop)
	imgOp.Filter = paint.FilterLinear
	imgOp.Add(gtx.Ops)
	paint.PaintOp{}.Add(gtx.Ops)
	trStack.Pop()
	clipStack.Pop()
	return layout.Dimensions{Size: image.Pt(size, size)}
}

// squareCrop center-crops an RGBA to its largest centered square.
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
