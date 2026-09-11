package engine

// httpimg.go — slice 130: the pure-Go HTTP image fetcher. A tiny, strict,
// cached GET for remote image bytes (inline-bot result thumbs today; any
// backend's URL-referenced media later). Account-independent — it makes no
// core calls, so every backend can use it.
//
// Policy (tdesktop-scale prudence, honest failure everywhere):
//   - http/https only (data:, file:, javascript: rejected outright);
//   - 10s total deadline, at most 5 redirects;
//   - hard byte cap enforced with a LimitReader (Content-Length known too
//     big is rejected before a byte is read);
//   - content sniff: image/* accepted; application/octet-stream accepted
//     only when the URL path ends in a known image extension (webp/avif
//     bytes often sniff as octet-stream — Go's sniffer knows neither);
//   - in-memory LRU (256 entries) keyed url|cap; failures are not cached;
//   - concurrent fetches of the same key collapse into one request.
//
// js/wasm: net/http rides the browser fetch transport there; cross-origin
// refusals surface as errors and the GUI falls back honestly (§1.10).

import (
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"path"
	"strings"
	"sync"
	"time"
)

const (
	httpImgTimeout  = 10 * time.Second
	httpImgMaxHops  = 5
	httpImgCacheCap = 256
	httpImgMinBytes = 1 << 10 // 1 KiB floor: thumbs below this are junk
	httpImgMaxBytes = 8 << 20 // 8 MiB ceiling
)

var (
	// httpImgClient is shared by every fetch (connection reuse) with the
	// universal redirect cap baked in.
	httpImgClient = &http.Client{
		Timeout: httpImgTimeout,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) > httpImgMaxHops {
				return fmt.Errorf("too many redirects (%d)", len(via))
			}
			return nil
		},
	}

	// httpImgCache memoizes fetched bytes.
	httpImgCache = newHTTPImageCache(httpImgCacheCap)

	// httpImgFlights dedups concurrent fetches per key.
	httpImgMu       sync.Mutex
	httpImgInflight = map[string]*httpImgFlight{}
)

// httpImgFlight is one in-flight (or completed-and-waiting) fetch.
type httpImgFlight struct {
	done chan struct{}
	data []byte
	err  error
}

// validImageURL reports whether the URL may be fetched: http/https with a
// host. Pure — unit-tested.
func validImageURL(raw string) bool {
	if raw == "" {
		return false
	}
	u, err := url.Parse(raw)
	if err != nil {
		return false
	}
	return (u.Scheme == "http" || u.Scheme == "https") && u.Host != ""
}

// imageExtURLs are extensions that legitimize an octet-stream response
// (formats Go's content sniffer cannot identify).
var imageExtURLs = map[string]bool{
	".webp": true,
	".avif": true,
	".jxl":  true,
	".heic": true,
	".heif": true,
}

// sniffImageAccepted reports whether fetched bytes smell like an image:
// sniffed image/* always passes; octet-stream passes only with an
// image-extension URL (decoder makes the final call downstream); anything
// else (html/json/zip) is rejected. Pure — unit-tested.
func sniffImageAccepted(data []byte, fromURL string) bool {
	ct := http.DetectContentType(data)
	if strings.HasPrefix(ct, "image/") {
		return true
	}
	if ct == "application/octet-stream" && imageExtURLs[strings.ToLower(path.Ext(rawURLPath(fromURL)))] {
		return true
	}
	return false
}

// rawURLPath extracts the path for extension checks (malformed → "").
func rawURLPath(raw string) string {
	if u, err := url.Parse(raw); err == nil {
		return u.Path
	}
	return ""
}

// clampMaxBytes bounds a caller's cap to the fetcher's sane range.
func clampMaxBytes(n int64) int64 {
	if n < httpImgMinBytes {
		return httpImgMinBytes
	}
	if n > httpImgMaxBytes {
		return httpImgMaxBytes
	}
	return n
}

