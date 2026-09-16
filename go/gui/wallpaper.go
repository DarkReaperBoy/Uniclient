package gui

// wallpaper.go — slice 218: per-chat custom wallpapers (tdesktop/AyuGram
// "Set wallpaper" for private chats). The picker stages a local image
// (explorer), previews it, and applies it through the engine
// (account.uploadWallPaper for_chat → messages.setChatWallPaper, with the
// blur transform and the premium for-both flag). The message pane renders
// the chat's active wallpaper — received ones arrive via the
// messageActionSetChatWallPaper service row (engine mirror) — cover-fit
// behind the messages with the spec blur (downscale to 450 + box blur 12)
// when the settings ask for it.

import (
	"encoding/json"
	"image"
	"os"
	"sync"

	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget/material"

	"uniclient/cores"
	"uniclient/engine"
)

// ── dialog state ──────────────────────────────────────────────────────────

// wallpaperDlgState is the picker dialog (mirrors chatThemeDlgState).
type wallpaperDlgState struct {
	accountID string
	chatID    string
	title     string

	// staged local image ("" = none picked yet).
	path     string
	preview  *image.RGBA
	decoding bool

	blur    bool
	forBoth bool
	setting bool
	errMsg  string
}

// openWallpaperDialog opens the picker for a private chat.
func (a *App) openWallpaperDialog(c engine.ChatInfo) {
	a.mu.Lock()
	a.wallpaperDlg = &wallpaperDlgState{accountID: c.AccountID, chatID: c.ChatID, title: c.Title}
	a.mu.Unlock()
	a.invalidate()
}

