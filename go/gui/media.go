package gui

import (
	"bytes"
	"encoding/base64"
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

	"gioui.org/f32"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"

	"uniclient/engine"
)

// Media bubbles + download progress (AyuGram parity, research/ayugram_parity.md
// §5 "Media"): photo/video/voice/audio/file bubble rendering driven by the
// engine media pipeline (RequestDownload / EventDownloadProgress / Complete /
// Failed). Thumbnails come inline with the message (Telegram stripped JPEGs,
// already inflated to valid JPEG by the core); the full file swaps in once
// downloaded. Nothing renders a state the engine cannot back (§1.10).

// ── download bookkeeping ──────────────────────────────────────────────────

// dlState mirrors one download's live progress for a bubble.
type dlState struct {
	recv, total int64
	state       int // engine.Download* constants
}

func dlKey(accountID, chatID, msgID string, seq int) string {
	return accountID + "|" + chatID + "|" + msgID + "|" + strconv.Itoa(seq)
}

// dlActive reports whether any download is transferring right now (drives the
// progress-bar animation invalidation).
func dlActive(dls map[string]dlState) bool {
	for _, d := range dls {
		if d.state == engine.DownloadInProgress {
			return true
		}
	}
	return false
}

// dlFraction clamps recv/total into 0..1.
func dlFraction(recv, total int64) float32 {
	if total <= 0 || recv <= 0 {
		return 0
	}
	if recv >= total {
		return 1
	}
	return float32(recv) / float32(total)
}

// fmtBytes renders AyuGram-style sizes ("1.5 KB", "2.4 MB").
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

// fmtDur renders a duration as m:ss / h:mm:ss.
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

// ── decoded-image cache (thumbs + files) ──────────────────────────────────

// mediaImg caches decoded images keyed by "thumb:<b64>" / "file:<path>".
// Decoding happens off the frame thread; frames only look up. The cache is
// reset (not LRU-evicted) when it outgrows a full chat of bubbles — keys are
// stable, so a later frame re-decodes what it needs.
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

// start claims a decode slot; false while a decode for the key is in flight.
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

// imgToRGBA converts any decoded image to the GPU-friendly RGBA layout.
func imgToRGBA(src image.Image) *image.RGBA {
	if rgba, ok := src.(*image.RGBA); ok {
		return rgba
	}
	b := src.Bounds()
	dst := image.NewRGBA(image.Rectangle{Max: b.Size()})
	draw.Draw(dst, dst.Bounds(), src, b.Min, draw.Src)
	return dst
}

// decodeImageAsync decodes raw image bytes off-thread, caches the result and
// invalidates so the bubble repaints with real pixels. Failed decodes release
// the pending claim so a retry is possible.
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
		img, _, err := image.Decode(bytes.NewReader(raw))
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

// imageExts are the formats the stdlib decoders here can display.
var imageExts = map[string]bool{".jpg": true, ".jpeg": true, ".png": true, ".gif": true}

// isDisplayableImage reports whether a local media path can be shown inline.
func isDisplayableImage(path string) bool {
	return imageExts[strings.ToLower(filepath.Ext(path))]
}

// ── drawing primitives ────────────────────────────────────────────────────

// fitScale returns the aspect-fit scale for w0×h0 inside maxW×maxH.
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

// fitDims returns the aspect-fit size for w0×h0 inside maxW×maxH (rounded,
// clamped; degenerate source falls back to the box).
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

// drawImageScaled paints img aspect-fit into a maxW×maxH box with rounded
// corners, linear filtering (thumbnail upscale, AyuGram-style).
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

// drawImageEllipse paints img scaled into a square, clipped to a circle
// (round video messages).
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

// drawPlayBadge renders a translucent circle with a white play triangle.
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

// ── bubble kinds ──────────────────────────────────────────────────────────

// mediaBlockKind maps an engine media type to the bubble kind rendering it.
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
	default:
		return "file"
	}
}

// mediaClicks pools whole-bubble clickables (msgID-keyed, pruned like
// reactionClicks when rows scroll away for good).
var mediaClicks = map[string]*widget.Clickable{}

func mediaClickable(key string) *widget.Clickable {
	if c, ok := mediaClicks[key]; ok {
		return c
	}
	if len(mediaClicks) > 512 {
		mediaClicks = make(map[string]*widget.Clickable)
	}
	c := new(widget.Clickable)
	mediaClicks[key] = c
	return c
}

