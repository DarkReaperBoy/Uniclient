package gui

import (
	"fmt"
	"image"
	"image/color"
	"os"
	"sync"
	"time"

	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/unit"

	"uniclient/engine"
	"uniclient/lottie"
)

const (
	stickerKindTgs = iota
	stickerKindWebm
	stickerKindStatic
)

func isTgsMime(mime string) bool {
	return mime == "application/x-tgsticker"
}

func gzipMagic(path string) bool {
	f, err := os.Open(path)
	if err != nil {
		return false
	}
	defer f.Close()
	var hdr [2]byte
	if n, err := f.Read(hdr[:]); err != nil || n < 2 {
		return false
	}
	return hdr[0] == 0x1f && hdr[1] == 0x8b
}

func stickerRenderKind(m *engine.CachedMessage) int {
	switch m.MediaMimeType {
	case "application/x-tgsticker":
		return stickerKindTgs
	case "video/webm+sticker":
		return stickerKindWebm
	case "image/webp":
		return stickerKindStatic
	}
	if m.MediaLocalPath != "" && gzipMagic(m.MediaLocalPath) {
		return stickerKindTgs
	}
	return stickerKindStatic
}

const (
	tgsMinFPS = 20
	tgsMaxFPS = 60
)

func tgsFrameInterval(fps float64) time.Duration {
	if fps < tgsMinFPS {
		fps = tgsMinFPS
	}
	if fps > tgsMaxFPS {
		fps = tgsMaxFPS
	}
	return time.Duration(float64(time.Second) / fps)
}

func tgsLoopFrame(anim *lottie.Animation, elapsed time.Duration) float64 {
	if anim == nil {
		return 0
	}
	dur := anim.Duration()
	if dur <= 0 {
		return anim.InPoint
	}
	e := elapsed % dur
	if e < 0 {
		e = 0
	}
	return anim.FrameAt(e)
}

func tgsFrameAt(anim *lottie.Animation, elapsed time.Duration, hold bool) float64 {
	if hold {
		if anim == nil {
			return 0
		}
		dur := anim.Duration()
		if dur > 0 && elapsed > dur {
			elapsed = dur
		}
		if elapsed < 0 {
			elapsed = 0
		}
		return anim.FrameAt(elapsed)
	}
	return tgsLoopFrame(anim, elapsed)
}

func stickerBox(maxSide, w0, h0 int) (int, int) {
	if maxSide <= 0 {
		return 0, 0
	}
	if w0 <= 0 || h0 <= 0 {
		return maxSide, maxSide
	}
	s := float64(maxSide) / float64(max(w0, h0))
	w := int(float64(w0)*s + 0.5)
	h := int(float64(h0)*s + 0.5)
	if w < 1 {
		w = 1
	}
	if h < 1 {
		h = 1
	}
	if w > maxSide {
		w = maxSide
	}
	if h > maxSide {
		h = maxSide
	}
	return w, h
}

type tgsPlayer struct {
	anim    *lottie.Animation
	start   time.Time
	path    string
	parsed  bool
	failed  bool
	reading bool
}

type tgsPlayerCache struct {
	mu      sync.Mutex
	players map[string]*tgsPlayer
}

var tgsPlayers = &tgsPlayerCache{players: make(map[string]*tgsPlayer)}

const tgsPlayerMax = 128

func (c *tgsPlayerCache) get(msgID string) *tgsPlayer {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p, ok := c.players[msgID]; ok {
		return p
	}
	if len(c.players) >= tgsPlayerMax {
		c.players = make(map[string]*tgsPlayer)
	}
	p := &tgsPlayer{}
	c.players[msgID] = p
	return p
}

func (c *tgsPlayerCache) setAnim(msgID, path string, anim *lottie.Animation) {
	c.mu.Lock()
	defer c.mu.Unlock()
	p := c.players[msgID]
	if p == nil {
		p = &tgsPlayer{}
		c.players[msgID] = p
	}
	p.anim, p.parsed, p.reading, p.failed = anim, true, false, false
	p.path = path
	p.start = time.Now()
}

func (c *tgsPlayerCache) reset(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p := c.players[msgID]; p != nil {
		p.anim, p.parsed, p.path, p.failed, p.reading = nil, false, "", false, false
	}
}

