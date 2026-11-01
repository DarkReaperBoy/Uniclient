package gui

import (
	"encoding/base64"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"gioui.org/f32"
	"gioui.org/io/event"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"

	"uniclient/engine"
)

type dlState struct {
	recv, total int64
	state       int
}

func dlKey(accountID, chatID, msgID string, seq int) string {
	return accountID + "|" + chatID + "|" + msgID + "|" + strconv.Itoa(seq)
}

func dlActive(dls map[string]dlState) bool {
	for _, d := range dls {
		if d.state == engine.DownloadInProgress {
			return true
		}
	}
	return false
}

func dlFraction(recv, total int64) float32 {
	if total <= 0 || recv <= 0 {
		return 0
	}
	if recv >= total {
		return 1
	}
	return float32(recv) / float32(total)
}

func fmtBytes(n int64) string {
	switch {
	case n <= 0:
		return "0 B"
	case n < 1024:
		return itoa(int(n)) + " B"
	}
	kb := float64(n) / 1024
	if kb < 1024 {
		return trimFloat(kb) + " KB"
	}
	mb := kb / 1024
	if mb < 1024 {
		return trimFloat(mb) + " MB"
	}
	return trimFloat(mb/1024) + " GB"
}

func trimFloat(v float64) string {
	s := strconv.FormatFloat(v, 'f', 1, 64)
	return strings.TrimSuffix(s, ".0")
}

func fmtDur(sec int) string {
	if sec < 0 {
		sec = 0
	}
	h, m, s := sec/3600, (sec%3600)/60, sec%60
	if h > 0 {
		return itoa(h) + ":" + pad2(m) + ":" + pad2(s)
	}
	return itoa(m) + ":" + pad2(s)
}

func pad2(n int) string {
	if n < 10 {
		return "0" + itoa(n)
	}
	return itoa(n)
}

type mediaImgCache struct {
	mu      sync.Mutex
	imgs    map[string]*image.RGBA
	pending map[string]bool
}

var mediaImgs = &mediaImgCache{imgs: make(map[string]*image.RGBA), pending: make(map[string]bool)}

const mediaImgMax = 256

func (c *mediaImgCache) get(key string) *image.RGBA {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.imgs[key]
}

func (c *mediaImgCache) store(key string, img *image.RGBA) {
	c.mu.Lock()
	if len(c.imgs) >= mediaImgMax {
		c.imgs = make(map[string]*image.RGBA)
	}
	c.imgs[key] = img
	delete(c.pending, key)
	c.mu.Unlock()
}

func (c *mediaImgCache) start(key string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.pending[key] {
		return false
	}
	c.pending[key] = true
	return true
}

func (c *mediaImgCache) fail(key string) {
	c.mu.Lock()
	delete(c.pending, key)
	c.mu.Unlock()
}

func imgToRGBA(src image.Image) *image.RGBA {
	if rgba, ok := src.(*image.RGBA); ok {
		return rgba
	}
	b := src.Bounds()
	dst := image.NewRGBA(image.Rectangle{Max: b.Size()})
	draw.Draw(dst, dst.Bounds(), src, b.Min, draw.Src)
	return dst
}

func (a *App) decodeImageAsync(key string, read func() ([]byte, error)) {
	if !mediaImgs.start(key) {
		return
	}
	go func() {
		raw, err := read()
		if err != nil {
			mediaImgs.fail(key)
			return
		}
		img, _, err := decodeGUIImage(raw)
		if err != nil || img == nil {
			mediaImgs.fail(key)
			return
		}
		mediaImgs.store(key, imgToRGBA(img))
		a.invalidate()
	}()
}

func (a *App) decodeThumbAsync(key, b64 string) {
	a.decodeImageAsync(key, func() ([]byte, error) { return base64.StdEncoding.DecodeString(b64) })
}

func (a *App) decodeFileAsync(path string) {
	if path == "" {
		return
	}
	a.decodeImageAsync("file:"+path, func() ([]byte, error) { return os.ReadFile(path) })
}

var imageExts = map[string]bool{".jpg": true, ".jpeg": true, ".png": true, ".gif": true, ".webp": true}

