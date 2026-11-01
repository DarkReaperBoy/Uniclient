package gui

import (
	"image"
	"image/color"
	"time"

	"gioui.org/f32"
	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

type viewerState struct {
	accountID string
	chatID    string
	chatTitle string
	kind      string
	anchor    string
	items     []engine.SharedMediaItem
	index     int
	loaded    bool
	deleting  bool
}

var (
	viewerKeyTag = new(struct{})
	viewerBgTag  = new(struct{})
	viewerImgTag = new(struct{})
)

func stepViewerIndex(i, n, delta int) int {
	if n <= 0 {
		return 0
	}
	i += delta
	if i < 0 {
		return 0
	}
	if i > n-1 {
		return n - 1
	}
	return i
}

func viewerZoomAfter(z float32) float32 {
	if z > 1.01 {
		return 1
	}
	return 2.5
}

func clampPanAxis(pan, scaled, box float32) float32 {
	lim := (scaled - box) / 2
	if lim < 0 {
		return 0
	}
	if pan > lim {
		return lim
	}
	if pan < -lim {
		return -lim
	}
	return pan
}

func panAfterZoom(pan, click, center, k float32) float32 {
	return pan*k + (click-center)*(1-k)
}

func findViewerItem(items []engine.SharedMediaItem, msgID string) int {
	for i, it := range items {
		if it.MsgID == msgID {
			return i
		}
	}
	return -1
}

func mergeViewerItems(items []engine.SharedMediaItem, synth *engine.SharedMediaItem, anchor string) ([]engine.SharedMediaItem, int) {
	if i := findViewerItem(items, anchor); i >= 0 {
		return items, i
	}
	if synth == nil {
		return items, 0
	}
	out := make([]engine.SharedMediaItem, 0, len(items)+1)
	out = append(out, *synth)
	out = append(out, items...)
	return out, 0
}

func synthItemFromMsg(m *engine.CachedMessage) engine.SharedMediaItem {
	return engine.SharedMediaItem{
		MsgID:      m.MsgID,
		Timestamp:  m.Timestamp,
		MediaType:  m.MediaType,
		FileName:   m.MediaFileName,
		MimeType:   m.MediaMimeType,
		FileSize:   m.MediaFileSize,
		ThumbB64:   m.MediaThumbB64,
		LocalPath:  m.MediaLocalPath,
		Width:      m.MediaWidth,
		Height:     m.MediaHeight,
		Duration:   m.MediaDuration,
		SenderName: m.SenderName,
		Text:       m.ContentText,
		IsOutgoing: m.IsOutgoing,
	}
}

func viewerKindFor(mt int) string {
	switch mt {
	case engine.MediaImage, engine.MediaGIF, engine.MediaSticker:
		return "image"
	case engine.MediaVideo, engine.MediaVideoNote:
		return "video"
	default:
		return "file"
	}
}

func fmtViewerDate(ms int64) string {
	if ms <= 0 {
		return ""
	}
	return time.UnixMilli(ms).Format("2 Jan 2006, 15:04")
}

func viewerIsVideo(it engine.SharedMediaItem) bool {
	return it.MediaType == engine.MediaVideo || it.MediaType == engine.MediaVideoNote
}

func (a *App) openViewerFromMsg(gtx layout.Context, m *engine.CachedMessage) {
	kind := viewerKindFor(m.MediaType)
	if kind == "file" {
		return
	}
	title := a.chatTitleFor(chatKey{AccountID: m.AccountID, ChatID: m.ChatID})
	synth := synthItemFromMsg(m)
	v := &viewerState{
		accountID: m.AccountID,
		chatID:    m.ChatID,
		chatTitle: title,
		kind:      kind,
		anchor:    m.MsgID,
		items:     []engine.SharedMediaItem{synth},
	}
	a.mu.Lock()
	a.viewer = v
	a.mu.Unlock()
	a.viewerResetGesture()
	if gtx.Ops != nil {
		gtx.Execute(key.FocusCmd{Tag: nil})
	}
	a.invalidate()

	msg := *m
	go func() {
		items, err := a.eng.GetSharedMedia(msg.AccountID, msg.ChatID, kind, 120, 0, "")
		if err != nil {
			return
		}
		a.mu.Lock()
		if cur := a.viewer; cur != nil && cur.accountID == msg.AccountID && cur.chatID == msg.ChatID && cur.kind == kind {
			cur.items, cur.index = mergeViewerItems(items, &synth, msg.MsgID)
			cur.loaded = true
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

func (a *App) openViewerAt(k chatKey, title, kind, msgID string) {
	v := &viewerState{
		accountID: k.AccountID,
		chatID:    k.ChatID,
		chatTitle: title,
		kind:      kind,
		anchor:    msgID,
	}
	a.mu.Lock()
	a.viewer = v
	a.mu.Unlock()
	a.viewerResetGesture()
	go func() {
		items, err := a.eng.GetSharedMedia(k.AccountID, k.ChatID, kind, 120, 0, "")
		if err != nil {
			return
		}
		a.mu.Lock()
		if cur := a.viewer; cur != nil && cur.accountID == k.AccountID && cur.chatID == k.ChatID && cur.kind == kind {
			cur.items = items
			if i := findViewerItem(items, msgID); i >= 0 {
				cur.index = i
			}
			cur.loaded = true
		}
		a.mu.Unlock()
		a.invalidate()
	}()
	a.invalidate()
}

func (a *App) closeViewer() {
	a.mu.Lock()
	v := a.viewer
	a.viewer = nil
	a.mu.Unlock()
	if v != nil && v.index >= 0 && v.index < len(v.items) {
		msgID := v.items[v.index].MsgID
		h264Players.reset(msgID)
		a.videoAudioPause(msgID)
	}
	a.viewerResetGesture()
	a.invalidate()
}

func (a *App) viewerStep(delta int) {
	a.mu.Lock()
	if v := a.viewer; v != nil {
		v.index = stepViewerIndex(v.index, len(v.items), delta)
	}
	a.mu.Unlock()
	a.viewerResetGesture()
	a.invalidate()
}

func (a *App) viewerSetIndex(i int) {
	a.mu.Lock()
	if v := a.viewer; v != nil && i >= 0 && i < len(v.items) {
		v.index = i
	}
	a.mu.Unlock()
	a.viewerResetGesture()
	a.invalidate()
}

func (a *App) viewerResetGesture() {
	a.mvZoom = 1
	a.mvPan = f32.Point{}
	a.mvLastPressAt = time.Time{}
	a.mvScaledW, a.mvScaledH = 0, 0
}

func (a *App) chatTitleFor(k chatKey) string {
	a.mu.Lock()
	defer a.mu.Unlock()
	for _, c := range a.chats {
		if c.AccountID == k.AccountID && c.ChatID == k.ChatID {
			return c.Title
		}
	}
	return ""
}

func (a *App) viewerCurrent(f frame) (engine.SharedMediaItem, int, bool) {
	v := f.viewer
	if v == nil || len(v.items) == 0 || v.index < 0 || v.index >= len(v.items) {
		return engine.SharedMediaItem{}, 0, false
	}
	return v.items[v.index], v.index, true
}

func (a *App) layoutMediaView(gtx layout.Context, f frame) layout.Dimensions {
	v := f.viewer

	gtx.Execute(key.FocusCmd{Tag: nil})

	{
		stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
		event.Op(gtx.Ops, viewerKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(
			key.Filter{Name: key.NameEscape},
			key.Filter{Name: key.NameLeftArrow},
			key.Filter{Name: key.NameRightArrow},
		)
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			switch ke.Name {
			case key.NameEscape:
				if v.deleting {
					a.viewerCancelDelete()
				} else {
					a.closeViewer()
				}
			case key.NameLeftArrow:
				a.viewerStep(-1)
			case key.NameRightArrow:
				a.viewerStep(1)
			}
		}
	}

	{
		stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
		event.Op(gtx.Ops, viewerBgTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(pointer.Filter{Target: viewerBgTag, Kinds: pointer.Press})
		if !ok {
			break
		}
		if pe, is := ev.(pointer.Event); is && pe.Kind == pointer.Press {
			if v.deleting {
				a.viewerCancelDelete()
			} else {
				a.closeViewer()
			}
		}
	}

	paintFill(gtx.Ops, color.NRGBA{R: 0, G: 0, B: 0, A: 0xF0}, gtx.Constraints.Max)

	body := layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.viewerTopBar(gtx, f)
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			return a.viewerCenter(gtx, f)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.viewerCaption(gtx, f)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.viewerVideoBar(gtx, f)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.viewerFilmstrip(gtx, f)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.viewerProgress(gtx, f)
		}),
	)
	if v.deleting {
		a.viewerDeleteDialog(gtx, f)
	}
	return body
}

func (a *App) viewerTopBar(gtx layout.Context, f frame) layout.Dimensions {
	v := f.viewer
	it, _, ok := a.viewerCurrent(f)

	if a.wid.viewerCloseBtn.Clicked(gtx) {
		a.closeViewer()
	}
	if a.wid.viewerSaveBtn.Clicked(gtx) {
		if ok {
			a.viewerSave(v, it)
		}
	}
	if a.wid.viewerShareBtn.Clicked(gtx) {
		if ok {
			a.viewerShare(v, it)
		}
	}
	if a.wid.viewerFolderBtn.Clicked(gtx) {
		if ok && it.LocalPath != "" {
			a.revealMedia(it.LocalPath)
		}
	}
	if a.wid.viewerPipBtn.Clicked(gtx) {
		if ok && pipEligible(it) {
			a.viewerPopOut(gtx, it)
		}
	}
	if a.wid.viewerDelBtn.Clicked(gtx) {
		a.mu.Lock()
		if a.viewer != nil {
			a.viewer.deleting = true
		}
		a.mu.Unlock()
		a.invalidate()
	}

	return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(8), Right: unit.Dp(12)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.IconButton(&a.wid.viewerCloseBtn, iconContentClear, "Close")
					btn.Color = a.ui.p.Text
					btn.Background = a.ui.p.SurfaceHi
					return btn.Layout(gtx)
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Left: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								title := v.chatTitle
								if title == "" {
									title = "Media"
								}
								lbl := a.ui.Dim(unit.Sp(16), title)
								lbl.Color = a.ui.p.Text
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								date := "—"
								if ok && fmtViewerDate(it.Timestamp) != "" {
									date = fmtViewerDate(it.Timestamp)
								}
								lbl := a.ui.Dim(unit.Sp(11), date)
								lbl.Color = a.ui.p.TextDim
								return lbl.Layout(gtx)
							}),
						)
					})
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if !ok || it.LocalPath == "" {
						return layout.Dimensions{}
					}
					return a.viewerIconBtn(gtx, &a.wid.viewerFolderBtn, iconFileFolder, "Show in folder")
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.viewerIconBtn(gtx, &a.wid.viewerSaveBtn, iconFileDownload, "Save")
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.viewerIconBtn(gtx, &a.wid.viewerShareBtn, iconSocialShare, "Share")
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if !ok || !pipEligible(it) {
						return layout.Dimensions{}
					}
					return a.viewerIconBtn(gtx, &a.wid.viewerPipBtn, iconActionPictureInPicture, "Picture in picture")
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.viewerIconBtn(gtx, &a.wid.viewerDelBtn, iconActionDelete, "Delete")
				}),
			)
		})
}