// FetchHTTPImage GETs a remote image (≤ maxBytes) and returns its bytes.
// Cached per url+cap; concurrent duplicate calls share one request. The
// method touches no engine state — a zero Engine works.
func (e *Engine) FetchHTTPImage(rawURL string, maxBytes int64) ([]byte, error) {
	if !validImageURL(rawURL) {
		return nil, fmt.Errorf("not an http(s) image URL: %q", rawURL)
	}
	cap := clampMaxBytes(maxBytes)
	key := fmt.Sprintf("%s|%d", rawURL, cap)

	// Cache hit.
	if data := httpImgCache.get(key); data != nil {
		return data, nil
	}

	// Join or start a flight.
	httpImgMu.Lock()
	if fl, ok := httpImgInflight[key]; ok {
		httpImgMu.Unlock()
		<-fl.done
		if fl.err != nil {
			return nil, fl.err
		}
		return fl.data, nil
	}
	fl := &httpImgFlight{done: make(chan struct{})}
	httpImgInflight[key] = fl
	httpImgMu.Unlock()

	fl.data, fl.err = httpImgDo(rawURL, cap)
	close(fl.done)

	httpImgMu.Lock()
	delete(httpImgInflight, key)
	httpImgMu.Unlock()

	if fl.err != nil {
		return nil, fl.err
	}
	httpImgCache.store(key, fl.data)
	return fl.data, nil
}

// httpImgDo performs the guarded request.
func httpImgDo(rawURL string, cap int64) ([]byte, error) {
	resp, err := httpImgClient.Get(rawURL)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("http %d", resp.StatusCode)
	}
	if resp.ContentLength > cap {
		return nil, fmt.Errorf("image too large: %d bytes (cap %d)", resp.ContentLength, cap)
	}

	// cap+1 so an exactly-cap body passes and one byte more fails.
	body, err := io.ReadAll(io.LimitReader(resp.Body, cap+1))
	if err != nil {
		return nil, err
	}
	if int64(len(body)) > cap {
		return nil, fmt.Errorf("image exceeds %d bytes", cap)
	}
	if len(body) == 0 {
		return nil, errors.New("empty response")
	}
	if !sniffImageAccepted(body, rawURL) {
		return nil, fmt.Errorf("content is not an image (sniffed %s)", http.DetectContentType(body))
	}
	return body, nil
}

// ── LRU cache ──────────────────────────────────────────────────────────────

// httpImageCache is a simple thread-safe LRU of fetched image bytes.
type httpImageCache struct {
	mu   sync.Mutex
	cap  int
	keys []string // front = least recently used
	vals map[string][]byte
}

func newHTTPImageCache(cap int) *httpImageCache {
	if cap < 1 {
		cap = 1
	}
	return &httpImageCache{cap: cap, vals: make(map[string][]byte)}
}

// get returns the cached bytes (nil when absent) and marks the key used.
func (c *httpImageCache) get(key string) []byte {
	c.mu.Lock()
	defer c.mu.Unlock()
	data, ok := c.vals[key]
	if !ok {
		return nil
	}
	c.touchLocked(key)
	return data
}

// store inserts/overwrites an entry, evicting the LRU entry when full.
func (c *httpImageCache) store(key string, data []byte) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if _, ok := c.vals[key]; !ok {
		for len(c.keys) >= c.cap {
			delete(c.vals, c.keys[0])
			c.keys = c.keys[1:]
		}
		c.keys = append(c.keys, key)
	}
	c.vals[key] = data
	c.touchLocked(key)
}

// touchLocked moves key to the back (most recently used). Caller holds mu.
func (c *httpImageCache) touchLocked(key string) {
	for i, k := range c.keys {
		if k == key {
			if i != len(c.keys)-1 {
				rest := make([]string, 0, len(c.keys)-1)
				rest = append(rest, c.keys[:i]...)
				rest = append(rest, c.keys[i+1:]...)
				c.keys = append(rest, key)
			}
			return
		}
	}
}

// len reports the entry count (test hook).
func (c *httpImageCache) len() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return len(c.keys)
}
