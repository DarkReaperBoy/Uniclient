package gui

// emojifile.go — slice 132: inline custom-emoji artwork in message text.
// MessageEntityCustomEmoji ranges currently render as their base emoji
// glyph; this file swaps in the real document artwork once fetched:
//
//   - .tgs (application/x-tgsticker) parses through the lottie player and
//     animates inline on a per-document clock (shared across messages);
//   - webp/png decode to RGBA and render statically at the same box;
//   - video/webm emoji have no pure-Go decoder (§1.1) and honestly stay
//     base-glyph text.
//
// Fetches ride engine.GetCustomEmojiFiles (batched, full document bytes)
// with one in-flight guard per message; failures pin per document (no
// retry churn). The richtext flow treats a ready emoji as a square token
// ~1.35x the font box (tdesktop proportions).

import (
	"image"
	"sync"
	"time"

	"gioui.org/layout"
	"gioui.org/op"

	"uniclient/cores"
	"uniclient/engine"
	"uniclient/lottie"
)

// emojiArt kinds.
const (
	emojiArtUnknown     = iota // not fetched yet
	emojiArtRaster             // webp/png decoded image
	emojiArtLottie             // tgs animation
	emojiArtUnsupported        // video/undecodable: base glyph fallback
)

// classifyEmojiArt maps a custom-emoji document mime to its render kind.
// Pure — unit-tested.
func classifyEmojiArt(mime string) int {
	switch mime {
	case "application/x-tgsticker":
		return emojiArtLottie
	case "image/webp", "image/png", "image/jpeg":
		return emojiArtRaster
	default:
		return emojiArtUnsupported // video/webm etc: honest fallback
	}
}

// customEmojiDocIDs collects the distinct custom-emoji document IDs of a
// message's entities (0 and duplicates dropped). Pure — unit-tested.
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

// emojiArtSide is the inline artwork box for a font pixel height
// (~1.35x, rounded; degenerate input → 0). Pure — unit-tested.
func emojiArtSide(fontPx int) int {
	if fontPx <= 0 {
		return 0
	}
	return (fontPx*135 + 50) / 100
}

// emojiArt is one document's resolved artwork.
type emojiArt struct {
	kind    int
	img     *image.RGBA       // raster kind
	anim    *lottie.Animation // lottie kind
	start   time.Time         // lottie clock origin
	failed  bool              // fetch/parse failed (pinned)
	reading bool              // fetch in flight
}

// emojiArtCache memoizes artwork per document ID (shared across messages
// and chats — premium emoji are per-document, not per-message).
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
		c.entries = make(map[int64]*emojiArt)
	}
	e := &emojiArt{}
	c.entries[docID] = e
	return e
}

// emojiArtBusy reports whether any entry is still resolving.
func (c *emojiArtCache) busy(docIDs []int64) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	for _, id := range docIDs {
		if e, ok := c.entries[id]; ok && e.reading {
			return true
		}
	}
	return false
}

// ensureEmojiArt fetches the missing artwork for a message's custom-emoji
// entities in one batched engine call (per-message in-flight guard).
func (a *App) ensureEmojiArt(m *engine.CachedMessage, entities []cores.TextEntity) {
	if m == nil {
		return
	}
	ids := customEmojiDocIDs(entities)
	if len(ids) == 0 {
		return
	}
	// Only the missing ones.
	var missing []int64
	for _, id := range ids {
		e := emojiArts.get(id)
		if e.kind == emojiArtUnknown && !e.failed && !e.reading {
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
		_ = ferr // per-document failures below cover the whole-batch miss
		byID := make(map[int64]cores.CustomEmojiFile, len(files))
		for _, f := range files {
			byID[f.DocumentID] = f
		}
		for _, id := range missing {
			e := emojiArts.get(id)
			f, ok := byID[id]
			if !ok || len(f.FileData) == 0 {
				e.failed = true
				continue
			}
			switch classifyEmojiArt(f.MimeType) {
			case emojiArtLottie:
				anim, parsed := parseTgsBytes(f.FileData)
				if !parsed {
					e.failed = true
					continue
				}
				e.anim, e.kind, e.start = anim, emojiArtLottie, time.Now()
			case emojiArtRaster:
				img, _, derr := decodeGUIImage(f.FileData)
				if derr != nil {
					e.failed = true
					continue
				}
				e.img, e.kind = imgToRGBA(img), emojiArtRaster
			default:
				e.kind = emojiArtUnsupported
			}
		}
		delete(a.emojiArtFetching, key)
		a.invalidate()
	}()
}

// drawEmojiArt paints one inline artwork into a side×side box (lottie:
// current frame + re-arm; raster: aspect-fit). Returns false when the
// entry is not renderable (caller falls back to the base glyph).
func drawEmojiArt(gtx layout.Context, e *emojiArt, side int) bool {
	if e == nil || side <= 0 {
		return false
	}
	switch e.kind {
	case emojiArtLottie:
		if e.anim == nil {
			return false
		}
		// Power saving (slice 135): first frame, no re-arm.
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
	}
	return false
}