func (a *App) viewerIconBtn(gtx layout.Context, btn *widget.Clickable, icon *widget.Icon, desc string) layout.Dimensions {
	b := a.ui.IconButton(btn, icon, desc)
	b.Color = a.ui.p.Text
	b.Background = a.ui.p.SurfaceHi
	return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, b.Layout)
}

func (a *App) viewerCenter(gtx layout.Context, f frame) layout.Dimensions {
	it, _, ok := a.viewerCurrent(f)
	if a.wid.viewerPrevBtn.Clicked(gtx) {
		a.viewerStep(-1)
	}
	if a.wid.viewerNextBtn.Clicked(gtx) {
		a.viewerStep(1)
	}
	if a.wid.viewerPlayBtn.Clicked(gtx) && ok {
		a.viewerPlay(f.viewer, it)
	}

	return layout.Stack{}.Layout(gtx,
		layout.Expanded(func(gtx layout.Context) layout.Dimensions {
			stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
			event.Op(gtx.Ops, viewerImgTag)
			stack.Pop()
			a.processViewerImageEvents(gtx, f)
			return layout.Dimensions{Size: gtx.Constraints.Min}
		}),
		layout.Stacked(func(gtx layout.Context) layout.Dimensions {
			return a.viewerImage(gtx, f, it, ok)
		}),
		layout.Stacked(func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					return a.viewerChevron(gtx, &a.wid.viewerPrevBtn, iconNavChevronLeft, "Previous")
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					return a.viewerChevron(gtx, &a.wid.viewerNextBtn, iconNavChevronRight, "Next")
				}),
			)
		}),
	)
}