func isDisplayableImage(path string) bool {
	return imageExts[strings.ToLower(filepath.Ext(path))]
}

func fitScale(w0, h0, maxW, maxH int) float32 {
	if w0 <= 0 || h0 <= 0 {
		return 1
	}
	s := float32(maxW) / float32(w0)
	if s2 := float32(maxH) / float32(h0); s2 < s {
		s = s2
	}
	return s
}

func fitDims(w0, h0, maxW, maxH int) (int, int) {
	if w0 <= 0 || h0 <= 0 {
		return maxW, maxH
	}
	s := fitScale(w0, h0, maxW, maxH)
	w := int(float32(w0)*s + 0.5)
	h := int(float32(h0)*s + 0.5)
	if w < 1 {
		w = 1
	}
	if h < 1 {
		h = 1
	}
	if w > maxW {
		w = maxW
	}
	if h > maxH {
		h = maxH
	}
	return w, h
}

func drawImageScaled(gtx layout.Context, img *image.RGBA, maxW, maxH, radius int) layout.Dimensions {
	w0, h0 := img.Bounds().Dx(), img.Bounds().Dy()
	if w0 <= 0 || h0 <= 0 {
		return layout.Dimensions{}
	}
	s := fitScale(w0, h0, maxW, maxH)
	w, h := fitDims(w0, h0, maxW, maxH)

	clipStack := clip.RRect{Rect: image.Rect(0, 0, w, h), NE: radius, NW: radius, SE: radius, SW: radius}.Push(gtx.Ops)
	trStack := op.Affine(f32.AffineId().Scale(f32.Point{}, f32.Pt(s, s))).Push(gtx.Ops)
	imgOp := paint.NewImageOp(img)
	imgOp.Filter = paint.FilterLinear
	imgOp.Add(gtx.Ops)
	paint.PaintOp{}.Add(gtx.Ops)
	trStack.Pop()
	clipStack.Pop()
	return layout.Dimensions{Size: image.Pt(w, h)}
}

func drawImageEllipse(gtx layout.Context, img *image.RGBA, diameter int) layout.Dimensions {
	w0, h0 := img.Bounds().Dx(), img.Bounds().Dy()
	if w0 <= 0 || h0 <= 0 || diameter <= 0 {
		return layout.Dimensions{}
	}
	s := fitScale(w0, h0, diameter, diameter)
	clipStack := clip.Ellipse{Min: image.Pt(0, 0), Max: image.Pt(diameter, diameter)}.Push(gtx.Ops)
	trStack := op.Affine(f32.AffineId().Scale(f32.Point{}, f32.Pt(s, s))).Push(gtx.Ops)
	imgOp := paint.NewImageOp(img)
	imgOp.Filter = paint.FilterLinear
	imgOp.Add(gtx.Ops)
	paint.PaintOp{}.Add(gtx.Ops)
	trStack.Pop()
	clipStack.Pop()
	return layout.Dimensions{Size: image.Pt(diameter, diameter)}
}

func drawPlayBadge(gtx layout.Context, diameter int) layout.Dimensions {
	if diameter <= 0 {
		return layout.Dimensions{}
	}
	c := float32(diameter) / 2
	r := c - 1

	circle := clip.Ellipse{Min: image.Pt(0, 0), Max: image.Pt(diameter, diameter)}.Push(gtx.Ops)
	paint.Fill(gtx.Ops, color.NRGBA{A: 0x99})
	circle.Pop()

	s := r * 0.9
	var p clip.Path
	p.Begin(gtx.Ops)
	p.MoveTo(f32.Pt(c-s*0.5, c-s*0.62))
	p.LineTo(f32.Pt(c-s*0.5, c+s*0.62))
	p.LineTo(f32.Pt(c+s*0.72, c))
	p.Close()
	tri := clip.Outline{Path: p.End()}.Op().Push(gtx.Ops)
	paint.Fill(gtx.Ops, color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF})
	tri.Pop()
	return layout.Dimensions{Size: image.Pt(diameter, diameter)}
}

