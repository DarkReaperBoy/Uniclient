package engine

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
	httpImgMinBytes = 1 << 10
	httpImgMaxBytes = 8 << 20
)

var (
	httpImgClient = &http.Client{
		Timeout: httpImgTimeout,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) > httpImgMaxHops {
				return fmt.Errorf("too many redirects (%d)", len(via))
			}
			return nil
		},
	}

	httpImgCache = newHTTPImageCache(httpImgCacheCap)

	httpImgMu       sync.Mutex
	httpImgInflight = map[string]*httpImgFlight{}
)

type httpImgFlight struct {
	done chan struct{}
	data []byte
	err  error
}

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

var imageExtURLs = map[string]bool{
	".webp": true,
	".avif": true,
	".jxl":  true,
	".heic": true,
	".heif": true,
}

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

func rawURLPath(raw string) string {
	if u, err := url.Parse(raw); err == nil {
		return u.Path
	}
	return ""
}

func clampMaxBytes(n int64) int64 {
	if n < httpImgMinBytes {
		return httpImgMinBytes
	}
	if n > httpImgMaxBytes {
		return httpImgMaxBytes
	}
	return n
}

func (e *Engine) FetchHTTPImage(rawURL string, maxBytes int64) ([]byte, error) {
	if !validImageURL(rawURL) {
		return nil, fmt.Errorf("not an http(s) image URL: %q", rawURL)
	}
	cap := clampMaxBytes(maxBytes)
	key := fmt.Sprintf("%s|%d", rawURL, cap)

	if data := httpImgCache.get(key); data != nil {
		return data, nil
	}

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

type httpImageCache struct {
	mu   sync.Mutex
	cap  int
	keys []string
	vals map[string][]byte
}

func newHTTPImageCache(cap int) *httpImageCache {
	if cap < 1 {
		cap = 1
	}
	return &httpImageCache{cap: cap, vals: make(map[string][]byte)}
}

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

func (c *httpImageCache) len() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return len(c.keys)
}