func (a *App) viewerChevron(gtx layout.Context, btn *widget.Clickable, icon *widget.Icon, desc string) layout.Dimensions {
	return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
		b := a.ui.IconButton(btn, icon, desc)
		b.Color = a.ui.p.Text
		b.Background = color.NRGBA{A: 0x42}
		return b.Layout(gtx)
	})
}

func (a *App) viewerImage(gtx layout.Context, f frame, it engine.SharedMediaItem, ok bool) layout.Dimensions {
	boxW := gtx.Constraints.Max.X
	boxH := gtx.Constraints.Max.Y
	if boxW > gtx.Dp(unit.Dp(920)) {
		boxW = gtx.Dp(unit.Dp(920))
	}
	if boxW <= 0 || boxH <= 0 {
		return layout.Dimensions{}
	}
	a.mvBoxW, a.mvBoxH = boxW, boxH

	var img *image.RGBA
	if ok {
		if it.LocalPath != "" && isDisplayableImage(it.LocalPath) {
			k := "file:" + it.LocalPath
			if img = mediaImgs.get(k); img == nil {
				a.decodeFileAsync(it.LocalPath)
			}
		}
		if img == nil && it.ThumbB64 != "" {
			k := "thumb:" + it.ThumbB64
			if img = mediaImgs.get(k); img == nil {
				a.decodeThumbAsync(k, it.ThumbB64)
			}
		}
	}

	if ok && viewerIsVideo(it) {
		if st, has := h264Players.peek(it.MsgID); has && st.playing && st.player != nil && st.video != nil {
			elapsed := h264Players.elapsed(it.MsgID)
			if fr := st.player.FrameAt(elapsed); fr != nil {
				img = fr
				if !powerSavingBlocks(powerSaving.flags, powerSaving.forceAll, psClassVideo) {
					gtx.Execute(op.InvalidateCmd{At: time.Now().Add(st.player.NextFrameIn(elapsed))})
				}
			}
		}
	}

	if img == nil {
		w, h := fitDims(it.Width, it.Height, boxW, boxH)
		if w <= 0 || h <= 0 {
			w, h = boxW, boxH
		}
		a.mvScaledW, a.mvScaledH = float32(w), float32(h)
		return roundedFill(gtx, color.NRGBA{A: 0x30}, 0, func(gtx layout.Context) layout.Dimensions {
			return layout.Dimensions{Size: image.Pt(w, h)}
		})
	}

	w0, h0 := img.Bounds().Dx(), img.Bounds().Dy()
	total := fitScale(w0, h0, boxW, boxH) * a.mvZoom
	sw, sh := float32(w0)*total, float32(h0)*total
	a.mvScaledW, a.mvScaledH = sw, sh

	a.mvPan = f32.Pt(
		clampPanAxis(a.mvPan.X, sw, float32(boxW)),
		clampPanAxis(a.mvPan.Y, sh, float32(boxH)),
	)

	cx, cy := float32(boxW)/2, float32(boxH)/2
	originX := cx + a.mvPan.X - sw/2
	originY := cy + a.mvPan.Y - sh/2

	clipStack := clip.Rect{Max: image.Pt(boxW, boxH)}.Push(gtx.Ops)
	trStack := op.Affine(f32.AffineId().
		Offset(f32.Pt(originX, originY)).
		Scale(f32.Point{}, f32.Pt(total, total))).Push(gtx.Ops)
	imgOp := paint.NewImageOp(img)
	imgOp.Filter = paint.FilterLinear
	imgOp.Add(gtx.Ops)
	paint.PaintOp{}.Add(gtx.Ops)
	trStack.Pop()
	clipStack.Pop()

	if ok && viewerIsVideo(it) && !viewerVideoActive(it) {
		d := gtx.Dp(unit.Dp(72))
		dx := (boxW - d) / 2
		dy := (boxH - d) / 2
		off := op.Offset(image.Pt(dx, dy)).Push(gtx.Ops)
		btn := material.ButtonLayout(a.ui.Theme, &a.wid.viewerPlayBtn)
		btn.Background = color.NRGBA{}
		btn.CornerRadius = 36
		dims := btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return drawPlayBadge(gtx, d)
		})
		off.Pop()
		_ = dims
	}

	return layout.Dimensions{Size: image.Pt(boxW, boxH)}
}