func mediaBlockKind(mt int) string {
	switch mt {
	case engine.MediaImage, engine.MediaGIF:
		return "photo"
	case engine.MediaVideo, engine.MediaVideoNote:
		return "video"
	case engine.MediaVoice:
		return "voice"
	case engine.MediaAudio:
		return "audio"
	case engine.MediaSticker, engine.MediaDice:
		return "sticker"
	case engine.MediaLocation:
		return "location"
	case engine.MediaContact:
		return "contact"
	default:
		return "file"
	}
}

func (a *App) mediaClickable(key string) *widget.Clickable {
	if c, ok := a.wid.mediaClicks[key]; ok {
		return c
	}
	if len(a.wid.mediaClicks) > 512 {
		a.wid.mediaClicks = make(map[string]*widget.Clickable)
	}
	c := new(widget.Clickable)
	a.wid.mediaClicks[key] = c
	return c
}

func (a *App) mediaBlock(gtx layout.Context, f frame, m *engine.CachedMessage) layout.Dimensions {
	kind := mediaBlockKind(m.MediaType)

	st, live := f.downloads[dlKey(m.AccountID, m.ChatID, m.MsgID, 0)]
	state := m.MediaDownloadState
	if live {
		state = st.state
	}

	if autoDownloadable(m.MediaType) &&
		state == engine.DownloadNone && a.markAutoDl(m.MsgID) {
		msg := *m
		go func() {
			_ = a.eng.RequestDownload(msg.AccountID, msg.ChatID, msg.MsgID, 0, 2)
		}()
	}

	btn := a.mediaClickable(m.MsgID)
	dims := btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		var children []layout.FlexChild
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			switch kind {
			case "photo":
				return a.photoBubble(gtx, f, m, state)
			case "video":
				return a.videoBubble(gtx, f, m, state)
			case "voice":
				return a.voiceBubble(gtx, f, m)
			case "audio":
				return a.audioBubble(gtx, m)
			case "sticker":
				return a.stickerBubble(gtx, f, m, state)
			case "location":
				return a.locationBubble(gtx, f, m)
			case "contact":
				return a.contactBubble(gtx, m)
			default:
				return a.fileBubble(gtx, m)
			}
		}))
		if live && state == engine.DownloadInProgress {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.downloadRow(gtx, st.recv, st.total)
			}))
		}
		if state == engine.DownloadFailed {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(10), "Download failed — tap to retry")
				lbl.Color = a.ui.p.Error
				return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, lbl.Layout)
			}))
		}
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
	})
	if btn.Clicked(gtx) {
		a.actMedia(gtx, m, state)
	}
	return dims
}

