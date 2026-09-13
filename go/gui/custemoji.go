package gui

import (
	"image"
	"strconv"
	"time"

	"gioui.org/layout"
	"gioui.org/unit"
	_ "golang.org/x/image/webp" // register webp decoder (Telegram custom-emoji thumbs)

	"uniclient/cores"
)

// Custom-emoji reaction pills (AyuGram parity, matrix "Bubbles: reactions
// strip"): reactions with an empty Emoji but a DocumentID are premium
// custom-emoji reactions — their static thumbnails come from the engine's
// GetCustomEmojiThumbs (Telegram documents) and render inside the reaction
// pill. Thumbnails are cached for the session; unknown ones fetch lazily
// (batched per message render) and the pill shows a neutral placeholder
// until they land. Tapping a custom pill toggles the own reaction through
// the engine's "custom_<docID>" wire convention (tg.ReactionCustomEmoji).

// customEmojiPlaceholder is shown while a thumbnail loads (or when the
// platform can't provide one).
const customEmojiPlaceholder = "⭐"

// customThumbFor returns the cached thumbnail (base64) for a custom emoji,
// kicking a batched async fetch (once per document) when missing.
func (a *App) customThumbFor(accountID string, docID int64) string {
	if docID == 0 {
		return ""
	}
	a.mu.Lock()
	if a.customThumbs == nil {
		a.customThumbs = make(map[int64]cores.CustomEmojiThumb)
	}
	if a.customThumbsFetching == nil {
		a.customThumbsFetching = make(map[string]bool)
	}
	if t, ok := a.customThumbs[docID]; ok {
		a.mu.Unlock()
		// PathB64 is an SVG vector path, not a raster image — rasterizing
		// it is future work; render the placeholder instead.
		return t.ThumbB64
	}
	missing := make([]int64, 0, 4)
	missing = append(missing, docID)
	// Batch with other unknown custom reactions of the same message.
	if a.customThumbWant != nil && a.customThumbWantAcc == accountID {
		for _, id := range a.customThumbWant {
			if id != docID {
				if _, ok := a.customThumbs[id]; !ok {
					missing = append(missing, id)
				}
			}
		}
	}
	a.customThumbWant = nil
	a.customThumbWantAcc = ""
	key := accountID + "|" + strconv.FormatInt(docID, 10)
	if !a.customThumbsFetching[key] {
		a.customThumbsFetching[key] = true
	} else {
		// Another fetch in flight for this batch lead; wait for it.
		a.mu.Unlock()
		return ""
	}
	a.mu.Unlock()

	go func() {
		thumbs, err := a.eng.GetCustomEmojiThumbs(accountID, missing)
		a.mu.Lock()
		for _, t := range thumbs {
			a.customThumbs[t.DocumentID] = t
		}
		delete(a.customThumbsFetching, key)
		a.mu.Unlock()
		if err != nil {
			// Cache a miss so we don't retry every frame.
			a.mu.Lock()
			a.customThumbs[docID] = cores.CustomEmojiThumb{DocumentID: docID}
			a.mu.Unlock()
		}
		a.invalidate()
	}()
	return ""
}

// noteCustomThumbs registers the custom-reaction document ids a message
// wants (consumed by the next customThumbFor call to batch one fetch).
func (a *App) noteCustomThumbs(accountID string, docIDs []int64) {
	a.mu.Lock()
	a.customThumbWant = docIDs
	a.customThumbWantAcc = accountID
	a.mu.Unlock()
}

// customWantDocs collects the document ids of a strip's custom-emoji
// reactions (pure helper — also locked by tests).
func customWantDocs(list []cores.Reaction) []int64 {
	var out []int64
	for _, r := range list {
		if r.Emoji == "" && r.DocumentID != 0 {
			out = append(out, r.DocumentID)
		}
	}
	return out
}

// customReactionKey builds the engine wire key of a custom-emoji reaction
// (mirrors cores' tgReactionEmoji for tg.ReactionCustomEmoji).
func customReactionKey(docID int64) string {
	return "custom_" + strconv.FormatInt(docID, 10)
}

