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

// Fullscreen media viewer — the AyuGram mediaview overlay
// (research/ayugram_parity.md §12): near-black scrim, top bar (chat title +
// date, save/share/delete), aspect-fit image or video poster with
// double-click zoom + drag pan, caption, a thumbnail filmstrip over
// engine.GetSharedMedia, and live download progress from the engine media
// pipeline. Keyboard: Escape closes, arrows navigate. Every action
// dispatches a real engine call; nothing renders state the engine cannot
// back (§1.10).

// viewerState is the open media viewer (mu-guarded; frames read via
// snapshot pointer copy).
type viewerState struct {
	accountID string
	chatID    string
	chatTitle string
	kind      string // shared-media filter: "image" | "video"
	anchor    string // msgID the viewer was opened from
	items     []engine.SharedMediaItem
	index     int
	loaded    bool
	deleting  bool // delete-confirmation dialog open
}

// viewer input tags (frame-loop only, single GUI goroutine).
var (
	viewerKeyTag = new(struct{}) // keyboard: Escape/arrows
	viewerBgTag  = new(struct{}) // backdrop press-to-close
	viewerImgTag = new(struct{}) // image area: double-click zoom, drag pan
)

// viewer button pool (package-level, like the menu buttons).
var (
	viewerCloseBtn  widget.Clickable
	viewerSaveBtn   widget.Clickable
	viewerShareBtn  widget.Clickable
	viewerDelBtn    widget.Clickable
	viewerPrevBtn   widget.Clickable
	viewerNextBtn   widget.Clickable
	viewerPlayBtn   widget.Clickable
	viewerDelYesBtn widget.Clickable
	viewerDelNoBtn  widget.Clickable
	filmClicks      []widget.Clickable // filmstrip thumbnails
)

var filmList widget.List

// ── pure helpers (unit-tested in mediaview_test.go) ──────────────────────

// stepViewerIndex clamps navigation at both ends (AyuGram stops at the
// oldest/newest media; no wrap-around).
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

// viewerZoomAfter toggles between fit (1x) and AyuGram's double-click zoom.
func viewerZoomAfter(z float32) float32 {
	if z > 1.01 {
		return 1
	}
	return 2.5
}

// clampPanAxis keeps a zoomed image edge reachable: pan is limited so the
// image never drifts fully off the box; a zoomed side smaller than the box
// snaps to center.
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

// panAfterZoom keeps the point under the cursor stationary across a zoom
// change: pan' = pan*k + (click-center)*(1-k).
func panAfterZoom(pan, click, center, k float32) float32 {
	return pan*k + (click-center)*(1-k)
}

// findViewerItem returns the index of msgID in items, or -1.
func findViewerItem(items []engine.SharedMediaItem, msgID string) int {
	for i, it := range items {
		if it.MsgID == msgID {
			return i
		}
	}
	return -1
}

// mergeViewerItems splices the loaded shared-media list with the synthetic
// entry the viewer opened with (for the case where the anchor message is
// not itself in the media table's kind filter) and returns the list plus
// the anchor's index.
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

// synthItemFromMsg mirrors a CachedMessage's media fields into a viewer item
// so the viewer shows the tapped message instantly, before the shared list
// loads.
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

// viewerKindFor maps a message media type to the viewer's shared-media kind.
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

// fmtViewerDate renders the item date AyuGram-style (full date + time).
func fmtViewerDate(ms int64) string {
	if ms <= 0 {
		return ""
	}
	return time.UnixMilli(ms).Format("2 Jan 2006, 15:04")
}

// viewerIsVideo reports the poster/play treatment.
func viewerIsVideo(it engine.SharedMediaItem) bool {
	return it.MediaType == engine.MediaVideo || it.MediaType == engine.MediaVideoNote
}

// ── App state transitions ─────────────────────────────────────────────────