func (a *App) processViewerImageEvents(gtx layout.Context, f frame) {
	const dblClickWindow = 350 * time.Millisecond
	var last f32.Point
	for {
		ev, ok := gtx.Source.Event(pointer.Filter{
			Target: viewerImgTag,
			Kinds:  pointer.Press | pointer.Drag | pointer.Release,
		})
		if !ok {
			break
		}
		pe, is := ev.(pointer.Event)
		if !is {
			continue
		}
		switch pe.Kind {
		case pointer.Press:
			now := time.Now()
			dx := pe.Position.X - a.mvLastPressPos.X
			dy := pe.Position.Y - a.mvLastPressPos.Y
			tol := float32(gtx.Dp(unit.Dp(10)))
			if now.Sub(a.mvLastPressAt) < dblClickWindow && dx*dx+dy*dy <= tol*tol {
				newZoom := viewerZoomAfter(a.mvZoom)
				k := newZoom / a.mvZoom
				cx := float32(gtx.Constraints.Max.X) / 2
				cy := float32(gtx.Constraints.Max.Y) / 2
				a.mvPan.X = panAfterZoom(a.mvPan.X, pe.Position.X, cx, k)
				a.mvPan.Y = panAfterZoom(a.mvPan.Y, pe.Position.Y, cy, k)
				a.mvZoom = newZoom
				a.mvPan = a.clampPan(a.mvPan, a.mvScaledW*k, a.mvScaledH*k)
				a.mvLastPressAt = time.Time{}
				a.invalidate()
			} else {
				a.mvLastPressAt = now
				a.mvLastPressPos = pe.Position
			}
			last = pe.Position
		case pointer.Drag:
			if a.mvZoom > 1.01 {
				a.mvPan.X += pe.Position.X - last.X
				a.mvPan.Y += pe.Position.Y - last.Y
				a.mvPan = a.clampPanNow(a.mvPan)
				a.invalidate()
			}
			last = pe.Position
		case pointer.Release:
			last = f32.Point{}
		}
	}
}