// customReactionGlyph renders the pill glyph for a custom-emoji reaction:
// the fetched static thumbnail (rounded, pill-sized) or the neutral
// placeholder while it loads — reserving the box so pills don't jump once
// the async decode lands.
// Reaction-glyph render paths (slice 183): animated custom-emoji
// reactions resolve through the shared emojiArts cache — lottie (TGS)
// documents animate frame-by-frame exactly like they do in message
// text (drawEmojiArt re-arms the frame clock); raster artwork draws
// aspect-fit; anything unresolved falls back to the static-thumb path.
const (
	reactionPathAnim   = "anim"
	reactionPathRaster = "raster"
	reactionPathThumb  = "thumb"
)

// reactionGlyphPath decides the render path for one artwork entry.
// Pure — unit-tested.
func reactionGlyphPath(art *emojiArt) string {
	if art == nil || art.failed {
		return reactionPathThumb
	}
	switch art.kind {
	case emojiArtLottie:
		if art.anim != nil {
			return reactionPathAnim
		}
		return reactionPathThumb
	case emojiArtRaster:
		// drawEmojiArt declines degenerate boxes itself (nil/empty
		// image) — the glyph caller then falls back to the static
		// thumb, so the path decision stays kind-based.
		return reactionPathRaster
	}
	return reactionPathThumb
}

// reactionAnimSide: the animated glyph box (125% of the old static
// thumb size, +2dp floor). Pure — unit-tested.
func reactionAnimSide(thumbDp int) int {
	if thumbDp <= 0 {
		return 20
	}
	side := thumbDp * 125 / 100
	if side < thumbDp+2 {
		side = thumbDp + 2
	}
	return side
}

// ensureReactionEmojiArt fetches one custom-emoji document's artwork
// through the shared emojiArts cache (once per doc; guards per
// account+doc). Mirrors ensureEmojiArt's body for the reaction path.
func (a *App) ensureReactionEmojiArt(accountID string, docID int64) {
	if accountID == "" || docID == 0 {
		return
	}
	e := emojiArts.get(docID)
	if e.kind != emojiArtUnknown || e.failed || e.reading {
		return
	}
	if a.emojiArtFetching == nil {
		a.emojiArtFetching = make(map[string]bool)
	}
	key := accountID + "|react|" + strconv.FormatInt(docID, 10)
	if a.emojiArtFetching[key] {
		return
	}
	a.emojiArtFetching[key] = true
	go func() {
		files, _ := a.eng.GetCustomEmojiFiles(accountID, []int64{docID})
		var f cores.CustomEmojiFile
		if len(files) > 0 {
			f = files[0]
		}
		e := emojiArts.get(docID)
		delete(a.emojiArtFetching, key)
		if f.DocumentID == 0 || len(f.FileData) == 0 {
			e.failed = true
			a.invalidate()
			return
		}
		switch classifyEmojiArt(f.MimeType) {
		case emojiArtLottie:
			anim, parsed := parseTgsBytes(f.FileData)
			if !parsed {
				e.failed = true
				break
			}
			e.anim, e.kind, e.start = anim, emojiArtLottie, time.Now()
		case emojiArtRaster:
			img, _, derr := decodeGUIImage(f.FileData)
			if derr != nil {
				e.failed = true
				break
			}
			e.img, e.kind = imgToRGBA(img), emojiArtRaster
		default:
			e.kind = emojiArtUnsupported
		}
		a.invalidate()
	}()
}

func (a *App) customReactionGlyph(gtx layout.Context, accountID string, docID int64) layout.Dimensions {
	a.ensureReactionEmojiArt(accountID, docID)
	switch reactionGlyphPath(emojiArts.get(docID)) {
	case reactionPathAnim, reactionPathRaster:
		side := gtx.Dp(unit.Dp(reactionAnimSide(16)))
		if drawEmojiArt(gtx, emojiArts.get(docID), side) {
			return layout.Dimensions{Size: image.Pt(side, side)}
		}
		// drawEmojiArt declined (degenerate box): fall through to the
		// static-thumb path.
	}
	// Static-thumb fallback (unresolved yet, or raster/lottie that
	// failed to decode) — the slice-53 behavior.
	b64 := a.customThumbFor(accountID, docID)
	if b64 == "" {
		return a.ui.Label(unit.Sp(13), customEmojiPlaceholder).Layout(gtx)
	}
	img := a.avatarImage("", b64)
	if img == nil {
		return layout.Dimensions{Size: image.Pt(gtx.Dp(unit.Dp(16)), gtx.Dp(unit.Dp(16)))}
	}
	return drawImageRRectCover(gtx, img, gtx.Dp(unit.Dp(16)))
}