// closeWallpaperDialog dismisses the picker.
func (a *App) closeWallpaperDialog() {
	a.mu.Lock()
	a.wallpaperDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// wallpaperExts are the image formats the wallpaper flow accepts
// (account.uploadWallPaper takes JPEG/PNG).
var wallpaperExts = []string{".jpg", ".jpeg", ".png"}

// pickWallpaperImage opens the OS file picker and stages the chosen
// image (async decode into the preview).
func (a *App) pickWallpaperImage() {
	a.mu.Lock()
	d := a.wallpaperDlg
	expl := a.expl
	a.mu.Unlock()
	if d == nil || expl == nil {
		return
	}
	rcs, err := expl.ChooseFiles(wallpaperExts...)
	if err != nil {
		if !isUserDecline(err) {
			a.setToast("Wallpaper: " + err.Error())
		}
		return
	}
	paths, temps := resolveUploadPaths(rcs)
	defer func() {
		for _, t := range temps {
			os.Remove(t)
		}
	}()
	if len(paths) == 0 {
		return
	}
	path := paths[0]
	data, err := os.ReadFile(path)
	if err != nil {
		a.setToast("Wallpaper: " + err.Error())
		return
	}
	a.mu.Lock()
	if a.wallpaperDlg == d {
		d.path = path
		d.decoding = true
	}
	a.mu.Unlock()
	go func() {
		img, _, derr := decodeGUIImage(data)
		a.mu.Lock()
		if a.wallpaperDlg == d && derr == nil {
			d.preview = imgToRGBA(img)
		}
		d.decoding = false
		a.mu.Unlock()
		a.invalidate()
	}()
}

// applyWallpaper uploads the staged image and sets it on the chat.
func (a *App) applyWallpaper() {
	a.mu.Lock()
	d := a.wallpaperDlg
	if d == nil || d.path == "" || d.setting {
		a.mu.Unlock()
		return
	}
	d.setting, d.errMsg = true, ""
	path, blur, forBoth := d.path, d.blur, d.forBoth
	accountID, chatID := d.accountID, d.chatID
	a.mu.Unlock()

	go func() {
		fail := func(msg string) {
			a.mu.Lock()
			if a.wallpaperDlg == d {
				d.errMsg = msg
			}
			a.mu.Unlock()
			a.invalidate()
		}
		defer func() {
			a.mu.Lock()
			if a.wallpaperDlg == d {
				d.setting = false
			}
			a.mu.Unlock()
			a.invalidate()
		}()
		data, err := os.ReadFile(path)
		if err != nil {
			fail(err.Error())
			return
		}
		mime := "image/jpeg"
		if len(data) > 3 && data[0] == 0x89 && data[1] == 'P' && data[2] == 'N' && data[3] == 'G' {
			mime = "image/png"
		}
		wp, err := a.eng.UploadChatWallpaper(accountID, data, mime, blur)
		if err != nil {
			fail("Upload failed: " + err.Error())
			return
		}
		if err := a.eng.SetChatWallpaper(accountID, chatID, wp, forBoth); err != nil {
			fail("Set failed: " + err.Error())
			return
		}
		a.setToast("Wallpaper set")
		a.mu.Lock()
		for i := range a.chats {
			if a.chats[i].AccountID == accountID && a.chats[i].ChatID == chatID {
				if raw, jerr := json.Marshal(wp); jerr == nil {
					a.chats[i].WallpaperJSON = string(raw)
				}
				break
			}
		}
		a.mu.Unlock()
		a.closeWallpaperDialog()
	}()
}

// refreshWallpaperChat mirrors the freshly-set wallpaper onto the open
// chat list entry (the engine already wrote chats.wallpaper_json; the
// message-pane renderer reads ChatInfo.WallpaperJSON — same optimistic
// local mirror as the theme apply, the echo confirms later).

// ── dialog layout ─────────────────────────────────────────────────────────

// layoutWallpaperDialog renders the picker as the content-pane surface.
func (a *App) layoutWallpaperDialog(gtx layout.Context, f frame) layout.Dimensions {
	st := f.wallpaperDlg
	if st == nil {
		return layout.Dimensions{}
	}
	// Esc closes (self-handled, same as the theme picker).
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeWallpaperDialog()
			return layout.Dimensions{}
		}
	}
	if a.wid.wallpaperPickBtn.Clicked(gtx) {
		go a.pickWallpaperImage()
	}
	if a.wid.wallpaperCancelBtn.Clicked(gtx) {
		a.closeWallpaperDialog()
	}
	if a.wid.wallpaperSetBtn.Clicked(gtx) {
		go a.applyWallpaper()
	}
	st.blur = a.wid.wallpaperBlurChk.Update(gtx)
	st.forBoth = a.wid.wallpaperBothChk.Update(gtx)

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(340))
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(360))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.ui.H3("Set wallpaper").Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(12), "Applies to "+st.title)
						lbl.Color = a.ui.p.TextFaint
						return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(10)}.Layout(gtx, lbl.Layout)
					}),
					// Preview: the staged image cover-fit, or the hint.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						h := gtx.Dp(unit.Dp(130))
						gtx.Constraints.Min = image.Pt(gtx.Constraints.Max.X, h)
						gtx.Constraints.Max.Y = h
						if st.preview == nil {
							txt := "Choose a JPEG or PNG image"
							if st.decoding {
								txt = "Decoding…"
							}
							return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(13), txt)
								lbl.Color = a.ui.p.TextFaint
								return lbl.Layout(gtx)
							})
						}
						return drawWallpaperCover(gtx, st.preview)
					}),
					layout.Rigid(layout.Spacer{Height: unit.Dp(10)}.Layout),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						label := "Choose image…"
						if st.path != "" {
							label = "Change image…"
						}
						return material.Button(a.ui.Theme, &a.wid.wallpaperPickBtn, label).Layout(gtx)
					}),
					layout.Rigid(layout.Spacer{Height: unit.Dp(8)}.Layout),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return material.CheckBox(a.ui.Theme, &a.wid.wallpaperBlurChk, "Blur").Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return material.CheckBox(a.ui.Theme, &a.wid.wallpaperBothChk, "Set for both sides (Premium)").Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if st.errMsg == "" {
							return layout.Dimensions{}
						}
						lbl := a.ui.Dim(unit.Sp(12), st.errMsg)
						lbl.Color = a.ui.p.Error
						return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, lbl.Layout)
					}),
					layout.Flexed(1, layout.Spacer{Height: unit.Dp(1)}.Layout),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								btn := material.Button(a.ui.Theme, &a.wid.wallpaperCancelBtn, "Cancel")
								btn.Background = a.ui.p.Surface
								btn.Color = a.ui.p.Text
								return btn.Layout(gtx)
							}),
							layout.Rigid(layout.Spacer{Width: unit.Dp(8)}.Layout),
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								set := material.Button(a.ui.Theme, &a.wid.wallpaperSetBtn, "Set")
								if st.path == "" || st.setting {
									set.Background = a.ui.p.Surface
								}
								if st.setting {
									set.Text = "Setting…"
								}
								return set.Layout(gtx)
							}),
						)
					}),
				)
			})
		})
	})
}

// ── background rendering ──────────────────────────────────────────────────