func (a *App) actMedia(gtx layout.Context, m *engine.CachedMessage, state int) {
	a.mu.Lock()
	selOn := a.selOn
	a.mu.Unlock()
	if selOn {
		a.toggleMsgSel(m.MsgID)
		return
	}
	msg := *m
	switch msg.MediaType {
	case engine.MediaLocation:
		if g := parseGeoMessage(&msg); g != nil {
			a.copyTextSoon(g.mapsURL())
		}
		return
	case engine.MediaContact:
		if c := parseContactMessage(&msg); c != nil && c.Phone != "" {
			a.copyTextSoon(c.Phone)
		}
		return
	}
	switch state {
	case engine.DownloadNone, engine.DownloadFailed:
		if msg.MediaType == engine.MediaVideoNote {
			if a.startStreamedVideoNote(&msg) {
				return
			}
			a.setPlayOnDone(msg.AccountID, msg.ChatID, msg.MsgID, 0)
		} else {
			a.setOpenOnDone(msg.AccountID, msg.ChatID, msg.MsgID, 0)
		}
		go func() {
			if err := a.eng.RequestDownload(msg.AccountID, msg.ChatID, msg.MsgID, 0, 0); err != nil {
				a.setToast("Download failed: " + err.Error())
			}
		}()
	case engine.DownloadInProgress:
		go func() { a.eng.CancelDownload(msg.AccountID, msg.ChatID, msg.MsgID, 0) }()
	default:
		switch msg.MediaType {
		case engine.MediaImage, engine.MediaGIF, engine.MediaVideo:
			a.openViewerFromMsg(gtx, &msg)
		case engine.MediaVideoNote:
			if !a.tapVideoNote(&msg) {
				a.openViewerFromMsg(gtx, &msg)
			}
		case engine.MediaSticker, engine.MediaDice:
			if msg.MediaType == engine.MediaDice &&
				(state == engine.DownloadNone || state == engine.DownloadFailed) {
				a.ensureDiceSticker(&msg)
				return
			}
			switch stickerRenderKind(&msg) {
			case stickerKindTgs:
				a.replaySticker(&msg)
			case stickerKindStatic:
				if msg.MediaLocalPath != "" && isDisplayableImage(msg.MediaLocalPath) {
					a.openViewerFromMsg(gtx, &msg)
				} else if msg.MediaLocalPath != "" {
					a.openMedia(msg.MediaLocalPath, true)
				}
			default:
				a.replayWebmSticker(&msg)
			}
		case engine.MediaVoice, engine.MediaAudio:
			if msg.MediaLocalPath != "" && engine.IsInAppPlayable(msg.MediaLocalPath) {
				a.toggleVoicePlayback(&msg)
			} else if msg.MediaLocalPath != "" {
				a.openMedia(msg.MediaLocalPath, true)
			}
		default:
			if msg.MediaLocalPath != "" {
				a.openMedia(msg.MediaLocalPath, true)
			}
		}
	}
}

func (a *App) markAutoDl(msgID string) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.autoDl == nil {
		a.autoDl = make(map[string]bool)
	}
	if a.autoDl[msgID] {
		return false
	}
	a.autoDl[msgID] = true
	return true
}

func (a *App) photoBubble(gtx layout.Context, f frame, m *engine.CachedMessage, state int) layout.Dimensions {
	maxW := gtx.Dp(unit.Dp(280))
	if avail := gtx.Constraints.Max.X; avail > 0 && avail < maxW {
		maxW = avail
	}
	maxH := gtx.Dp(unit.Dp(360))

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
	if img != nil {
		return drawImageScaled(gtx, img, maxW, maxH, 8)
	}

	w0, h0 := m.MediaWidth, m.MediaHeight
	if w0 <= 0 || h0 <= 0 {
		w0, h0 = 4, 3
	}
	capW := maxW
	if capW > gtx.Dp(unit.Dp(220)) {
		capW = gtx.Dp(unit.Dp(220))
	}
	w, h := fitDims(w0, h0, capW, gtx.Dp(unit.Dp(165)))
	return a.mediaPlaceholder(gtx, m, w, h)
}

func (a *App) videoBubble(gtx layout.Context, f frame, m *engine.CachedMessage, state int) layout.Dimensions {
	if m.MediaType == engine.MediaVideoNote {
		return a.videoNoteBubble(gtx, f, m)
	}

	maxW := gtx.Dp(unit.Dp(280))
	if avail := gtx.Constraints.Max.X; avail > 0 && avail < maxW {
		maxW = avail
	}
	maxH := gtx.Dp(unit.Dp(220))

	var img *image.RGBA
	if m.MediaThumbB64 != "" {
		key := "thumb:" + m.MediaThumbB64
		if img = mediaImgs.get(key); img == nil {
			a.decodeThumbAsync(key, m.MediaThumbB64)
		}
	}

	if img == nil {
		w0, h0 := m.MediaWidth, m.MediaHeight
		if w0 <= 0 || h0 <= 0 {
			w0, h0 = 16, 9
		}
		w, h := fitDims(w0, h0, gtx.Dp(unit.Dp(220)), gtx.Dp(unit.Dp(124)))
		return layout.Stack{Alignment: layout.Center}.Layout(gtx,
			layout.Stacked(func(gtx layout.Context) layout.Dimensions {
				return a.mediaPlaceholder(gtx, m, w, h)
			}),
			layout.Stacked(func(gtx layout.Context) layout.Dimensions {
				return drawPlayBadge(gtx, gtx.Dp(unit.Dp(56)))
			}),
			layout.Expanded(func(gtx layout.Context) layout.Dimensions {
				return a.durationBadge(gtx, m)
			}),
		)
	}

	return layout.Stack{Alignment: layout.Center}.Layout(gtx,
		layout.Stacked(func(gtx layout.Context) layout.Dimensions {
			return drawImageScaled(gtx, img, maxW, maxH, 8)
		}),
		layout.Stacked(func(gtx layout.Context) layout.Dimensions {
			return drawPlayBadge(gtx, gtx.Dp(unit.Dp(56)))
		}),
		layout.Expanded(func(gtx layout.Context) layout.Dimensions {
			return a.durationBadge(gtx, m)
		}),
	)
}