// openViewerFromMsg opens the viewer on a tapped message's media. gtx is
// the frame context: opening the overlay clears the composer focus so the
// viewer's Escape/arrow keys are not consumed by the editor underneath.
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

	// Fill the filmstrip from the chat's shared media (same kind).
	msg := *m
	go func() {
		items, err := a.eng.GetSharedMedia(msg.AccountID, msg.ChatID, kind, 120, 0, "")
		if err != nil {
			return // keep the synthetic single-item view
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

// openViewerAt opens the viewer on a shared-media entry (info-panel
// gallery).
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

// closeViewer dismisses the overlay.
func (a *App) closeViewer() {
	a.mu.Lock()
	a.viewer = nil
	a.mu.Unlock()
	a.viewerResetGesture()
	a.invalidate()
}

// viewerStep navigates ±1 (clamped) and resets zoom/pan.
func (a *App) viewerStep(delta int) {
	a.mu.Lock()
	if v := a.viewer; v != nil {
		v.index = stepViewerIndex(v.index, len(v.items), delta)
	}
	a.mu.Unlock()
	a.viewerResetGesture()
	a.invalidate()
}

// viewerSetIndex jumps to a filmstrip thumbnail and resets zoom/pan.
func (a *App) viewerSetIndex(i int) {
	a.mu.Lock()
	if v := a.viewer; v != nil && i >= 0 && i < len(v.items) {
		v.index = i
	}
	a.mu.Unlock()
	a.viewerResetGesture()
	a.invalidate()
}

// viewerResetGesture (frame-loop fields; called from GUI goroutine only).
func (a *App) viewerResetGesture() {
	a.mvZoom = 1
	a.mvPan = f32.Point{}
	a.mvLastPressAt = time.Time{}
	mvScaledW, mvScaledH = 0, 0
}

// chatTitleFor looks the chat title up (viewer top bar).
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

// viewerCurrent returns the shown item (copy) + index.
func (a *App) viewerCurrent(f frame) (engine.SharedMediaItem, int, bool) {
	v := f.viewer
	if v == nil || len(v.items) == 0 || v.index < 0 || v.index >= len(v.items) {
		return engine.SharedMediaItem{}, 0, false
	}
	return v.items[v.index], v.index, true
}

// ── layout ────────────────────────────────────────────────────────────────

// layoutMediaView renders the fullscreen viewer over everything else.
func (a *App) layoutMediaView(gtx layout.Context, f frame) layout.Dimensions {
	v := f.viewer

	// Keep keyboard focus out of the (covered) composer while viewing; the
	// router dedups unchanged focus, so this is cheap.
	gtx.Execute(key.FocusCmd{Tag: nil})

	// Keyboard: Escape closes, arrows navigate (AyuGram mediaview keys).
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

	// Backdrop press closes (registered before the image/buttons → below
	// them in hit-test order).
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

	// Scrim: near-black like AyuGram's mediaview, over the whole window.
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
			return a.viewerFilmstrip(gtx, f)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.viewerProgress(gtx, f)
		}),
	)
	if v.deleting {
		// Confirmation card on top (its buttons register later → on top).
		a.viewerDeleteDialog(gtx, f)
	}
	return body
}