func (a *App) clampPanNow(pan f32.Point) f32.Point {
	return a.clampPan(pan, a.mvScaledW, a.mvScaledH)
}

func (a *App) clampPan(pan f32.Point, scaledW, scaledH float32) f32.Point {
	if scaledW <= 0 || scaledH <= 0 || a.mvBoxW <= 0 || a.mvBoxH <= 0 {
		return pan
	}
	return f32.Pt(
		clampPanAxis(pan.X, scaledW, float32(a.mvBoxW)),
		clampPanAxis(pan.Y, scaledH, float32(a.mvBoxH)),
	)
}

func (a *App) viewerCaption(gtx layout.Context, f frame) layout.Dimensions {
	it, _, ok := a.viewerCurrent(f)
	if !ok || (it.Text == "" && it.SenderName == "") {
		return layout.Dimensions{}
	}
	gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(64))
	gtx.Constraints.Min.Y = 0
	return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(2), Left: unit.Dp(24), Right: unit.Dp(24)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			if it.SenderName != "" {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(13), it.SenderName)
						lbl.Color = a.ui.p.Accent
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if it.Text == "" {
							return layout.Dimensions{}
						}
						lbl := a.ui.Dim(unit.Sp(14), it.Text)
						lbl.Color = a.ui.p.Text
						return lbl.Layout(gtx)
					}),
				)
			}
			lbl := a.ui.Dim(unit.Sp(14), it.Text)
			lbl.Color = a.ui.p.Text
			return lbl.Layout(gtx)
		})
}

