package gui

// Animated .tgs sticker playback (slice 123, on top of the lottie engine
// from slice 122 A/B/C). Tests lock the pure helpers BEFORE the widgets:
// container/mime detection, playback math (frame loop + invalidation
// interval), the per-msg player cache, and the bare-bubble gating.

import (
	"bytes"
	"compress/gzip"
	"os"
	"path/filepath"
	"testing"
	"time"

	"uniclient/engine"
	"uniclient/lottie"
)

// gzipTgs compresses a Bodymovin JSON document like a real .tgs file.
func gzipTgs(t *testing.T, doc string) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	if _, err := zw.Write([]byte(doc)); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

const sampleTgsJSON = `{"v":"5.5.7","fr":30,"ip":0,"op":90,"w":512,"h":512,"nm":"wave","layers":[{"ty":4,"nm":"dot","ip":0,"op":90,"ks":{}}]}`

func TestIsTgsMime(t *testing.T) {
	cases := []struct {
		mime string
		want bool
	}{
		{"application/x-tgsticker", true},
		{"APPLICATION/X-TGSTICKER", false}, // exact match only
		{"image/webp", false},
		{"video/webm+sticker", false},
		{"", false},
	}
	for _, c := range cases {
		if got := isTgsMime(c.mime); got != c.want {
			t.Errorf("isTgsMime(%q) = %v, want %v", c.mime, got, c.want)
		}
	}
}

func TestGzipMagic(t *testing.T) {
	dir := t.TempDir()
	gz := filepath.Join(dir, "anim.tgs")
	if err := os.WriteFile(gz, gzipTgs(t, sampleTgsJSON), 0o600); err != nil {
		t.Fatal(err)
	}
	png := filepath.Join(dir, "sticker.webp")
	if err := os.WriteFile(png, []byte{0x89, 'P', 'N', 'G', 0x0D, 0x0A}, 0o600); err != nil {
		t.Fatal(err)
	}
	one := filepath.Join(dir, "tiny")
	if err := os.WriteFile(one, []byte{0x1F}, 0o600); err != nil {
		t.Fatal(err)
	}
	if !gzipMagic(gz) {
		t.Error("gzipMagic(.tgs) = false, want true")
	}
	if gzipMagic(png) {
		t.Error("gzipMagic(webp/png) = true, want false")
	}
	if gzipMagic(one) {
		t.Error("gzipMagic(1-byte file) = true, want false")
	}
	if gzipMagic(filepath.Join(dir, "missing")) {
		t.Error("gzipMagic(missing) = true, want false")
	}
}

func TestStickerRenderKind(t *testing.T) {
	dir := t.TempDir()
	gzPath := filepath.Join(dir, "sniffed")
	if err := os.WriteFile(gzPath, gzipTgs(t, sampleTgsJSON), 0o600); err != nil {
		t.Fatal(err)
	}
	cases := []struct {
		name string
		m    engine.CachedMessage
		want int
	}{
		{"tgs mime", engine.CachedMessage{MediaMimeType: "application/x-tgsticker"}, stickerKindTgs},
		{"webm mime", engine.CachedMessage{MediaMimeType: "video/webm+sticker"}, stickerKindWebm},
		{"webp mime", engine.CachedMessage{MediaMimeType: "image/webp"}, stickerKindStatic},
		{"sniff gzip path", engine.CachedMessage{MediaLocalPath: gzPath}, stickerKindTgs},
		{"sniff non-gzip path", engine.CachedMessage{MediaLocalPath: filepath.Join(dir, "nope")}, stickerKindStatic},
		{"no mime no path", engine.CachedMessage{}, stickerKindStatic},
	}
	for _, c := range cases {
		if got := stickerRenderKind(&c.m); got != c.want {
			t.Errorf("%s: stickerRenderKind = %d, want %d", c.name, got, c.want)
		}
	}
}

