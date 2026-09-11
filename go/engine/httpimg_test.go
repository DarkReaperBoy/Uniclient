package engine

// httpimg_test.go — slice 130 tests-first: the pure-Go HTTP image fetcher.
// Behavior under test (before the implementation exists):
//   - URL policy: only http/https URLs fetch; everything else errors.
//   - size cap: oversize bodies error; Content-Length known-too-big errors early.
//   - content policy: non-image content types error; image/* accepted;
//     application/octet-stream accepted only for image-ish URL extensions.
//   - redirect policy: up to 5 redirects followed; 6+ errors.
//   - LRU cache: second fetch of the same URL hits the cache (server sees
//     exactly one hit); capacity evicts the least-recently-used entry.
//   - in-flight dedup: two concurrent fetches of the same URL produce one
//     server hit and both receive the same bytes.
// The fetcher is an Engine method but touches no Engine state (no DB, no
// accounts) so a zero Engine exercises it fully.

import (
	"bytes"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// tinyPNG builds a real 1x1 PNG (valid image bytes).
func tinyPNG(t *testing.T) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 1, 1))
	img.Set(0, 0, color.RGBA{R: 0x80, G: 0x40, B: 0x20, A: 0xff})
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatalf("png encode: %v", err)
	}
	return buf.Bytes()
}

func TestValidImageURL(t *testing.T) {
	cases := []struct {
		in   string
		want bool
	}{
		{"http://example.com/a.jpg", true},
		{"https://example.com/a.jpg", true},
		{"HTTPS://EXAMPLE.COM/a.png", true}, // scheme case-insensitive per RFC 3986
		{"https://example.com", true},       // no path is still a URL
		{"", false},
		{"example.com/a.jpg", false},       // no scheme
		{"ftp://example.com/a.jpg", false}, // wrong scheme
		{"data:image/png;base64,AAAA", false},
		{"file:///etc/passwd", false},
		{"javascript:alert(1)", false},
		{"https://", false}, // empty host
	}
	for _, c := range cases {
		if got := validImageURL(c.in); got != c.want {
			t.Errorf("validImageURL(%q) = %v, want %v", c.in, got, c.want)
		}
	}
}

func TestSniffImageAccepted(t *testing.T) {
	png := tinyPNG(t)
	// A real PNG sniffs as image/png.
	if !sniffImageAccepted(png, "") {
		t.Error("real PNG rejected by sniffer")
	}
	// HTML error page sniffs as text/html → rejected.
	if sniffImageAccepted([]byte("<html><body>err</body></html>"), "") {
		t.Error("html accepted by sniffer")
	}
	// WebP header bytes sniff as image/webp in modern Go — accepted
	// regardless of URL.
	if !sniffImageAccepted([]byte("RIFF____WEBPVP8 "), "") {
		t.Error("webp-magic bytes rejected (sniffs as image/webp)")
	}
	// AVIF bytes are NOT in Go's sniff table (octet-stream) → the URL
	// extension gate rescues them.
	avif := []byte{0x00, 0x00, 0x00, 0x20, 'f', 't', 'y', 'p', 'a', 'v', 'i', 'f'}
	if !sniffImageAccepted(avif, "https://x.com/t.avif") {
		t.Error("avif bytes with .avif URL rejected at sniff stage")
	}
	if sniffImageAccepted(avif, "") {
		t.Error("avif bytes with no URL accepted as octet-stream")
	}
	if sniffImageAccepted(avif, "https://x.com/page.html") {
		t.Error("avif bytes with .html URL accepted as octet-stream")
	}
	// Plain random bytes: octet-stream with no image extension → rejected.
	if sniffImageAccepted([]byte{0x00, 0x01, 0x02}, "https://x.com/binary") {
		t.Error("random octet-stream bytes accepted")
	}
}

func TestClampMaxBytes(t *testing.T) {
	cases := []struct {
		in, want int64
	}{
		{0, httpImgMinBytes},
		{-5, httpImgMinBytes},
		{2048, 2048},
		{1 << 30, httpImgMaxBytes},
	}
	for _, c := range cases {
		if got := clampMaxBytes(c.in); got != c.want {
			t.Errorf("clampMaxBytes(%d) = %d, want %d", c.in, got, c.want)
		}
	}
}

func TestHTTPImageCacheLRU(t *testing.T) {
	c := newHTTPImageCache(3)
	c.store("a", []byte{1})
	c.store("b", []byte{2})
	c.store("c", []byte{3})
	if got := c.get("a"); got == nil || got[0] != 1 {
		t.Fatalf("get(a) after 3 stores = %v", got)
	}
	// "a" is now most-recently used; inserting "d" must evict "b" (LRU).
	c.store("d", []byte{4})
	if c.get("b") != nil {
		t.Error("b survived eviction (LRU order wrong)")
	}
	if c.get("a") == nil || c.get("c") == nil || c.get("d") == nil {
		t.Error("wrong entry evicted")
	}
	// Overwrite in place does not grow the cache.
	c.store("a", []byte{9})
	if got := c.get("a"); got == nil || got[0] != 9 {
		t.Fatalf("overwrite get = %v", got)
	}
	if c.len() != 3 {
		t.Errorf("len after overwrite = %d, want 3", c.len())
	}
}