func (a *App) viewerFilmstrip(gtx layout.Context, f frame) layout.Dimensions {
	v := f.viewer
	n := len(v.items)
	if n == 0 {
		return layout.Dimensions{}
	}
	growClickables(&a.wid.filmClicks, n)
	const thumb = unit.Dp(52)
	rowH := gtx.Dp(thumb) + gtx.Dp(unit.Dp(8))
	gtx.Constraints.Max.Y = rowH
	gtx.Constraints.Min.Y = rowH

	list := &a.wid.filmList
	list.Axis = layout.Horizontal
	ml := material.List(a.ui.Theme, list)
	return ml.Layout(gtx, n, func(gtx layout.Context, i int) layout.Dimensions {
		it := v.items[i]
		btn := &a.wid.filmClicks[i]
		if btn.Clicked(gtx) {
			a.viewerSetIndex(i)
		}
		current := i == v.index
		return layout.Inset{Right: unit.Dp(4), Left: unit.Dp(4), Top: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx,
			func(gtx layout.Context) layout.Dimensions {
				cell := gtx.Dp(thumb)
				gtx.Constraints.Max.X = cell
				gtx.Constraints.Max.Y = cell
				gtx.Constraints.Min = image.Pt(cell, cell)
				return material.ButtonLayout(a.ui.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					if current {
						defer clip.RRect{Rect: image.Rect(0, 0, cell, cell), NE: 4, NW: 4, SE: 4, SW: 4}.Push(gtx.Ops).Pop()
						paint.Fill(gtx.Ops, a.ui.p.Accent)
					}
					return layout.UniformInset(unit.Dp(2)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						var img *image.RGBA
						if it.LocalPath != "" && isDisplayableImage(it.LocalPath) {
							k := "file:" + it.LocalPath
							if got := mediaImgs.get(k); got != nil {
								img = got
							} else {
								a.decodeFileAsync(it.LocalPath)
							}
						}
						if img == nil && it.ThumbB64 != "" {
							k := "thumb:" + it.ThumbB64
							if img = mediaImgs.get(k); img == nil {
								a.decodeThumbAsync(k, it.ThumbB64)
							}
						}
						if img != nil {
							return drawImageScaled(gtx, img, cell, cell, 3)
						}
						return roundedFill(gtx, color.NRGBA{A: 0x38}, 3, func(gtx layout.Context) layout.Dimensions {
							return layout.Dimensions{Size: image.Pt(cell, cell)}
						})
					})
				})
			})
	})
}

func (a *App) viewerProgress(gtx layout.Context, f frame) layout.Dimensions {
	v := f.viewer
	it, _, ok := a.viewerCurrent(f)
	if !ok {
		return layout.Dimensions{}
	}
	st, live := f.downloads[dlKey(v.accountID, v.chatID, it.MsgID, 0)]
	if !live || st.state != engine.DownloadInProgress {
		return layout.Dimensions{}
	}
	return layout.Inset{Left: unit.Dp(24), Right: unit.Dp(24), Bottom: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return a.downloadRow(gtx, st.recv, st.total)
	})
}