func (a *App) videoNoteBubble(gtx layout.Context, f frame, m *engine.CachedMessage) layout.Dimensions {
	d := gtx.Dp(unit.Dp(190))
	if dims, ok := a.drawVideoNoteFrame(gtx, m.MsgID, d); ok {
		return dims
	}
	var img *image.RGBA
	if m.MediaThumbB64 != "" {
		key := "thumb:" + m.MediaThumbB64
		if img = mediaImgs.get(key); img == nil {
			a.decodeThumbAsync(key, m.MediaThumbB64)
		}
	}
	if img == nil {
		return layout.Stack{Alignment: layout.Center}.Layout(gtx,
			layout.Stacked(func(gtx layout.Context) layout.Dimensions {
				return a.mediaPlaceholder(gtx, m, d, d)
			}),
			layout.Stacked(func(gtx layout.Context) layout.Dimensions {
				return drawPlayBadge(gtx, gtx.Dp(unit.Dp(56)))
			}),
		)
	}
	return layout.Stack{Alignment: layout.Center}.Layout(gtx,
		layout.Stacked(func(gtx layout.Context) layout.Dimensions {
			return drawImageEllipse(gtx, img, d)
		}),
		layout.Stacked(func(gtx layout.Context) layout.Dimensions {
			return drawPlayBadge(gtx, gtx.Dp(unit.Dp(56)))
		}),
	)
}

func (a *App) durationBadge(gtx layout.Context, m *engine.CachedMessage) layout.Dimensions {
	if m.MediaDuration <= 0 {
		return layout.Dimensions{}
	}
	return layout.Stack{Alignment: layout.SE}.Layout(gtx,
		layout.Stacked(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Right: unit.Dp(8), Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return roundedFill(gtx, color.NRGBA{A: 0xB0}, 8, func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(6), Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(10), fmtDur(m.MediaDuration))
						lbl.Color = color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF}
						return lbl.Layout(gtx)
					})
				})
			})
		}),
	)
}

func (a *App) voiceBubble(gtx layout.Context, f frame, m *engine.CachedMessage) layout.Dimensions {
	st := a.eng.MediaState()
	active := st.Playing || st.Paused
	mine := active && st.AccountID == m.AccountID && st.ChatID == m.ChatID && st.MsgID == m.MsgID
	playing := mine && st.Playing && !st.Paused

	total := float64(m.MediaDuration)
	if mine && st.Duration > 0 {
		total = st.Duration
	}
	pos := 0.0
	if mine {
		pos = st.Position
	}
	speed := 1.0
	if mine {
		speed = st.Speed
	}

	return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := a.mediaPlayClickable(m.AccountID + "|" + m.ChatID + "|" + m.MsgID)
				d := gtx.Dp(unit.Dp(44))
				if btn.Clicked(gtx) {
					a.toggleVoicePlayback(m)
				}
				return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					dims := btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						if playing {
							return drawPauseBadge(gtx, d)
						}
						return drawPlayBadge(gtx, d)
					})
					a.startPlaybackTickerIfNeeded()
					return dims
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.voiceWaveform(gtx, m, pos, total, playing, mine)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Label(unit.Sp(12), fmtPlaybackTime(pos, total))
									return lbl.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									sub := "Voice message"
									if m.MediaFileSize > 0 {
										sub += " · " + fmtBytes(m.MediaFileSize)
									}
									lbl := a.ui.Dim(unit.Sp(10), sub)
									return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, lbl.Layout)
								}),
							)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.transcriptBlock(gtx, m)
					}),
				)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				clk := a.mediaPlayClickable(m.AccountID + "|" + m.ChatID + "|" + m.MsgID + "|speed")
				if clk.Clicked(gtx) {
					a.eng.CycleMediaSpeed()
				}
				return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return clk.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return drawSpeedChip(gtx, a.ui, a.ui.p.Accent, speed)
					})
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if !transcribeWanted(m, f.transcribeCap) {
					return layout.Dimensions{}
				}
				clk := a.transcribeClickable(transcriptKey(m))
				if clk.Clicked(gtx) {
					a.transcribeVoiceNote(m)
				}
				return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return clk.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return drawTranscribeGlyph(gtx, a.ui, a.ui.p.AccentDim, a.ui.p.Text)
					})
				})
			}),
		)
	})
}

