package gui

// tgsplayer.go — slice 123: animated .tgs sticker playback in the chat
// (on top of the pure-Go lottie engine, slice 122 A/B/C). Telegram
// animated stickers are gzip-compressed Lottie JSON; once the document
// downloads, it parses once per message and renders on the frame clock:
// each painted frame schedules the next window invalidation at the
// animation's own rate (clamped 20..60fps), looping at the animation
// duration. Taps replay from frame 0 (AyuGram behavior). Static .webp
// stickers render from the downloaded file (webp decode registered by
// custemoji.go) with the inline thumb as the pre-download fallback;
// .webm video stickers honestly stay at their thumbnail (no webm decoder
// in pure Go yet) and hand off to the system player on tap (§1.10).
//
// Sticker messages also render WITHOUT the chat-bubble chrome (AyuGram:
// bare artwork with a translucent meta pill overlaid bottom-right) — see
// bareStickerBubble, wired from messageRow.

import (
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

// ── kind detection ────────────────────────────────────────────────────────

// Sticker render paths.
const (
	stickerKindTgs    = iota // animated: application/x-tgsticker (gzip Lottie)
	stickerKindWebm          // video sticker: video/webm (no decoder — thumb only)
	stickerKindStatic        // static webp (or unknown): image decode path
)

// isTgsMime reports the Telegram animated-sticker mime.
func isTgsMime(mime string) bool {
	return mime == "application/x-tgsticker"
}

// gzipMagic reports whether the file at path starts with the gzip magic
// (0x1f 0x8b) — the .tgs container sniff. Missing/short files are not gzip.
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

// stickerRenderKind picks the render path for a sticker message: the mime
// decides when present; otherwise the local file is sniffed for the gzip
// container (animated); everything else renders statically.
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

// ── playback math (pure) ──────────────────────────────────────────────────

// Frame-rate clamps for the invalidation clock: never redraw slower than
// 20fps (visible stutter) nor faster than 60fps (burning CPU for nothing).
const (
	tgsMinFPS = 20
	tgsMaxFPS = 60
)

// tgsFrameInterval returns the redraw interval for an animation frame rate.
func tgsFrameInterval(fps float64) time.Duration {
	if fps < tgsMinFPS {
		fps = tgsMinFPS
	}
	if fps > tgsMaxFPS {
		fps = tgsMaxFPS
	}
	return time.Duration(float64(time.Second) / fps)
}

// tgsLoopFrame maps an elapsed play time to the looping frame number.
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

// tgsFrameAt resolves the frame for an elapsed time, looping by default
// or holding the final frame (dice outcomes rest on their value face).
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

// stickerBox returns the pixel box for a sticker of w0×h0 animation units
// inside a maxSide square (AyuGram sticker size ~256dp), aspect-true with
// a square fallback for degenerate dims.
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

// ── per-message player cache ──────────────────────────────────────────────

// tgsPlayer is one message's parsed animation + play clock.
type tgsPlayer struct {
	anim    *lottie.Animation
	start   time.Time
	path    string // source file (a changed path re-parses: dice value swaps)
	parsed  bool   // anim successfully parsed (anim != nil)
	failed  bool   // permanently unplayable (bad container/document)
	reading bool   // async file read + parse in flight
}

// tgsPlayerCache keeps per-msgID players; pruned wholesale when oversized
// (same policy as a.wid.mediaClicks — scrolling chats churn entries).
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

// setAnim publishes a parsed animation and starts its clock.
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

// reset clears a parsed animation (new source file for the message).
func (c *tgsPlayerCache) reset(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p := c.players[msgID]; p != nil {
		p.anim, p.parsed, p.path, p.failed, p.reading = nil, false, "", false, false
	}
}

// failParse pins the message to the static fallback (no re-parse churn).
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

// replay restarts the play clock from frame 0.
func (c *tgsPlayerCache) replay(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p := c.players[msgID]; p != nil {
		p.start = time.Now()
	}
}

// markReading claims the async read slot; false while one is in flight.
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

// endReading releases the read slot (retryable failures).
func (c *tgsPlayerCache) endReading(msgID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if p := c.players[msgID]; p != nil {
		p.reading = false
	}
}

// parseTgsBytes parses raw .tgs bytes, rejecting documents that cannot
// animate (parse error, no duration, no layers).
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

// ensureTgsAnim kicks off the one-time async parse of a downloaded .tgs
// document; repaints when the animation lands.
func (a *App) ensureTgsAnim(m *engine.CachedMessage) {
	if m == nil || m.MediaLocalPath == "" {
		return
	}
	p := tgsPlayers.get(m.MsgID)
	if p.parsed && p.path != m.MediaLocalPath {
		// New file for the same message (dice value swap): re-parse.
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
			tgsPlayers.endReading(msgID) // retry on a later frame
			return
		}
		anim, ok := parseTgsBytes(data)
		if !ok {
			tgsPlayers.failParse(msgID) // static fallback, permanently
			return
		}
		tgsPlayers.setAnim(msgID, path, anim)
		a.invalidate()
	}()
}

