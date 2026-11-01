package gui

import (
	"image"
	"strconv"
	"time"

	"gioui.org/layout"
	"gioui.org/unit"
	_ "golang.org/x/image/webp"

	"uniclient/cores"
)

const customEmojiPlaceholder = "⭐"

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
		return t.ThumbB64
	}
	missing := make([]int64, 0, 4)
	missing = append(missing, docID)
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
			a.mu.Lock()
			a.customThumbs[docID] = cores.CustomEmojiThumb{DocumentID: docID}
			a.mu.Unlock()
		}
		a.invalidate()
	}()
	return ""
}

func (a *App) noteCustomThumbs(accountID string, docIDs []int64) {
	a.mu.Lock()
	a.customThumbWant = docIDs
	a.customThumbWantAcc = accountID
	a.mu.Unlock()
}

func customWantDocs(list []cores.Reaction) []int64 {
	var out []int64
	for _, r := range list {
		if r.Emoji == "" && r.DocumentID != 0 {
			out = append(out, r.DocumentID)
		}
	}
	return out
}

func customReactionKey(docID int64) string {
	return "custom_" + strconv.FormatInt(docID, 10)
}

const (
	reactionPathAnim   = "anim"
	reactionPathRaster = "raster"
	reactionPathThumb  = "thumb"
)

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
	case emojiArtVideo:
		if art.player != nil {
			return reactionPathAnim
		}
		return reactionPathThumb
	case emojiArtRaster:
		return reactionPathRaster
	}
	return reactionPathThumb
}

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
	}
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