func TestParseTgsBytes(t *testing.T) {
	if anim, ok := parseTgsBytes(gzipTgs(t, sampleTgsJSON)); !ok || anim == nil {
		t.Fatal("parseTgsBytes(valid tgs) rejected the document")
	}
	if _, ok := parseTgsBytes(gzipTgs(t, `not json at all`)); ok {
		t.Error("parseTgsBytes(gzip of garbage) = ok, want rejected")
	}
	if _, ok := parseTgsBytes([]byte{0x89, 'P', 'N', 'G'}); ok {
		t.Error("parseTgsBytes(png) = ok, want rejected")
	}
	// Degenerate documents (no frames to animate) must not count as playable.
	if _, ok := parseTgsBytes(gzipTgs(t, `{"v":"5.5.7","fr":30,"ip":0,"op":0,"w":512,"h":512,"layers":[]}`)); ok {
		t.Error("parseTgsBytes(zero-length op) = ok, want rejected")
	}
	if _, ok := parseTgsBytes(gzipTgs(t, `{"v":"5.5.7","fr":30,"ip":0,"op":90,"w":512,"h":512,"layers":[],"assets":[]}`)); ok {
		t.Error("parseTgsBytes(no layers) = ok, want rejected")
	}
}

func TestTgsFrameInterval(t *testing.T) {
	cases := []struct {
		fps  float64
		want time.Duration
	}{
		{60, time.Second / 60},
		{30, time.Second / 30},
		{25, time.Second / 25},
		{120, time.Second / 60}, // capped at 60fps
		{10, time.Second / 20},  // floored at 20fps
		{0, time.Second / 20},
		{-5, time.Second / 20},
	}
	for _, c := range cases {
		if got := tgsFrameInterval(c.fps); got != c.want {
			t.Errorf("tgsFrameInterval(%v) = %v, want %v", c.fps, got, c.want)
		}
	}
}

func TestTgsLoopFrame(t *testing.T) {
	anim := &lottie.Animation{FrameRate: 30, InPoint: 0, OutPoint: 90} // 3s
	cases := []struct {
		elapsed time.Duration
		want    float64
	}{
		{0, 0},
		{time.Second, 30},
		{time.Second * 29 / 10, 87},
		{3 * time.Second, 0}, // exact loop point wraps
		{7*time.Second + 500*time.Millisecond, 45}, // 7.5s → 1.5s → frame 45
	}
	for _, c := range cases {
		if got := tgsLoopFrame(anim, c.elapsed); got != c.want {
			t.Errorf("tgsLoopFrame(%v) = %v, want %v", c.elapsed, got, c.want)
		}
	}
	// Degenerate animation (no duration): pinned at the in-point.
	if got := tgsLoopFrame(&lottie.Animation{FrameRate: 30, InPoint: 2, OutPoint: 2}, time.Second); got != 2 {
		t.Errorf("tgsLoopFrame(degenerate) = %v, want 2", got)
	}
	if got := tgsLoopFrame(nil, time.Second); got != 0 {
		t.Errorf("tgsLoopFrame(nil) = %v, want 0", got)
	}
}

func TestTgsPlayerCache(t *testing.T) {
	c := &tgsPlayerCache{players: make(map[string]*tgsPlayer)}

	p1 := c.get("m1")
	if p1 == nil {
		t.Fatal("get returned nil")
	}
	if c.get("m1") != p1 {
		t.Error("get returned a fresh player for the same msgID")
	}
	if p1.parsed || p1.failed || p1.reading {
		t.Error("fresh player flags not zero")
	}

	// setAnim publishes the animation and marks parsed.
	anim := &lottie.Animation{FrameRate: 30, InPoint: 0, OutPoint: 90}
	c.setAnim("m1", anim)
	if p := c.get("m1"); !p.parsed || p.anim != anim {
		t.Error("setAnim did not publish parsed state")
	}

	// replay resets the clock.
	c.replay("m1")
	if st := c.get("m1").start; st.IsZero() {
		t.Error("replay left a zero start time")
	}

	// failParse pins the failed flag (static fallback, no re-parse).
	c.failParse("m2")
	if p := c.get("m2"); !p.failed || p.parsed {
		t.Error("failParse did not pin the failed state")
	}

	// markReading guards concurrent reads: claim once, release once.
	if !c.markReading("m3") {
		t.Error("first markReading claim rejected")
	}
	if c.markReading("m3") {
		t.Error("second markReading claim accepted while in flight")
	}
	c.endReading("m3")
	if !c.markReading("m3") {
		t.Error("markReading after endReading rejected")
	}

	// Prune: an oversized cache resets without panic.
	for i := 0; i < 200; i++ {
		c.get("bulk" + itoa(i))
	}
	if got := c.get("after-prune"); got == nil {
		t.Error("get after prune returned nil")
	}
}