func (a *App) toggleVoicePlayback(m *engine.CachedMessage) {
	st := a.eng.MediaState()
	mine := (st.Playing || st.Paused) && st.AccountID == m.AccountID && st.ChatID == m.ChatID && st.MsgID == m.MsgID
	if mine {
		a.eng.TogglePauseMedia()
		a.invalidate()
		return
	}
	if m.MediaLocalPath == "" {
		return
	}
	if !engine.IsInAppPlayable(m.MediaLocalPath) {
		if m.MediaLocalPath != "" {
			a.openMedia(m.MediaLocalPath, true)
		}
		return
	}
	go func() {
		if err := a.eng.PlayMedia(m.AccountID, m.ChatID, m.MsgID, m.MediaLocalPath); err != nil {
			a.setToast("Playback failed: " + err.Error())
			return
		}
		a.startPlaybackTickerIfNeeded()
	}()
	a.invalidate()
}

func (a *App) startPlaybackTickerIfNeeded() {
	a.mu.Lock()
	if a.mediaTickerOn {
		a.mu.Unlock()
		return
	}
	a.mediaTickerOn = true
	a.mu.Unlock()
	go func() {
		t := time.NewTicker(250 * time.Millisecond)
		defer t.Stop()
		for range t.C {
			st := a.eng.MediaState()
			if !st.Playing || st.Paused {
				a.mu.Lock()
				a.mediaTickerOn = false
				a.mu.Unlock()
				return
			}
			a.invalidate()
		}
	}()
}

func (a *App) voiceWaveform(gtx layout.Context, m *engine.CachedMessage, pos, total float64, playing, seekable bool) layout.Dimensions {
	const nBars = 44
	w := gtx.Dp(unit.Dp(150))
	h := gtx.Dp(unit.Dp(26))
	progress := 0.0
	if total > 0 {
		progress = pos / total
		if progress < 0 {
			progress = 0
		}
		if progress > 1 {
			progress = 1
		}
	}

	if seekable {
		key := m.AccountID + "|" + m.ChatID + "|" + m.MsgID + "|wave"
		tag := a.seekBarTag(key)
		stack := clip.Rect{Max: image.Pt(w, h)}.Push(gtx.Ops)
		event.Op(gtx.Ops, tag)
		for {
			ev, ok := gtx.Source.Event(pointer.Filter{Target: tag, Kinds: pointer.Press | pointer.Drag | pointer.Release})
			if !ok {
				break
			}
			pe, is := ev.(pointer.Event)
			if !is {
				continue
			}
			switch pe.Kind {
			case pointer.Press, pointer.Drag, pointer.Release:
				f := seekFraction(pe.Position.X, w, progress)
				if last, ok := a.wid.seekBarApplied[key]; ok && absF64(f-last) < 0.005 && pe.Kind == pointer.Drag {
					continue
				}
				a.wid.seekBarApplied[key] = f
				_ = a.eng.SeekMedia(f)
				a.startPlaybackTickerIfNeeded()
				a.invalidate()
			}
		}
		stack.Pop()
	}

	wf := m.VoiceWaveform()
	amps := make([]float32, nBars)
	if len(wf) > 0 {
		mx := float32(1)
		for _, b := range wf {
			if float32(b) > mx {
				mx = float32(b)
			}
		}
		for i := 0; i < nBars; i++ {
			src := i * len(wf) / nBars
			amps[i] = float32(wf[src]) / mx
		}
	} else {
		for i := range amps {
			amps[i] = 0.35
		}
	}

	bw := float32(w) / float32(nBars)
	for i := 0; i < nBars; i++ {
		bh := amps[i] * float32(h)
		if bh < 2 {
			bh = 2
		}
		x := float32(i) * bw
		col := a.ui.p.TextDim
		if float32(i)/float32(nBars) <= float32(progress) && progress > 0 {
			col = a.ui.p.Accent
			col.A = 0xFF
		}
		bar := clip.UniformRRect(image.Rect(0, 0, max(int(bw-bw*0.35), 1), int(bh)), 1).Push(gtx.Ops)
		paint.FillShape(gtx.Ops, col, clip.Rect{
			Min: image.Pt(int(x), int((float32(h)-bh)/2)),
			Max: image.Pt(int(x)+max(int(bw-bw*0.35), 1), int((float32(h)+bh)/2)),
		}.Op())
		bar.Pop()
	}
	if playing {
		gtx.Execute(op.InvalidateCmd{At: time.Now().Add(250 * time.Millisecond)})
	}
	return layout.Dimensions{Size: image.Pt(w, h)}
}

