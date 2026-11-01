package gui

import (
	"bytes"
	"image"
	"strings"
	"sync"

	"gioui.org/layout"
	"gioui.org/unit"

	"uniclient/cores"
	"uniclient/utils"
)

const inlineThumbCap = 512 << 10

const guiMaxImagePixels = 40_000_000

func validGUIFetchURL(u string) bool {
	return strings.HasPrefix(u, "http://") || strings.HasPrefix(u, "https://")
}

type thumbSrc int

const (
	thumbSrcNone thumbSrc = iota
	thumbSrcB64
	thumbSrcURL
)

func inlineThumbSource(r cores.InlineBotResult) (thumbSrc, string) {
	if r.ThumbB64 != "" {
		return thumbSrcB64, ""
	}
	if validGUIFetchURL(r.ThumbURL) {
		return thumbSrcURL, r.ThumbURL
	}
	return thumbSrcNone, ""
}

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

func (c *urlThumbCache) get(key string) *image.RGBA {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.imgs[key]
}

func (c *urlThumbCache) claim(key string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.busy[key] || c.failed[key] || c.imgs[key] != nil {
		return false
	}
	c.busy[key] = true
	return true
}

func (c *urlThumbCache) store(key string, img *image.RGBA) {
	c.mu.Lock()
	c.imgs[key], c.busy[key] = img, false
	c.mu.Unlock()
}

func (c *urlThumbCache) fail(key string) {
	c.mu.Lock()
	c.busy[key], c.failed[key] = false, true
	c.mu.Unlock()
}

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

func decodeGUIImage(data []byte) (image.Image, string, error) {
	return utils.DecodeImageGuarded(bytes.NewReader(data), guiMaxImagePixels)
}

func (a *App) urlThumb(gtx layout.Context, url string, sizeDp unit.Dp) layout.Dimensions {
	size := gtx.Dp(sizeDp)
	if url == "" || size <= 0 {
		return layout.Dimensions{}
	}
	if img := urlThumbs.get(url); img != nil {
		return drawImageRRectCover(gtx, img, size)
	}
	a.ensureURLThumb(url)
	return layout.Dimensions{Size: image.Pt(size, size)}
}