// replaySticker restarts an animated sticker from frame 0 (tap action).
func (a *App) replaySticker(m *engine.CachedMessage) {
	if m == nil {
		return
	}
	tgsPlayers.replay(m.MsgID)
	a.invalidate()
}

// ── gating helpers ────────────────────────────────────────────────────────

// isBareStickerMsg reports whether a message renders without the chat
// bubble chrome (AyuGram: bare sticker artwork). Stickers with captions,
// service rows and poll bodies keep the regular bubble.
func isBareStickerMsg(m *engine.CachedMessage) bool {
	if m == nil || m.IsService {
		return false
	}
	return (m.MediaType == engine.MediaSticker || m.MediaType == engine.MediaDice) &&
		m.ContentText == "" && !pollIsBody(m)
}

// autoDownloadable reports which media types prefetch as they scroll into
// view (AyuGram auto-download): photos, GIFs and stickers (all small).
func autoDownloadable(mt int) bool {
	switch mt {
	case engine.MediaImage, engine.MediaGIF, engine.MediaSticker:
		return true
	}
	return false
}

// messageMetaLabel builds the meta line (time, edited mark, scheduled
// prefix) shared by the in-bubble meta row and the sticker overlay pill.
func messageMetaLabel(m engine.CachedMessage, ayuEditedMark string) string {
	// Ayu showMessageSeconds (slice 173): message meta times carry
	// seconds when the toggle is on (formatMessageTime semantics).
	meta := msgTimeLabel(m.Timestamp)
	if m.EditedAt != 0 {
		meta = editedMark(ayuEditedMark) + msgTimeLabel(m.EditedAt)
	}
	if sm := scheduledMetaLabel(m); sm != "" {
		meta = sm + " · " + meta
	}
	return meta
}

// ── widgets ───────────────────────────────────────────────────────────────

// stickerBubble renders a sticker media block (~256dp): the animated frame
// when a .tgs is parsed, the downloaded static image when complete, the
// inline thumbnail otherwise. Drives its own repaint clock while animating.
func (a *App) stickerBubble(gtx layout.Context, f frame, m *engine.CachedMessage, state int) layout.Dimensions {
	maxSide := gtx.Dp(unit.Dp(256))
	if avail := gtx.Constraints.Max.X; avail > 0 && avail < maxSide {
		maxSide = avail
	}

	kind := stickerRenderKind(m)

	// Dice messages resolve their pack document through the engine before
	// the download pipeline can run; the emoji glyph is the honest
	// pre-download state (slot machines stay textual — no fake collage).
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

	// Animated: parse once the document is local, then draw the looping
	// frame on the animation's own clock (dice outcomes hold their final
	// frame instead of looping).
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
				// Power saving (slice 135): the first frame renders
				// statically with no re-arm — loops are the battery cost.
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

	// Static (or animated-but-not-yet-parsed): the downloaded file when it
	// is a decodable image, else the inline thumbnail.
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

	// Honest placeholder box (aspect from the document dims) while the
	// thumb decodes; tapped downloads reveal real pixels.
	w, h := stickerBox(maxSide, m.MediaWidth, m.MediaHeight)
	return layout.Dimensions{Size: image.Pt(w, h)}
}

// bareStickerBubble lays out a sticker message without the bubble chrome:
// forwarded header and reply quote keep their own surfaces, the artwork
// renders bare with a translucent meta pill overlaid at its bottom-right
// (Telegram/AyuGram sticker look), reactions strip below.
func (a *App) bareStickerBubble(gtx layout.Context, f frame, m *engine.CachedMessage, out, deleted bool) layout.Dimensions {
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		// Forwarded-from header (bare, dim).
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
		// Reply quote (own surface).
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if m.ReplyPreview == "" {
				return layout.Dimensions{}
			}
			return a.replyQuote(gtx, f, *m, *f.msgFor)
		}),
		// Artwork + meta pill overlay.
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
		// Reactions strip.
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

// stickerMetaPill renders the translucent time (+ticks) overlay pill.
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