func (c *tgsPlayerCache) failParse(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	p := c.players[msgID]
	if p == nil {
		p = &tgsPlayer{}
		c.players[msgID] = p
	}
	p.failed, p.reading = true, false
}

func (c *tgsPlayerCache) replay(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p := c.players[msgID]; p != nil {
		p.start = time.Now()
	}
}

func (c *tgsPlayerCache) markReading(msgID string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	p := c.players[msgID]
	if p == nil {
		p = &tgsPlayer{}
		c.players[msgID] = p
	}
	if p.reading {
		return false
	}
	p.reading = true
	return true
}

func (c *tgsPlayerCache) endReading(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p := c.players[msgID]; p != nil {
		p.reading = false
	}
}

func parseTgsBytes(data []byte) (*lottie.Animation, bool) {
	anim, err := lottie.ParseTgs(data)
	if err != nil || anim == nil {
		return nil, false
	}
	if anim.Duration() <= 0 || len(anim.Layers) == 0 {
		return nil, false
	}
	return anim, true
}

func (a *App) ensureTgsAnim(m *engine.CachedMessage) {
	if m == nil || m.MediaLocalPath == "" {
		return
	}
	p := tgsPlayers.get(m.MsgID)
	if p.parsed && p.path != m.MediaLocalPath {
		tgsPlayers.reset(m.MsgID)
		p = tgsPlayers.get(m.MsgID)
	}
	if p.parsed || p.failed {
		return
	}
	if !tgsPlayers.markReading(m.MsgID) {
		return
	}
	msgID, path := m.MsgID, m.MediaLocalPath
	go func() {
		data, err := os.ReadFile(path)
		if err != nil {
			tgsPlayers.endReading(msgID)
			return
		}
		anim, ok := parseTgsBytes(data)
		if !ok {
			tgsPlayers.failParse(msgID)
			return
		}
		tgsPlayers.setAnim(msgID, path, anim)
		a.invalidate()
	}()
}

func (a *App) replaySticker(m *engine.CachedMessage) {
	if m == nil {
		return
	}
	tgsPlayers.replay(m.MsgID)
	a.invalidate()
}

func isBareStickerMsg(m *engine.CachedMessage) bool {
	if m == nil || m.IsService {
		return false
	}
	return (m.MediaType == engine.MediaSticker || m.MediaType == engine.MediaDice) &&
		m.ContentText == "" && !pollIsBody(m)
}

func autoDownloadable(mt int) bool {
	switch mt {
	case engine.MediaImage, engine.MediaGIF, engine.MediaSticker:
		return true
	}
	return false
}

func messageMetaLabel(m engine.CachedMessage, ayuEditedMark string) string {
	meta := msgTimeLabel(m.Timestamp)
	if m.EditedAt != 0 {
		meta = editedMark(ayuEditedMark) + msgTimeLabel(m.EditedAt)
	}
	if sm := scheduledMetaLabel(m); sm != "" {
		meta = sm + " · " + meta
	}
	return meta
}

func viewsCountLabel(n int) string {
	switch {
	case n < 1000:
		return itoa(n)
	case n < 10000:
		return fmt.Sprintf("%.1fK", float64(n)/1000)
	case n < 1000000:
		return itoa(n/1000) + "K"
	case n < 10000000:
		return fmt.Sprintf("%.1fM", float64(n)/1000000)
	default:
		return itoa(n/1000000) + "M"
	}
}