// wallpaperBackground paints the chat's custom wallpaper behind the
// messages (cover-fit; spec blur when the settings ask). Returns whether
// it painted — the theme gradient is skipped then (a custom wallpaper
// replaces it, tdesktop behavior).
func (a *App) wallpaperBackground(gtx layout.Context, chat engine.ChatInfo, f frame) bool {
	if chat.WallpaperJSON == "" {
		return false
	}
	info, ok := parseWallpaperJSON(chat.WallpaperJSON)
	if !ok || info.DocID == 0 {
		return false
	}
	key := "wallpaper:" + itoa64(info.DocID)
	if img := mediaImgs.get(key); img != nil {
		drawWallpaperCover(gtx, img)
		return true
	}
	a.ensureWallpaperImage(chat.AccountID, info)
	return false
}

// wallpaperFetches guards one in-flight document download per doc.
var wallpaperFetches sync.Map

// ensureWallpaperImage downloads + decodes a wallpaper document into the
// shared media cache (blur applied per the wallpaper settings).
func (a *App) ensureWallpaperImage(accountID string, info cores.WallpaperInfo) {
	if _, busy := wallpaperFetches.LoadOrStore(info.DocID, true); busy {
		return
	}
	go func() {
		defer wallpaperFetches.Delete(info.DocID)
		data, err := a.eng.DownloadWallpaperDocument(accountID, info.DocID, info.DocHash, []byte(info.DocRef))
		if err != nil || len(data) == 0 {
			return
		}
		img, _, derr := decodeGUIImage(data)
		if derr != nil {
			return
		}
		rgba := imgToRGBA(img)
		if info.Blurred {
			rgba = wallpaperBlur(rgba)
		}
		mediaImgs.store("wallpaper:"+itoa64(info.DocID), rgba)
		a.invalidate()
	}()
}

// parseWallpaperJSON decodes the mirrored WallpaperInfo ("" and garbage
// both mean "no wallpaper"). Pure — unit-tested.
func parseWallpaperJSON(js string) (cores.WallpaperInfo, bool) {
	if js == "" {
		return cores.WallpaperInfo{}, false
	}
	var info cores.WallpaperInfo
	if err := json.Unmarshal([]byte(js), &info); err != nil {
		return cores.WallpaperInfo{}, false
	}
	return info, true
}

// drawWallpaperCover draws img cover-fit into the full constraints box
// (scale to fill, center crop) — the wallpaper presentation, on top of
// the album-crop primitive.
func drawWallpaperCover(gtx layout.Context, img *image.RGBA) layout.Dimensions {
	w := gtx.Constraints.Max.X
	h := gtx.Constraints.Max.Y
	if h <= 0 {
		h = gtx.Constraints.Min.Y
	}
	if w <= 0 || h <= 0 {
		return layout.Dimensions{Size: image.Pt(w, h)}
	}
	stack := clip.Rect{Max: image.Pt(w, h)}.Push(gtx.Ops)
	drawImageCover(gtx, img, w, h)
	stack.Pop()
	return layout.Dimensions{Size: image.Pt(w, h)}
}

// ── spec blur ─────────────────────────────────────────────────────────────

// wallpaperBlur applies the API-spec image-wallpaper transform: downscale
// to fit a 450×450 square, then box-blur with radius 12 (two passes for
// a smoother result). Pure — unit-tested.
func wallpaperBlur(src *image.RGBA) *image.RGBA {
	if src == nil || src.Bounds().Empty() {
		return src
	}
	w, h := src.Bounds().Dx(), src.Bounds().Dy()
	// Downscale to fit 450 (box-average when shrinking for quality).
	sw, sh := w, h
	if sw > 450 || sh > 450 {
		k := float64(450) / float64(maxInt(w, h))
		sw = maxInt(1, int(float64(w)*k+0.5))
		sh = maxInt(1, int(float64(h)*k+0.5))
	}
	dst := boxScaleRGBA(src, sw, sh)
	// Two separable box-blur passes at radius 12.
	dst = boxBlurRGBA(dst, 12)
	dst = boxBlurRGBA(dst, 12)
	return dst
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}

