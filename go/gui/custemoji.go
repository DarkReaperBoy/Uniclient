package gui

import (
        "image"
        "strconv"

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
func (a *App) customReactionGlyph(gtx layout.Context, accountID string, docID int64) layout.Dimensions {
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