// viewerTopBar: close | title/date | save/share/delete.
func (a *App) viewerTopBar(gtx layout.Context, f frame) layout.Dimensions {
	v := f.viewer
	it, _, ok := a.viewerCurrent(f)

	if viewerCloseBtn.Clicked(gtx) {
		a.closeViewer()
	}
	if viewerSaveBtn.Clicked(gtx) {
		if ok {
			a.viewerSave(v, it)
		}
	}
	if viewerShareBtn.Clicked(gtx) {
		if ok {
			a.viewerShare(v, it)
		}
	}
	if viewerDelBtn.Clicked(gtx) {
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
					btn := a.ui.IconButton(&viewerCloseBtn, iconContentClear, "Close")
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
					return a.viewerIconBtn(gtx, &viewerSaveBtn, iconFileDownload, "Save")
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.viewerIconBtn(gtx, &viewerShareBtn, iconSocialShare, "Share")
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.viewerIconBtn(gtx, &viewerDelBtn, iconActionDelete, "Delete")
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

// viewerCenter: the image / video poster with zoom-pan gestures, side
// chevrons, and (videos) the play affordance wired to the download pipeline.
func (a *App) viewerCenter(gtx layout.Context, f frame) layout.Dimensions {
	it, _, ok := a.viewerCurrent(f)
	if viewerPrevBtn.Clicked(gtx) {
		a.viewerStep(-1)
	}
	if viewerNextBtn.Clicked(gtx) {
		a.viewerStep(1)
	}
	if viewerPlayBtn.Clicked(gtx) && ok {
		a.viewerPlay(f.viewer, it)
	}

	return layout.Stack{}.Layout(gtx,
		layout.Expanded(func(gtx layout.Context) layout.Dimensions {
			// The image gesture area covers the whole center region: drag
			// pans while zoomed, double-click toggles zoom. Registered
			// after the backdrop → on top of it.
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
			// Side chevrons (desktop + touch).
			return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					return a.viewerChevron(gtx, &viewerPrevBtn, iconNavChevronLeft, "Previous")
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					return a.viewerChevron(gtx, &viewerNextBtn, iconNavChevronRight, "Next")
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

// viewerImage decodes + paints the current item (photo, or video poster with
// a play badge), applying the frame-loop zoom/pan transform. The image is
// centered in the box; zoom scales about the cursor, pan translates.
func (a *App) viewerImage(gtx layout.Context, f frame, it engine.SharedMediaItem, ok bool) layout.Dimensions {
	boxW := gtx.Constraints.Max.X
	boxH := gtx.Constraints.Max.Y
	if boxW > gtx.Dp(unit.Dp(920)) {
		boxW = gtx.Dp(unit.Dp(920))
	}
	if boxW <= 0 || boxH <= 0 {
		return layout.Dimensions{}
	}
	mvBoxW, mvBoxH = boxW, boxH

	// Resolve the best available pixels: downloaded file → full image;
	// otherwise the inline thumbnail. Decodes are async + cached; the next
	// frames swap in.
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

	if img == nil {
		// Still decoding (or no poster): an aspect box from the item's
		// recorded dimensions, so the layout is stable across frames.
		w, h := fitDims(it.Width, it.Height, boxW, boxH)
		if w <= 0 || h <= 0 {
			w, h = boxW, boxH
		}
		mvScaledW, mvScaledH = float32(w), float32(h)
		return roundedFill(gtx, color.NRGBA{A: 0x30}, 0, func(gtx layout.Context) layout.Dimensions {
			return layout.Dimensions{Size: image.Pt(w, h)}
		})
	}

	w0, h0 := img.Bounds().Dx(), img.Bounds().Dy()
	total := fitScale(w0, h0, boxW, boxH) * a.mvZoom
	sw, sh := float32(w0)*total, float32(h0)*total
	mvScaledW, mvScaledH = sw, sh

	// Clamp pan so a zoomed image always covers the box.
	a.mvPan = f32.Pt(
		clampPanAxis(a.mvPan.X, sw, float32(boxW)),
		clampPanAxis(a.mvPan.Y, sh, float32(boxH)),
	)

	cx, cy := float32(boxW)/2, float32(boxH)/2
	originX := cx + a.mvPan.X - sw/2
	originY := cy + a.mvPan.Y - sh/2

	// Clip to the center box so zoomed pixels never bleed over the bars.
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

	// Video poster: centered play badge on top.
	if ok && viewerIsVideo(it) {
		d := gtx.Dp(unit.Dp(72))
		dx := (boxW - d) / 2
		dy := (boxH - d) / 2
		off := op.Offset(image.Pt(dx, dy)).Push(gtx.Ops)
		btn := material.ButtonLayout(a.ui.Theme, &viewerPlayBtn)
		btn.Background = color.NRGBA{} // transparent: the badge paints itself
		btn.CornerRadius = 36
		dims := btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return drawPlayBadge(gtx, d)
		})
		off.Pop()
		_ = dims
	}

	return layout.Dimensions{Size: image.Pt(boxW, boxH)}
}

// processViewerImageEvents handles the image-area gestures: double-click
// zoom toggle (anchored at the cursor), drag pan while zoomed.
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
				// Double-click: toggle zoom, keeping the cursor point fixed.
				newZoom := viewerZoomAfter(a.mvZoom)
				k := newZoom / a.mvZoom
				cx := float32(gtx.Constraints.Max.X) / 2
				cy := float32(gtx.Constraints.Max.Y) / 2
				a.mvPan.X = panAfterZoom(a.mvPan.X, pe.Position.X, cx, k)
				a.mvPan.Y = panAfterZoom(a.mvPan.Y, pe.Position.Y, cy, k)
				a.mvZoom = newZoom
				a.mvPan = clampViewerPan2(a.mvPan, mvScaledW*k, mvScaledH*k)
				a.mvLastPressAt = time.Time{} // fresh pair needed for next toggle
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
				a.mvPan = clampViewerPanNow(a.mvPan)
				a.invalidate()
			}
			last = pe.Position
		case pointer.Release:
			last = f32.Point{}
		}
	}
}

// clampViewerPanNow clamps pan with the last painted image size (one frame
// stale at most — every pan invalidates).
func clampViewerPanNow(pan f32.Point) f32.Point {
	return clampViewerPan2(pan, mvScaledW, mvScaledH)
}