func TestIsBareStickerMsg(t *testing.T) {
	cases := []struct {
		name string
		m    engine.CachedMessage
		want bool
	}{
		{"pure sticker", engine.CachedMessage{HasMedia: true, MediaType: engine.MediaSticker}, true},
		{"sticker with caption", engine.CachedMessage{HasMedia: true, MediaType: engine.MediaSticker, ContentText: "hi"}, false},
		{"sticker service msg", engine.CachedMessage{HasMedia: true, MediaType: engine.MediaSticker, IsService: true}, false},
		{"photo", engine.CachedMessage{HasMedia: true, MediaType: engine.MediaImage}, false},
		{"poll body", engine.CachedMessage{MediaType: engine.MediaSticker, ContentRaw: []byte(`{"extra":{"poll_question":"pick one","poll_options":[{"text":"a","voters":0},{"text":"b","voters":0}]}}`)}, false},
	}
	for _, c := range cases {
		if got := isBareStickerMsg(&c.m); got != c.want {
			t.Errorf("%s: isBareStickerMsg = %v, want %v", c.name, got, c.want)
		}
	}
	if isBareStickerMsg(nil) {
		t.Error("isBareStickerMsg(nil) = true")
	}
}

func TestAutoDownloadable(t *testing.T) {
	for _, mt := range []int{engine.MediaImage, engine.MediaGIF, engine.MediaSticker} {
		if !autoDownloadable(mt) {
			t.Errorf("autoDownloadable(%d) = false, want true", mt)
		}
	}
	for _, mt := range []int{engine.MediaVideo, engine.MediaFile, engine.MediaAudio, engine.MediaVoice, engine.MediaVideoNote} {
		if autoDownloadable(mt) {
			t.Errorf("autoDownloadable(%d) = true, want false", mt)
		}
	}
}

func TestMessageMetaLabel(t *testing.T) {
	m := engine.CachedMessage{Timestamp: 1720000000000}
	base := messageMetaLabel(m, "")
	if base == "" {
		t.Error("messageMetaLabel empty for plain message")
	}
	m.EditedAt = 1720000100000
	if got := messageMetaLabel(m, ""); got == base {
		t.Error("edited message meta identical to plain (edited mark missing)")
	}
	if got := messageMetaLabel(m, "✎"); got == base {
		t.Error("custom edited mark not applied")
	}
}

func TestStickerBubbleSize(t *testing.T) {
	// Square sticker: full size, no letterbox waste.
	if w, h := stickerBox(256, 512, 512); w != 256 || h != 256 {
		t.Errorf("stickerBox(256,512,512) = %d,%d want 256,256", w, h)
	}
	// Wide sticker: height shrinks with aspect.
	if w, h := stickerBox(256, 512, 256); w != 256 || h != 128 {
		t.Errorf("stickerBox(256,512,256) = %d,%d want 256,128", w, h)
	}
	// Degenerate dims: square fallback.
	if w, h := stickerBox(256, 0, 0); w != 256 || h != 256 {
		t.Errorf("stickerBox(256,0,0) = %d,%d want 256,256", w, h)
	}
}
