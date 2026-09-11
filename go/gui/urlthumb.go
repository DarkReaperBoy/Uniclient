package gui

// urlthumb.go — slice 130: remote-URL thumbnails fetched through the
// engine's pure-Go HTTP image fetcher (engine.FetchHTTPImage). Same shape
// as gui/location.go's map-tile cache: claim → async fetch → decode →
// store → invalidate; failures pin an honest fallback (no retry churn).
//
// Consumers: the inline-bot results panel (BotInlineResult thumbs that
// arrive as plain http(s) URLs). Any later URL-referenced media (link
// previews on non-Telegram cores, GitHub avatars...) reuses this widget.

import (
	"bytes"
	"image"
	"strings"
	"sync"

	"gioui.org/layout"
	"gioui.org/unit"

	"uniclient/cores"
)

// inlineThumbCap bounds one URL thumb fetch (thumbs are small by nature).
const inlineThumbCap = 512 << 10 // 512 KiB

// validGUIFetchURL is the GUI's cheap pre-gate (the engine re-validates
// strictly): only http(s) URLs are fetch candidates.
func validGUIFetchURL(u string) bool {
	return strings.HasPrefix(u, "http://") || strings.HasPrefix(u, "https://")
}

// thumbSrc describes where a renderable thumb comes from.
type thumbSrc int

const (
	thumbSrcNone thumbSrc = iota
	thumbSrcB64           // stripped/inline base64 bytes (no network)
	thumbSrcURL           // remote http(s) image (engine fetcher)
)

// inlineThumbSource picks the thumb route for an inline-bot result: b64
// bytes first (delivered with the response), remote URL second, none last.
// Pure — unit-tested.
func inlineThumbSource(r cores.InlineBotResult) (thumbSrc, string) {
	if r.ThumbB64 != "" {
		return thumbSrcB64, ""
	}
	if validGUIFetchURL(r.ThumbURL) {
		return thumbSrcURL, r.ThumbURL
	}
	return thumbSrcNone, ""
}

// urlThumbCache memoizes decoded remote thumbs keyed by URL (mapTiles
// pattern: busy/failed maps guard the async fetch).
type urlThumbCache struct {
	mu     sync.Mutex
	imgs   map[string]*image.RGBA
	busy   map[string]bool
	failed map[string]bool
}

var urlThumbs = &urlThumbCache{
	imgs:   make(map[string]*image.RGBA),
	busy:   make(map[string]bool),
	failed: make(map[string]bool),
}

// get returns a cached decoded thumb (nil when absent).
func (c *urlThumbCache) get(key string) *image.RGBA {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.imgs[key]
}

// claim marks a fetch in-flight; false when one already runs, the thumb is
// cached, or the URL previously failed.
func (c *urlThumbCache) claim(key string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.busy[key] || c.failed[key] || c.imgs[key] != nil {
		return false
	}
	c.busy[key] = true
	return true
}

// store publishes a decoded thumb.
func (c *urlThumbCache) store(key string, img *image.RGBA) {
	c.mu.Lock()
	c.imgs[key], c.busy[key] = img, false
	c.mu.Unlock()
}

// fail pins the honest fallback for this URL (no retry churn).
func (c *urlThumbCache) fail(key string) {
	c.mu.Lock()
	c.busy[key], c.failed[key] = false, true
	c.mu.Unlock()
}

// ensureURLThumb kicks the async fetch+decode for one remote thumb.
func (a *App) ensureURLThumb(url string) {
	if url == "" || !urlThumbs.claim(url) {
		return
	}
	go func() {
		data, err := a.eng.FetchHTTPImage(url, inlineThumbCap)
		if err != nil || len(data) == 0 {
			urlThumbs.fail(url)
			return
		}
		img, _, derr := decodeGUIImage(data)
		if derr != nil {
			urlThumbs.fail(url)
			return
		}
		urlThumbs.store(url, imgToRGBA(img))
		a.invalidate()
	}()
}

// decodeGUIImage decodes image bytes with the registered decoders
// (stdlib jpeg/png/gif + x/image webp via custemoji.go's blank import).
func decodeGUIImage(data []byte) (image.Image, string, error) {
	return image.Decode(bytes.NewReader(data))
}

// urlThumb renders a remote thumb: cached image as a rounded square
// (cover-fit), the honest placeholder box while in flight or on failure.
func (a *App) urlThumb(gtx layout.Context, url string, sizeDp unit.Dp) layout.Dimensions {
	size := gtx.Dp(sizeDp)
	if url == "" || size <= 0 {
		return layout.Dimensions{}
	}
	if img := urlThumbs.get(url); img != nil {
		return drawImageRRectCover(gtx, img, size)
	}
	a.ensureURLThumb(url)
	// Reserve the box so rows/grid cells don't jump when the thumb lands.
	return layout.Dimensions{Size: image.Pt(size, size)}
}