func (a *App) stickerBubble(gtx layout.Context, f frame, m *engine.CachedMessage, state int) layout.Dimensions {
	maxSide := gtx.Dp(unit.Dp(256))
	if avail := gtx.Constraints.Max.X; avail > 0 && avail < maxSide {
		maxSide = avail
	}

	kind := stickerRenderKind(m)

	if m.MediaType == engine.MediaDice {
		info, hasDice := parseDiceMessage(m)
		if !hasDice {
			return layout.Dimensions{}
		}
		if !diceAnimated(info.Emoji) {
			return a.diceFallback(gtx, info, state)
		}
		a.ensureDiceSticker(m)
		if state != engine.DownloadComplete || m.MediaLocalPath == "" {
			return a.diceFallback(gtx, info, state)
		}
	}

	hold := false
	if m.MediaType == engine.MediaDice {
		if info, ok := parseDiceMessage(m); ok {
			hold = diceHoldLastFrame(info.Value)
		}
	}
	if kind == stickerKindTgs && state == engine.DownloadComplete && m.MediaLocalPath != "" {
		a.ensureTgsAnim(m)
		p := tgsPlayers.get(m.MsgID)
		if p.parsed && p.anim != nil {
			w, h := stickerBox(maxSide, int(p.anim.Width), int(p.anim.Height))
			if w > 0 && h > 0 {
				elapsed := time.Since(p.start)
				if powerSavingBlocks(powerSaving.flags, powerSaving.forceAll, psClassStickers) {
					lottie.Draw(p.anim, 0, gtx.Ops, image.Rect(0, 0, w, h))
					return layout.Dimensions{Size: image.Pt(w, h)}
				}
				frame := tgsFrameAt(p.anim, elapsed, hold)
				lottie.Draw(p.anim, frame, gtx.Ops, image.Rect(0, 0, w, h))
				if !hold || elapsed < p.anim.Duration() {
					gtx.Execute(op.InvalidateCmd{At: time.Now().Add(tgsFrameInterval(p.anim.FrameRate))})
				}
				return layout.Dimensions{Size: image.Pt(w, h)}
			}
		}
	}

	if kind == stickerKindWebm && state == engine.DownloadComplete && m.MediaLocalPath != "" {
		a.ensureWebmPlayer(m)
		if dims, ok := a.drawWebmSticker(gtx, m, maxSide); ok {
			return dims
		}
	}

	if state == engine.DownloadComplete && m.MediaLocalPath != "" && isDisplayableImage(m.MediaLocalPath) {
		key := "file:" + m.MediaLocalPath
		if img := mediaImgs.get(key); img != nil {
			w, h := stickerBox(maxSide, img.Bounds().Dx(), img.Bounds().Dy())
			return drawImageScaled(gtx, img, w, h, 0)
		}
		a.decodeFileAsync(m.MediaLocalPath)
	}
	if m.MediaThumbB64 != "" {
		key := "thumb:" + m.MediaThumbB64
		if img := mediaImgs.get(key); img != nil {
			w, h := stickerBox(maxSide, img.Bounds().Dx(), img.Bounds().Dy())
			return drawImageScaled(gtx, img, w, h, 0)
		}
		a.decodeThumbAsync(key, m.MediaThumbB64)
	}

	w, h := stickerBox(maxSide, m.MediaWidth, m.MediaHeight)
	return layout.Dimensions{Size: image.Pt(w, h)}
}

func (a *App) bareStickerBubble(gtx layout.Context, f frame, m *engine.CachedMessage, out, deleted bool) layout.Dimensions {
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if m.ForwardFrom == "" {
				return layout.Dimensions{}
			}
			lbl := a.ui.Dim(unit.Sp(12), "Forwarded from "+m.ForwardFrom)
			lbl.Color = a.ui.p.TextFaint
			if f.cfg.Streamer {
				return a.masked(gtx, lbl.Layout)
			}
			return layout.Inset{Bottom: unit.Dp(3)}.Layout(gtx, lbl.Layout)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if m.ReplyPreview == "" {
				return layout.Dimensions{}
			}
			return a.replyQuote(gtx, f, *m, *f.msgFor)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Stack{Alignment: layout.SE}.Layout(gtx,
				layout.Stacked(func(gtx layout.Context) layout.Dimensions {
					return a.mediaBlock(gtx, f, m)
				}),
				layout.Stacked(func(gtx layout.Context) layout.Dimensions {
					return a.stickerMetaPill(gtx, f, m, out, deleted)
				}),
			)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if len(m.Reactions) == 0 {
				return layout.Dimensions{}
			}
			return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return a.reactionStrip(gtx, f, m)
			})
		}),
	)
}

func (a *App) stickerMetaPill(gtx layout.Context, f frame, m *engine.CachedMessage, out, deleted bool) layout.Dimensions {
	text := messageMetaLabel(*m, f.cfg.AyuEditedMark)
	if deleted {
		text = deletedMarkText("", f.cfg.AyuDeletedMark) + " " + text
	}
	pill := func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(6), Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(10), text)
					lbl.Color = color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF}
					return lbl.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if !out {
						return layout.Dimensions{}
					}
					return layout.Inset{Left: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return a.statusTicks(gtx, m.Status, f)
					})
				}),
			)
		})
	}
	return roundedFill(gtx, color.NRGBA{A: 0x55}, unit.Dp(8), pill)
}