func fmtPlaybackTime(pos, total float64) string {
	p := fmtDur(int(pos + 0.5))
	t := fmtDur(int(total + 0.5))
	return p + " / " + t
}

func drawPauseBadge(gtx layout.Context, diameter int) layout.Dimensions {
	if diameter <= 0 {
		return layout.Dimensions{}
	}
	c := float32(diameter) / 2
	r := c - 1

	circle := clip.Ellipse{Min: image.Pt(0, 0), Max: image.Pt(diameter, diameter)}.Push(gtx.Ops)
	paint.Fill(gtx.Ops, color.NRGBA{A: 0x99})
	circle.Pop()

	s := r * 0.5
	for _, dx := range []float32{-s * 0.45, s * 0.25} {
		bar := clip.UniformRRect(image.Rect(0, 0, int(s*0.4), int(s*1.3)), 1).Push(gtx.Ops)
		paint.FillShape(gtx.Ops, color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF}, clip.Rect{
			Min: image.Pt(int(c+dx), int(c-s*0.65)),
			Max: image.Pt(int(c+dx+s*0.4), int(c+s*0.65)),
		}.Op())
		bar.Pop()
	}
	return layout.Dimensions{Size: image.Pt(diameter, diameter)}
}

func drawSpeedChip(gtx layout.Context, u *UI, accent color.NRGBA, speed float64) layout.Dimensions {
	lbl := u.Label(unit.Sp(10), fmtSpeed(speed))
	lbl.Color = accent
	return lbl.Layout(gtx)
}

func fmtSpeed(s float64) string {
	switch s {
	case 1:
		return "1×"
	case 1.5:
		return "1.5×"
	case 2:
		return "2×"
	case 0.5:
		return "0.5×"
	default:
		return fmt.Sprintf("%g×", s)
	}
}

func (a *App) mediaPlayClickable(key string) *widget.Clickable {
	if c, ok := a.wid.mediaPlayClickables[key]; ok {
		return c
	}
	if len(a.wid.mediaPlayClickables) > 512 {
		a.wid.mediaPlayClickables = make(map[string]*widget.Clickable)
	}
	c := new(widget.Clickable)
	a.wid.mediaPlayClickables[key] = c
	return c
}