// clampViewerPan2 clamps pan against the center box (mvBoxW/H globals).
func clampViewerPan2(pan f32.Point, scaledW, scaledH float32) f32.Point {
	if scaledW <= 0 || scaledH <= 0 || mvBoxW <= 0 || mvBoxH <= 0 {
		return pan
	}
	return f32.Pt(
		clampPanAxis(pan.X, scaledW, float32(mvBoxW)),
		clampPanAxis(pan.Y, scaledH, float32(mvBoxH)),
	)
}

// mvBox/mvScaled carry the last frame's viewer center box + painted image
// size (frame-loop bookkeeping, single GUI goroutine).
var (
	mvBoxW, mvBoxH       int
	mvScaledW, mvScaledH float32
)

// viewerCaption: sender + message text under the image.
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

// viewerFilmstrip: bottom thumbnail strip over the chat's shared media —
// AyuGram's group thumbs. Current item gets an accent backing.
func (a *App) viewerFilmstrip(gtx layout.Context, f frame) layout.Dimensions {
	v := f.viewer
	n := len(v.items)
	if n == 0 {
		return layout.Dimensions{}
	}
	growClickables(&filmClicks, n)
	const thumb = unit.Dp(52)
	rowH := gtx.Dp(thumb) + gtx.Dp(unit.Dp(8))
	gtx.Constraints.Max.Y = rowH
	gtx.Constraints.Min.Y = rowH

	list := &filmList
	list.Axis = layout.Horizontal
	ml := material.List(a.ui.Theme, list)
	return ml.Layout(gtx, n, func(gtx layout.Context, i int) layout.Dimensions {
		it := v.items[i]
		btn := &filmClicks[i]
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

// viewerProgress: live download bar for the current item (engine events).
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

// ── viewer actions (all engine-backed) ────────────────────────────────────

// viewerSave starts the download when the file is missing, else reveals the
// local path (AyuGram save → the media lands in the engine's media dir).
func (a *App) viewerSave(v *viewerState, it engine.SharedMediaItem) {
	if it.LocalPath != "" {
		a.setToast("Saved to " + it.LocalPath)
		return
	}
	acct, chat, id := v.accountID, v.chatID, it.MsgID
	go func() {
		if err := a.eng.RequestDownload(acct, chat, id, 0, 0); err != nil {
			a.setToast("Download failed: " + err.Error())
		}
	}()
}

// viewerShare hands the message to the forward picker (AyuGram "Share").
func (a *App) viewerShare(v *viewerState, it engine.SharedMediaItem) {
	m := engine.CachedMessage{
		AccountID:   v.accountID,
		ChatID:      v.chatID,
		MsgID:       it.MsgID,
		SenderName:  it.SenderName,
		ContentText: it.Text,
	}
	a.mu.Lock()
	a.fwd = &m
	a.viewer = nil
	a.mu.Unlock()
	a.viewerResetGesture()
	a.invalidate()
}

// viewerPlay: videos — download when missing, then report the local file
// (in-app streaming playback lands with the engine streaming core).
func (a *App) viewerPlay(v *viewerState, it engine.SharedMediaItem) {
	if it.LocalPath != "" {
		a.setToast("Video saved to " + it.LocalPath)
		return
	}
	acct, chat, id := v.accountID, v.chatID, it.MsgID
	go func() {
		if err := a.eng.RequestDownload(acct, chat, id, 0, 0); err != nil {
			a.setToast("Download failed: " + err.Error())
		}
	}()
	a.setToast("Downloading video…")
}

// viewerDeleteConfirmed dispatches the engine delete and closes the viewer.
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

// viewerCancelDelete closes the confirmation dialog.
func (a *App) viewerCancelDelete() {
	a.mu.Lock()
	if a.viewer != nil {
		a.viewer.deleting = false
	}
	a.mu.Unlock()
	a.invalidate()
}

// viewerDeleteDialog: AyuGram-style confirmation card over the scrim. Drawn
// after the scrim (and its buttons register their input areas last → on
// top); the backdrop press cancels.
func (a *App) viewerDeleteDialog(gtx layout.Context, f frame) layout.Dimensions {
	it, _, ok := a.viewerCurrent(f)
	if viewerDelYesBtn.Clicked(gtx) {
		if ok {
			a.viewerDeleteConfirmed(f.viewer, it)
		} else {
			a.closeViewer()
		}
		return layout.Dimensions{}
	}
	if viewerDelNoBtn.Clicked(gtx) {
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
									btn := a.ui.TextButton(&viewerDelNoBtn, "Cancel")
									btn.Color = a.ui.p.Text
									return btn.Layout(gtx)
								})
							}),
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								btn := a.ui.PrimaryButton(&viewerDelYesBtn, "Delete")
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