// boxScaleRGBA resizes by box averaging (each destination pixel averages
// its source footprint). Pure — unit-tested.
func boxScaleRGBA(src *image.RGBA, w, h int) *image.RGBA {
	sw, sh := src.Bounds().Dx(), src.Bounds().Dy()
	if w <= 0 || h <= 0 || sw == 0 || sh == 0 {
		return src
	}
	if w == sw && h == sh {
		return src
	}
	dst := image.NewRGBA(image.Rect(0, 0, w, h))
	xRatio := float64(sw) / float64(w)
	yRatio := float64(sh) / float64(h)
	for y := 0; y < h; y++ {
		y0 := int(float64(y) * yRatio)
		y1 := int(float64(y+1) * yRatio)
		if y1 <= y0 {
			y1 = y0 + 1
		}
		if y1 > sh {
			y1 = sh
		}
		for x := 0; x < w; x++ {
			x0 := int(float64(x) * xRatio)
			x1 := int(float64(x+1) * xRatio)
			if x1 <= x0 {
				x1 = x0 + 1
			}
			if x1 > sw {
				x1 = sw
			}
			var r, g, b, n uint64
			var a, an uint64
			for sy := y0; sy < y1; sy++ {
				row := src.Pix[sy*src.Stride:]
				for sx := x0; sx < x1; sx++ {
					i := sx * 4
					r += uint64(row[i])
					g += uint64(row[i+1])
					b += uint64(row[i+2])
					a += uint64(row[i+3])
					n++
					an++
				}
			}
			di := dst.PixOffset(x, y)
			dst.Pix[di] = byte(r / n)
			dst.Pix[di+1] = byte(g / n)
			dst.Pix[di+2] = byte(b / n)
			dst.Pix[di+3] = byte(a / an)
		}
	}
	return dst
}

// boxBlurRGBA is a separable moving-average box blur (edge clamp).
// Pure — unit-tested.
func boxBlurRGBA(src *image.RGBA, radius int) *image.RGBA {
	if src == nil || radius <= 0 || src.Bounds().Empty() {
		return src
	}
	tmp := image.NewRGBA(src.Bounds())
	dst := image.NewRGBA(src.Bounds())
	w, h := src.Bounds().Dx(), src.Bounds().Dy()
	// Horizontal.
	for y := 0; y < h; y++ {
		row := src.Pix[y*src.Stride:]
		out := tmp.Pix[y*tmp.Stride:]
		var r, g, b, a uint64
		for x := -radius; x <= radius; x++ {
			cx := clampInt(x, 0, w-1)
			i := cx * 4
			r += uint64(row[i])
			g += uint64(row[i+1])
			b += uint64(row[i+2])
			a += uint64(row[i+3])
		}
		n := uint64(2*radius + 1)
		for x := 0; x < w; x++ {
			out[x*4] = byte(r / n)
			out[x*4+1] = byte(g / n)
			out[x*4+2] = byte(b / n)
			out[x*4+3] = byte(a / n)
			// Sliding update with CLAMPED indices: the edge-clamped
			// window holds virtual copies of the edge samples, so the
			// add/remove pair always fires (a guarded skip desyncs the
			// multiset and overflows the average).
			i := clampInt(x+radius+1, 0, w-1) * 4
			r += uint64(row[i])
			g += uint64(row[i+1])
			b += uint64(row[i+2])
			a += uint64(row[i+3])
			i = clampInt(x-radius, 0, w-1) * 4
			r -= uint64(row[i])
			g -= uint64(row[i+1])
			b -= uint64(row[i+2])
			a -= uint64(row[i+3])
		}
	}
	// Vertical.
	for x := 0; x < w; x++ {
		var r, g, b, a uint64
		for y := -radius; y <= radius; y++ {
			cy := clampInt(y, 0, h-1)
			i := cy*tmp.Stride + x*4
			r += uint64(tmp.Pix[i])
			g += uint64(tmp.Pix[i+1])
			b += uint64(tmp.Pix[i+2])
			a += uint64(tmp.Pix[i+3])
		}
		n := uint64(2*radius + 1)
		for y := 0; y < h; y++ {
			di := y*dst.Stride + x*4
			dst.Pix[di] = byte(r / n)
			dst.Pix[di+1] = byte(g / n)
			dst.Pix[di+2] = byte(b / n)
			dst.Pix[di+3] = byte(a / n)
			// Same clamped always-add/always-remove as the horizontal
			// pass (see the comment there for the invariant).
			i := clampInt(y+radius+1, 0, h-1)*tmp.Stride + x*4
			r += uint64(tmp.Pix[i])
			g += uint64(tmp.Pix[i+1])
			b += uint64(tmp.Pix[i+2])
			a += uint64(tmp.Pix[i+3])
			i = clampInt(y-radius, 0, h-1)*tmp.Stride + x*4
			r -= uint64(tmp.Pix[i])
			g -= uint64(tmp.Pix[i+1])
			b -= uint64(tmp.Pix[i+2])
			a -= uint64(tmp.Pix[i+3])
		}
	}
	return dst
}

func clampInt(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

// draw keeps the draw import honest for future tiling paths.