func (a *App) audioBubble(gtx layout.Context, m *engine.CachedMessage) layout.Dimensions {
	title, performer := m.AudioMeta()
	if title == "" {
		title = mediaTitle(m)
	}
	st := a.eng.MediaState()
	mine := (st.Playing || st.Paused) && st.AccountID == m.AccountID && st.ChatID == m.ChatID && st.MsgID == m.MsgID && st.Duration > 0

	return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					if mine && st.Playing && !st.Paused {
						return drawPauseBadge(gtx, gtx.Dp(unit.Dp(32)))
					}
					if mine {
						return drawPlayBadge(gtx, gtx.Dp(unit.Dp(32)))
					}
					gtx.Constraints.Min.X = gtx.Dp(unit.Dp(28))
					return iconAVNote.Layout(gtx, a.ui.p.Accent)
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(13), title)
							lbl.MaxLines = 1
							return lbl.Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(10), audioSubLine(performer, m.MediaDuration, mine, st.Position, st.Duration, m.MediaFileSize))
							return lbl.Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							if !mine || st.Duration <= 0 {
								return layout.Dimensions{}
							}
							frac := 0.0
							if st.Duration > 0 {
								frac = st.Position / st.Duration
							}
							return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return a.seekBar(gtx, m.AccountID+"|"+m.ChatID+"|"+m.MsgID, frac)
							})
						}),
					)
				})
			}),
		)
	})
}

func (a *App) fileBubble(gtx layout.Context, m *engine.CachedMessage) layout.Dimensions {
	title := mediaTitle(m)
	if title == "" {
		title = engine.MediaPreviewLabel(m.MediaType)
	}
	return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				gtx.Constraints.Min.X = gtx.Dp(unit.Dp(28))
				return iconFileAttach.Layout(gtx, a.ui.p.TextDim)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(13), title)
							lbl.MaxLines = 2
							return lbl.Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							sub := ""
							if m.MediaFileSize > 0 {
								sub = fmtBytes(m.MediaFileSize)
							}
							if m.MediaWidth > 0 && m.MediaHeight > 0 {
								if sub != "" {
									sub += " · "
								}
								sub += itoa(m.MediaWidth) + "×" + itoa(m.MediaHeight)
							}
							lbl := a.ui.Dim(unit.Sp(10), sub)
							return lbl.Layout(gtx)
						}),
					)
				})
			}),
		)
	})
}

func mediaTitle(m *engine.CachedMessage) string {
	name := m.MediaFileName
	if name == "" {
		return ""
	}
	return strings.TrimSuffix(name, filepath.Ext(name))
}

func audioSubLine(performer string, msgDur int, mine bool, pos, liveDur float64, size int64) string {
	sub := fmtDur(msgDur)
	if mine {
		sub = fmtPlaybackTime(pos, liveDur)
	}
	if performer != "" {
		sub = performer + " · " + sub
	}
	if size > 0 {
		sub += " · " + fmtBytes(size)
	}
	return sub
}

func (a *App) mediaPlaceholder(gtx layout.Context, m *engine.CachedMessage, w, h int) layout.Dimensions {
	return roundedFill(gtx, a.ui.p.SurfaceHi, 8, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints = layout.Constraints{Min: image.Pt(w, h), Max: image.Pt(w, h)}
		return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(11), engine.MediaPreviewLabel(m.MediaType))
			lbl.Color = a.ui.p.TextFaint
			return lbl.Layout(gtx)
		})
	})
}

func (a *App) downloadRow(gtx layout.Context, recv, total int64) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(10), fmtBytes(recv)+" / "+fmtBytes(total))
				return lbl.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				w := gtx.Constraints.Max.X
				if w <= 0 {
					w = gtx.Dp(unit.Dp(120))
				}
				h := 3
				track := clip.Rect{Min: image.Pt(0, 0), Max: image.Pt(w, h)}.Push(gtx.Ops)
				paint.Fill(gtx.Ops, a.ui.p.SurfaceHi)
				track.Pop()
				fw := int(float32(w) * dlFraction(recv, total))
				if fw > 0 {
					if fw < h {
						fw = h
					}
					fill := clip.Rect{Min: image.Pt(0, 0), Max: image.Pt(fw, h)}.Push(gtx.Ops)
					paint.Fill(gtx.Ops, a.ui.p.Accent)
					fill.Pop()
				}
				return layout.Dimensions{Size: image.Pt(w, h)}
			}),
		)
	})
}
