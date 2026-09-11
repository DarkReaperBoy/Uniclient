package gui

// urlthumb_test.go — slice 130 tests-first: the remote-URL thumb cache
// (the mapTiles pattern applied to engine.FetchHTTPImage results) and the
// inline-result thumb selection logic (b64 first, URL second, none last).

import (
	"image"
	"testing"

	"uniclient/cores"
)

func TestURLThumbCacheSemantics(t *testing.T) {
	c := &urlThumbCache{imgs: map[string]*image.RGBA{}, busy: map[string]bool{}, failed: map[string]bool{}}
	if c.get("k") != nil {
		t.Error("empty cache returned an image")
	}
	if !c.claim("k") {
		t.Fatal("first claim failed")
	}
	if c.claim("k") {
		t.Error("double claim allowed while busy")
	}
	img := image.NewRGBA(image.Rect(0, 0, 4, 2))
	c.store("k", img)
	if c.get("k") != img {
		t.Error("stored image not returned")
	}
	if c.busy["k"] {
		t.Error("busy flag survived store")
	}
	if c.claim("k") {
		t.Error("claim allowed with a cached image")
	}
	c.fail("j")
	if c.claim("j") {
		t.Error("claim allowed for a failed key")
	}
	if c.busy["j"] {
		t.Error("busy flag survived fail")
	}
}

func TestInlineThumbSource(t *testing.T) {
	// b64 thumb wins (already-delivered inline bytes, no network).
	r := cores.InlineBotResult{ThumbB64: "QUJD", ThumbURL: "https://x.com/a.png"}
	if src, url := inlineThumbSource(r); src != thumbSrcB64 || url != "" {
		t.Errorf("b64 result: src=%v url=%q", src, url)
	}
	// URL-only result falls to the fetcher.
	r = cores.InlineBotResult{ThumbURL: "https://x.com/a.png"}
	if src, url := inlineThumbSource(r); src != thumbSrcURL || url != "https://x.com/a.png" {
		t.Errorf("url result: src=%v url=%q", src, url)
	}
	// Neither: no thumb at all (honest text row).
	r = cores.InlineBotResult{}
	if src, url := inlineThumbSource(r); src != thumbSrcNone || url != "" {
		t.Errorf("bare result: src=%v url=%q", src, url)
	}
	// Degenerate: empty URL string is not a fetch candidate.
	r = cores.InlineBotResult{ThumbURL: ""}
	if src, _ := inlineThumbSource(r); src != thumbSrcNone {
		t.Errorf("empty URL treated as fetchable: %v", src)
	}
}