func viewerSavePlan(hasLocal bool) string {
	if hasLocal {
		return "copy"
	}
	return "download"
}

func (a *App) viewerSave(v *viewerState, it engine.SharedMediaItem) {
	acct, chat, id := v.accountID, v.chatID, it.MsgID
	if it.LocalPath != "" {
		a.saveMediaToDownloads(acct, chat, id, 0)
		return
	}
	a.setSaveOnDone(acct, chat, id, 0)
	go func() {
		if err := a.eng.RequestDownload(acct, chat, id, 0, 0); err != nil {
			a.setToast("Download failed: " + err.Error())
		}
	}()
}

func (a *App) viewerShare(v *viewerState, it engine.SharedMediaItem) {
	m := engine.CachedMessage{
		AccountID:   v.accountID,
		ChatID:      v.chatID,
		MsgID:       it.MsgID,
		SenderName:  it.SenderName,
		ContentText: it.Text,
	}
	a.openForward([]engine.CachedMessage{m})
	a.mu.Lock()
	a.viewer = nil
	a.mu.Unlock()
	a.viewerResetGesture()
	a.invalidate()
}

func (a *App) viewerPlay(v *viewerState, it engine.SharedMediaItem) {
	if it.LocalPath != "" {
		if viewerCanPlayInApp(it) {
			a.viewerPlayVideo(it)
			return
		}
		a.openMedia(it.LocalPath, true)
		return
	}
	acct, chat, id := v.accountID, v.chatID, it.MsgID
	if a.startStreamedViewerVideo(v, it) {
		return
	}
	a.setOpenOnDone(acct, chat, id, 0)
	go func() {
		if err := a.eng.RequestDownload(acct, chat, id, 0, 0); err != nil {
			a.setToast("Download failed: " + err.Error())
		}
	}()
	a.setToast("Downloading video…")
}

func (a *App) viewerDeleteConfirmed(v *viewerState, it engine.SharedMediaItem) {
	acct, chat, id, revoke := v.accountID, v.chatID, it.MsgID, it.IsOutgoing
	a.closeViewer()
	go func() {
		if err := a.eng.DeleteMessage(acct, chat, id, revoke); err != nil {
			a.setToast("Delete failed: " + err.Error())
		} else {
			a.setToast("Message deleted")
		}
	}()
}

func (a *App) viewerCancelDelete() {
	a.mu.Lock()
	if a.viewer != nil {
		a.viewer.deleting = false
	}
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) viewerDeleteDialog(gtx layout.Context, f frame) layout.Dimensions {
	it, _, ok := a.viewerCurrent(f)
	if a.wid.viewerDelYesBtn.Clicked(gtx) {
		if ok {
			a.viewerDeleteConfirmed(f.viewer, it)
		} else {
			a.closeViewer()
		}
		return layout.Dimensions{}
	}
	if a.wid.viewerDelNoBtn.Clicked(gtx) {
		a.viewerCancelDelete()
	}

	w := gtx.Dp(unit.Dp(280))
	gtx2 := gtx
	gtx2.Constraints.Min = image.Point{}
	return centerLayout(gtx2, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = w
		gtx.Constraints.Min.X = w
		return surfaceBox(gtx, a.ui, a.ui.p.Surface, unit.Dp(12), func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(18)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.H3("Delete this message?")
						lbl.Color = a.ui.p.Text
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							hint := "The message will be deleted locally."
							if ok && it.IsOutgoing {
								hint = "The message will be deleted for everyone."
							}
							lbl := a.ui.Dim(unit.Sp(13), hint)
							lbl.Color = a.ui.p.TextDim
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.TextButton(&a.wid.viewerDelNoBtn, "Cancel")
									btn.Color = a.ui.p.Text
									return btn.Layout(gtx)
								})
							}),
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								btn := a.ui.PrimaryButton(&a.wid.viewerDelYesBtn, "Delete")
								btn.Background = a.ui.p.Error
								return btn.Layout(gtx)
							}),
						)
					}),
				)
			})
		})
	})
}