// mediaBlock renders one message's media attachment and routes taps through
// the engine download pipeline: none/failed → download, in-progress → cancel,
// complete → reveal the local path (AyuGram bubble behavior).
func (a *App) mediaBlock(gtx layout.Context, f frame, m *engine.CachedMessage) layout.Dimensions {
	kind := mediaBlockKind(m.MediaType)

	// Live download state (event-fed) wins over the DB snapshot.
	st, live := f.downloads[dlKey(m.AccountID, m.ChatID, m.MsgID, 0)]
	state := m.MediaDownloadState
	if live {
		state = st.state
	}

	// AyuGram auto-downloads photos/GIFs as they scroll into view.
	if (m.MediaType == engine.MediaImage || m.MediaType == engine.MediaGIF) &&
		state == engine.DownloadNone && a.markAutoDl(m.MsgID) {
		msg := *m
		go func() {
			_ = a.eng.RequestDownload(msg.AccountID, msg.ChatID, msg.MsgID, 0, 2) // prefetch priority
		}()
	}

	btn := mediaClickable(m.MsgID)
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

// actMedia dispatches the tap for a media bubble.
func (a *App) actMedia(gtx layout.Context, m *engine.CachedMessage, state int) {
	msg := *m
	switch state {
	case engine.DownloadNone, engine.DownloadFailed:
		go func() {
			if err := a.eng.RequestDownload(msg.AccountID, msg.ChatID, msg.MsgID, 0, 0); err != nil {
				a.setToast("Download failed: " + err.Error())
			}
		}()
	case engine.DownloadInProgress:
		go func() { a.eng.CancelDownload(msg.AccountID, msg.ChatID, msg.MsgID, 0) }()
	default:
		// Complete: photos/GIFs/videos open the fullscreen viewer; other
		// types reveal the local path.
		switch msg.MediaType {
		case engine.MediaImage, engine.MediaGIF, engine.MediaVideo, engine.MediaVideoNote:
			a.openViewerFromMsg(gtx, &msg)
		default:
			if msg.MediaLocalPath != "" {
				a.setToast("Saved to " + msg.MediaLocalPath)
			}
		}
	}
}

// markAutoDl records that a prefetch was issued for a message this session so
// repaints don't re-enqueue it.
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

// ── kind bubbles ──────────────────────────────────────────────────────────

// photoBubble: the image itself, aspect-fit and rounded. Shows the inline
// thumbnail immediately; swaps to the downloaded file once it lands.
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

	// Decoding in flight or no thumb: aspect box from metadata.
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

// videoBubble: thumbnail with a play badge and duration pill; round video
// notes render as a circle.
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

// videoNoteBubble: round video message — circle thumbnail, centered play.
func (a *App) videoNoteBubble(gtx layout.Context, f frame, m *engine.CachedMessage) layout.Dimensions {
	d := gtx.Dp(unit.Dp(190))
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

// durationBadge renders the m:ss pill pinned to the bottom-right of its
// parent (used inside layout.Expanded).
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

// voiceBubble: play circle + duration + size.
func (a *App) voiceBubble(gtx layout.Context, f frame, m *engine.CachedMessage) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return drawPlayBadge(gtx, gtx.Dp(unit.Dp(44)))
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(13), fmtDur(m.MediaDuration))
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						sub := "Voice message"
						if m.MediaFileSize > 0 {
							sub += " · " + fmtBytes(m.MediaFileSize)
						}
						lbl := a.ui.Dim(unit.Sp(10), sub)
						return lbl.Layout(gtx)
					}),
				)
			}),
		)
	})
}

// audioBubble: music-file row (title, duration, size).
func (a *App) audioBubble(gtx layout.Context, m *engine.CachedMessage) layout.Dimensions {
	title := mediaTitle(m)
	return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				gtx.Constraints.Min.X = gtx.Dp(unit.Dp(28))
				return iconAVNote.Layout(gtx, a.ui.p.Accent)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(13), title)
							lbl.MaxLines = 1
							return lbl.Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							sub := fmtDur(m.MediaDuration)
							if m.MediaFileSize > 0 {
								sub += " · " + fmtBytes(m.MediaFileSize)
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

// fileBubble: generic document row — state icon, name, size.
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

// mediaTitle derives the bubble title from the file name (extension stripped).
func mediaTitle(m *engine.CachedMessage) string {
	name := m.MediaFileName
	if name == "" {
		return ""
	}
	return strings.TrimSuffix(name, filepath.Ext(name))
}

// mediaPlaceholder: the aspect box shown while a thumbnail decodes or when a
// message has no inline thumb.
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

// downloadRow: byte counter + thin progress bar under a downloading bubble.
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