func TestFetchHTTPImageServer(t *testing.T) {
	pngBytes := tinyPNG(t)
	var hits struct {
		ok       atomic.Int64
		big      atomic.Int64
		text     atomic.Int64
		notfound atomic.Int64
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/ok.png", func(w http.ResponseWriter, r *http.Request) {
		hits.ok.Add(1)
		w.Header().Set("Content-Type", "image/png")
		w.Write(pngBytes)
	})
	mux.HandleFunc("/big.png", func(w http.ResponseWriter, r *http.Request) {
		hits.big.Add(1)
		w.Header().Set("Content-Type", "image/png")
		w.Write(make([]byte, 1<<20)) // 1 MiB > 4 KiB cap below
	})
	mux.HandleFunc("/text", func(w http.ResponseWriter, r *http.Request) {
		hits.text.Add(1)
		w.Header().Set("Content-Type", "text/html")
		w.Write([]byte("<html>not an image</html>"))
	})
	mux.HandleFunc("/404", func(w http.ResponseWriter, r *http.Request) {
		hits.notfound.Add(1)
		http.Error(w, "gone", http.StatusNotFound)
	})
	// Redirect chain: /r0 → /r1 → /r2 → /r3 → /r4 → /ok.png (5 hops,
	// allowed).
	for i := 0; i < 5; i++ {
		target := fmt.Sprintf("/r%d", i+1)
		if i == 4 {
			target = "/ok.png"
		}
		mux.HandleFunc(fmt.Sprintf("/r%d", i), func(w http.ResponseWriter, r *http.Request) {
			http.Redirect(w, r, target, http.StatusFound)
		})
	}
	// /loop0 → ... → /loop5 → /loop0: 6+ hops → rejected.
	for i := 0; i <= 5; i++ {
		next := (i + 1) % 6
		mux.HandleFunc(fmt.Sprintf("/loop%d", i), func(w http.ResponseWriter, r *http.Request) {
			http.Redirect(w, r, fmt.Sprintf("/loop%d", next), http.StatusFound)
		})
	}
	srv := httptest.NewServer(mux)
	defer srv.Close()

	e := &Engine{}

	// Valid image.
	got, err := e.FetchHTTPImage(srv.URL+"/ok.png", 4096)
	if err != nil || len(got) != len(pngBytes) {
		t.Fatalf("valid fetch: err=%v len=%d want=%d", err, len(got), len(pngBytes))
	}
	// Cache hit: second fetch must not touch the server.
	if _, err := e.FetchHTTPImage(srv.URL+"/ok.png", 4096); err != nil {
		t.Fatalf("cached fetch: %v", err)
	}
	if n := hits.ok.Load(); n != 1 {
		t.Errorf("server hits for ok.png = %d, want 1 (cache miss only)", n)
	}
	// Different cap → different cache key → refetch.
	e.FetchHTTPImage(srv.URL+"/ok.png", 8192)
	if n := hits.ok.Load(); n != 2 {
		t.Errorf("server hits after different-cap fetch = %d, want 2", n)
	}

	// Oversize.
	if _, err := e.FetchHTTPImage(srv.URL+"/big.png", 4096); err == nil {
		t.Error("oversize image accepted")
	}
	// Non-image content.
	if _, err := e.FetchHTTPImage(srv.URL+"/text", 4096); err == nil {
		t.Error("text/html accepted as image")
	}
	// 404.
	if _, err := e.FetchHTTPImage(srv.URL+"/404", 4096); err == nil {
		t.Error("404 accepted")
	}
	// Bad scheme.
	if _, err := e.FetchHTTPImage("javascript:alert(1)", 4096); err == nil {
		t.Error("javascript: URL accepted")
	}
	// Redirect chain of 5 → lands on ok.png.
	if _, err := e.FetchHTTPImage(srv.URL+"/r0", 4096); err != nil {
		t.Errorf("5-hop redirect chain failed: %v", err)
	}
	// Infinite redirect loop → rejected (redirect cap), not hang.
	done := make(chan error, 1)
	go func() { _, err := e.FetchHTTPImage(srv.URL+"/loop0", 4096); done <- err }()
	select {
	case err := <-done:
		if err == nil {
			t.Error("redirect loop accepted")
		}
	case <-time.After(15 * time.Second):
		t.Fatal("redirect loop hung (no redirect cap)")
	}
}

func TestFetchHTTPImageDedup(t *testing.T) {
	pngBytes := tinyPNG(t)
	var served atomic.Int64
	mux := http.NewServeMux()
	mux.HandleFunc("/slow.png", func(w http.ResponseWriter, r *http.Request) {
		served.Add(1)
		// Slow enough that all concurrent callers pile into the
		// in-flight window (goroutine scheduling is sub-millisecond,
		// so 500ms is generous even on loaded CI runners).
		time.Sleep(500 * time.Millisecond)
		w.Header().Set("Content-Type", "image/png")
		w.Write(pngBytes)
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()

	e := &Engine{}
	const n = 4
	var wg sync.WaitGroup
	results := make([][]byte, n)
	errs := make([]error, n)
	start := make(chan struct{})
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			results[i], errs[i] = e.FetchHTTPImage(srv.URL+"/slow.png", 4096)
		}(i)
	}
	close(start)
	wg.Wait()

	if served.Load() != 1 {
		t.Errorf("server served %d requests, want 1 (in-flight dedup)", served.Load())
	}
	for i := 0; i < n; i++ {
		if errs[i] != nil {
			t.Fatalf("caller %d failed: %v", i, errs[i])
		}
		if len(results[i]) != len(pngBytes) {
			t.Fatalf("caller %d got %d bytes, want %d", i, len(results[i]), len(pngBytes))
		}
	}
}
