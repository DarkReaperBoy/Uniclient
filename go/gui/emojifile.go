package gui

import (
	"image"
	"sync"
	"time"

	"gioui.org/layout"
	"gioui.org/op"

	"uniclient/cores"
	"uniclient/engine"
	"uniclient/lottie"
	"uniclient/vp9anim"
)

const (
	emojiArtUnknown = iota
	emojiArtRaster
	emojiArtLottie
	emojiArtVideo
	emojiArtUnsupported
)

func classifyEmojiArt(mime string) int {
	switch mime {
	case "application/x-tgsticker":
		return emojiArtLottie
	case "image/webp", "image/png", "image/jpeg":
		return emojiArtRaster
	case "video/webm":
		return emojiArtVideo
	default:
		return emojiArtUnsupported
	}
}

func customEmojiDocIDs(entities []cores.TextEntity) []int64 {
	var ids []int64
	seen := map[int64]bool{}
	for _, e := range entities {
		if e.Type != "custom_emoji" || e.DocumentID == 0 {
			continue
		}
		if seen[e.DocumentID] {
			continue
		}
		seen[e.DocumentID] = true
		ids = append(ids, e.DocumentID)
	}
	return ids
}

func emojiArtSide(fontPx int) int {
	if fontPx <= 0 {
		return 0
	}
	return (fontPx*135 + 50) / 100
}

type emojiArt struct {
	kind    int
	img     *image.RGBA
	anim    *lottie.Animation
	player  *vp9anim.Player
	vanim   *vp9anim.Animation
	start   time.Time
	failed  bool
	reading bool
}

type emojiArtCache struct {
	mu      sync.Mutex
	entries map[int64]*emojiArt
}

var emojiArts = &emojiArtCache{entries: make(map[int64]*emojiArt)}

const emojiArtMax = 512

func (c *emojiArtCache) get(docID int64) *emojiArt {
	c.mu.Lock()
	defer c.mu.Unlock()
	if e, ok := c.entries[docID]; ok {
		return e
	}
	if len(c.entries) >= emojiArtMax {
		for _, e := range c.entries {
			if e.player != nil {
				go e.player.Stop()
			}
		}
		c.entries = make(map[int64]*emojiArt)
	}
	e := &emojiArt{}
	c.entries[docID] = e
	return e
}

func (c *emojiArtCache) startReading(docID int64, e *emojiArt) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if e.reading {
		return false
	}
	e.reading = true
	return true
}

func resolveEmojiArtBytes(e *emojiArt, mime string, data []byte) bool {
	switch classifyEmojiArt(mime) {
	case emojiArtLottie:
		anim, parsed := parseTgsBytes(data)
		if !parsed {
			return false
		}
		e.anim, e.kind, e.start = anim, emojiArtLottie, time.Now()
		return true
	case emojiArtRaster:
		img, _, derr := decodeGUIImage(data)
		if derr != nil {
			return false
		}
		e.img, e.kind = imgToRGBA(img), emojiArtRaster
		return true
	case emojiArtVideo:
		anim, perr := vp9anim.Parse(data)
		if perr != nil || anim == nil || anim.FrameCount() == 0 {
			return false
		}
		pl := anim.NewPlayer()
		pl.Start()
		e.vanim, e.player, e.kind, e.start = anim, pl, emojiArtVideo, time.Now()
		return true
	}
	return false
}

func (a *App) ensureEmojiArt(m *engine.CachedMessage, entities []cores.TextEntity) {
	if m == nil {
		return
	}
	ids := customEmojiDocIDs(entities)
	if len(ids) == 0 {
		return
	}
	var missing []int64
	for _, id := range ids {
		e := emojiArts.get(id)
		if e.kind == emojiArtUnknown && !e.failed && emojiArts.startReading(id, e) {
			missing = append(missing, id)
		}
	}
	if len(missing) == 0 {
		return
	}
	key := m.AccountID + "|" + m.MsgID
	if a.emojiArtFetching == nil {
		a.emojiArtFetching = make(map[string]bool)
	}
	if a.emojiArtFetching[key] {
		return
	}
	a.emojiArtFetching[key] = true

	accountID := m.AccountID
	go func() {
		files, ferr := a.eng.GetCustomEmojiFiles(accountID, missing)
		_ = ferr
		byID := make(map[int64]cores.CustomEmojiFile, len(files))
		for _, f := range files {
			byID[f.DocumentID] = f
		}
		for _, id := range missing {
			e := emojiArts.get(id)
			f, ok := byID[id]
			switch {
			case !ok || len(f.FileData) == 0:
				e.failed = true
			case !resolveEmojiArtBytes(e, f.MimeType, f.FileData):
				e.kind = emojiArtUnsupported
				e.failed = true
			}
			e.reading = false
		}
		delete(a.emojiArtFetching, key)
		a.invalidate()
	}()
}

func drawEmojiArt(gtx layout.Context, e *emojiArt, side int) bool {
	if e == nil || side <= 0 {
		return false
	}
	switch e.kind {
	case emojiArtLottie:
		if e.anim == nil {
			return false
		}
		if powerSavingBlocks(powerSaving.flags, powerSaving.forceAll, psClassEmoji) {
			lottie.Draw(e.anim, 0, gtx.Ops, image.Rect(0, 0, side, side))
			return true
		}
		frame := tgsLoopFrame(e.anim, time.Since(e.start))
		lottie.Draw(e.anim, frame, gtx.Ops, image.Rect(0, 0, side, side))
		gtx.Execute(op.InvalidateCmd{At: time.Now().Add(tgsFrameInterval(e.anim.FrameRate))})
		return true
	case emojiArtRaster:
		if e.img == nil || e.img.Bounds().Empty() {
			return false
		}
		drawImageScaled(gtx, e.img, side, side, side/6)
		return true
	case emojiArtVideo:
		return drawWebmEmoji(gtx, e, side)
	}
	return false
}
