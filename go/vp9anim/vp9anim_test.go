package vp9anim

// vp9anim_test.go — tests-first pins for the animation pipeline. The
// hand-built WebM fixtures live in the webm package tests; here we pin:
//   - the timeline math (frame lookup, durations, loop wrap);
//   - YUV→RGBA colorimetry (BT.601 studio vs full range, per the VP9
//     header signaling, with alpha pairing);
//   - the decode-through + profile rejection against REAL official VP9
//     test vectors committed under testdata/ (webmproject.org).

import (
	"image"
	"image/color"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/thesyncim/govpx"

	"uniclient/vcodec"
	"uniclient/webm"
)

// ── timeline math ─────────────────────────────────────────────────────────

func TestTimelineFromTimecodes(t *testing.T) {
	// 3 frames at 0/33/66ms; container duration 100ms → last frame spans
	// 34ms. Default duration 40ms when the container duration is absent.
	an := &Animation{
		Width:  64,
		Height: 64,
	}
	an.frames = []frameSlot{
		{start: 0},
		{start: 33 * time.Millisecond},
		{start: 66 * time.Millisecond},
	}
	an.buildTimeline(100*time.Millisecond, 0)
	if an.Total != 100*time.Millisecond {
		t.Fatalf("total = %v, want 100ms", an.Total)
	}
	if an.frames[0].dur != 33*time.Millisecond || an.frames[2].dur != 34*time.Millisecond {
		t.Fatalf("durations = [%v %v %v], want [33ms 33ms 34ms]",
			an.frames[0].dur, an.frames[1].dur, an.frames[2].dur)
	}
}

func TestTimelineFallbacks(t *testing.T) {
	// No container duration: DefaultDuration wins for the last frame.
	an := &Animation{Width: 64, Height: 64}
	an.frames = []frameSlot{{start: 0}, {start: 40 * time.Millisecond}}
	an.buildTimeline(0, 41_708_333)
	if an.frames[1].dur != 41_708_333 {
		t.Fatalf("last dur = %v, want DefaultDuration", an.frames[1].dur)
	}
	// Neither: 40ms fallback.
	an2 := &Animation{Width: 64, Height: 64}
	an2.frames = []frameSlot{{start: 0}}
	an2.buildTimeline(0, 0)
	if an2.frames[0].dur != 40*time.Millisecond {
		t.Fatalf("fallback dur = %v, want 40ms", an2.frames[0].dur)
	}
	if an2.Total != 40*time.Millisecond {
		t.Fatalf("fallback total = %v, want 40ms", an2.Total)
	}
}

func TestFrameIndexAtLoops(t *testing.T) {
	an := &Animation{Width: 64, Height: 64, Total: 100 * time.Millisecond}
	an.frames = []frameSlot{
		{start: 0, dur: 33 * time.Millisecond},
		{start: 33 * time.Millisecond, dur: 33 * time.Millisecond},
		{start: 66 * time.Millisecond, dur: 34 * time.Millisecond},
	}
	cases := []struct {
		elapsed time.Duration
		want    int
	}{
		{0, 0},
		{32 * time.Millisecond, 0},
		{33 * time.Millisecond, 1},
		{65 * time.Millisecond, 1},
		{66 * time.Millisecond, 2},
		{99 * time.Millisecond, 2},
		{100 * time.Millisecond, 0}, // loop wrap
		{133 * time.Millisecond, 1}, // 33ms into the second loop
		{250 * time.Millisecond, 1}, // 50ms into the third loop → frame 1
	}
	for _, c := range cases {
		if got := an.frameIndexAt(c.elapsed); got != c.want {
			t.Fatalf("frameIndexAt(%v) = %d, want %d", c.elapsed, got, c.want)
		}
	}
}

func TestFrameIndexAtDegenerate(t *testing.T) {
	an := &Animation{Width: 64, Height: 64}
	if got := an.frameIndexAt(time.Second); got != 0 {
		t.Fatalf("empty animation frameIndexAt = %d, want 0", got)
	}
	an.Total = 10 * time.Millisecond
	an.frames = []frameSlot{{start: 0, dur: 0}} // zero duration slot
	if got := an.frameIndexAt(5 * time.Millisecond); got != 0 {
		t.Fatalf("zero-dur slot frameIndexAt = %d, want 0", got)
	}
}

// ── colorimetry ───────────────────────────────────────────────────────────

// yuvImage builds an I420 planar image with the given luma/chroma fills.
func yuvImage(w, h int, y, u, v byte) (govpx.Image, *image.RGBA) {
	src := govpx.Image{
		Width: w, Height: h,
		YStride: w, UStride: w / 2, VStride: w / 2,
		Y: make([]byte, w*h),
		U: make([]byte, (w/2)*(h/2)),
		V: make([]byte, (w/2)*(h/2)),
	}
	for i := range src.Y {
		src.Y[i] = y
	}
	for i := range src.U {
		src.U[i] = u
	}
	for i := range src.V {
		src.V[i] = v
	}
	alpha := make([]byte, w*h) // 255 = opaque
	for i := range alpha {
		alpha[i] = 255
	}
	dst := image.NewRGBA(image.Rect(0, 0, w, h))
	return src, dst
}

func TestYUVToRGBABT601Studio(t *testing.T) {
	// BT.601 studio range: black = Y16/U128/V128 → (0,0,0).
	src, dst := yuvImage(4, 4, 16, 128, 128)
	yuvToRGBA(&src, nil, dst, false)
	if got := dst.At(1, 1); got != (color.RGBA{0, 0, 0, 255}) {
		t.Fatalf("black = %v, want (0,0,0,255)", got)
	}
	// White = Y235 → (255,255,255).
	src2, dst2 := yuvImage(4, 4, 235, 128, 128)
	yuvToRGBA(&src2, nil, dst2, false)
	if got := dst2.At(1, 1); got != (color.RGBA{255, 255, 255, 255}) {
		t.Fatalf("white = %v, want (255,255,255,255)", got)
	}
}

func TestYUVToRGBAFullRange(t *testing.T) {
	// Full range: Y0 = black, Y255 = white.
	src, dst := yuvImage(4, 4, 0, 128, 128)
	yuvToRGBA(&src, nil, dst, true)
	if got := dst.At(1, 1); got != (color.RGBA{0, 0, 0, 255}) {
		t.Fatalf("black = %v, want (0,0,0,255)", got)
	}
	src2, dst2 := yuvImage(4, 4, 255, 128, 128)
	yuvToRGBA(&src2, nil, dst2, true)
	if got := dst2.At(1, 1); got != (color.RGBA{255, 255, 255, 255}) {
		t.Fatalf("white = %v, want (255,255,255,255)", got)
	}
}

func TestYUVToRGBAChroma(t *testing.T) {
	// Full-range red: Y81 U90 V240 converts to ≈ (238, 14, 14) under the
	// JFIF matrix (the canonical red test vector values).
	src, dst := yuvImage(4, 4, 81, 90, 240)
	yuvToRGBA(&src, nil, dst, true)
	r, g, b, a := dst.At(2, 2).RGBA()
	if r < 230<<8 || g > 25<<8 || b > 25<<8 || a != 0xffff {
		t.Fatalf("red = (%d,%d,%d,%d), want ~(238,14,14,255)", r>>8, g>>8, b>>8, a>>8)
	}
}

func TestYUVToRGBAAlpha(t *testing.T) {
	// Alpha plane: 0 = fully transparent, 255 = opaque (WebM alpha spec).
	src, dst := yuvImage(4, 4, 128, 128, 128)
	alpha := govpx.Image{
		Width: 4, Height: 4, YStride: 4, UStride: 2, VStride: 2,
		Y: []byte{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
		U: make([]byte, 4), V: make([]byte, 4),
	}
	yuvToRGBA(&src, &alpha, dst, true)
	if _, _, _, a := dst.At(0, 0).RGBA(); a != 0 {
		t.Fatalf("alpha0: a = %d, want 0", a)
	}
	for i := range alpha.Y {
		alpha.Y[i] = 255
	}
	yuvToRGBA(&src, &alpha, dst, true)
	if _, _, _, a := dst.At(0, 0).RGBA(); a != 0xffff {
		t.Fatalf("alpha255: a = %d, want 65535 (16-bit RGBA())", a)
	}
}

func TestYUVToRGBAStrides(t *testing.T) {
	// Padded strides (larger than visible width) must be honored.
	w, h := 4, 4
	src := govpx.Image{
		Width: w, Height: h,
		YStride: w + 8, UStride: w/2 + 4, VStride: w/2 + 4,
		Y: make([]byte, (w+8)*h),
		U: make([]byte, (w/2+4)*(h/2)),
		V: make([]byte, (w/2+4)*(h/2)),
	}
	for r := 0; r < h; r++ {
		for c := 0; c < w; c++ {
			src.Y[r*(w+8)+c] = 235
		}
	}
	for r := 0; r < h/2; r++ {
		for c := 0; c < w/2; c++ {
			src.U[r*(w/2+4)+c] = 128
			src.V[r*(w/2+4)+c] = 128
		}
	}
	dst := image.NewRGBA(image.Rect(0, 0, w, h))
	yuvToRGBA(&src, nil, dst, false)
	for r := 0; r < h; r++ {
		for c := 0; c < w; c++ {
			if got := dst.At(c, r); got != (color.RGBA{255, 255, 255, 255}) {
				t.Fatalf("pixel (%d,%d) = %v, want white (stride handling)", c, r, got)
			}
		}
	}
}

// ── real vectors (official webmproject test data) ─────────────────────────

func TestParseRealVector(t *testing.T) {
	data, err := os.ReadFile("testdata/vp90-2-03-size-196x196.webm")
	if err != nil {
		t.Skipf("testdata missing: %v", err)
	}
	an, err := Parse(data)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if an.Width != 196 || an.Height != 196 {
		t.Fatalf("dims = %dx%d, want 196x196", an.Width, an.Height)
	}
	if len(an.frames) != 10 {
		t.Fatalf("frames = %d, want 10", len(an.frames))
	}
	if an.Total != 333*time.Millisecond {
		t.Fatalf("total = %v, want 333ms", an.Total)
	}
}

func TestDecodeThroughRealVector(t *testing.T) {
	// The acceptance rung (AGENTS.md §9): every frame of a real official
	// VP9 stream decodes without error through the public player path.
	data, err := os.ReadFile("testdata/vp90-2-03-size-196x196.webm")
	if err != nil {
		t.Skipf("testdata missing: %v", err)
	}
	an, err := Parse(data)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	p := an.NewPlayer()
	defer p.Stop()
	p.Start()
	deadline := time.Now().Add(30 * time.Second)
	for p.DecodedCount() < len(an.frames) {
		if time.Now().After(deadline) {
			t.Fatalf("decode stalled at %d/%d frames", p.DecodedCount(), len(an.frames))
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func TestParseRejectsHighBitDepth(t *testing.T) {
	// Profile 2 (10-bit) is out of the 8-bit scope: honest error, no
	// partial animation.
	data, err := os.ReadFile("testdata/vp92-2-20-10bit-yuv420.webm")
	if err != nil {
		t.Skipf("testdata missing: %v", err)
	}
	if _, err := Parse(data); err == nil {
		t.Fatal("Parse accepted a 10-bit profile-2 stream")
	}
}

func TestFirstFramePixelsPinned(t *testing.T) {
	// Pinned end-to-end: demux → decode → RGBA. The exact bytes of the
	// first frame of the committed official vector are checked via a
	// stable checksum so any decoder/container regression trips.
	data, err := os.ReadFile("testdata/vp90-2-03-size-196x196.webm")
	if err != nil {
		t.Skipf("testdata missing: %v", err)
	}
	an, err := Parse(data)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	dec := newDecodePair(an.Width, an.Height, an.fullRange, an.bt709)
	img, err := dec.decode(an.frames[0].payload, an.frames[0].alpha)
	if err != nil {
		t.Fatalf("decode first frame: %v", err)
	}
	if img.Bounds().Dx() != an.Width || img.Bounds().Dy() != an.Height {
		t.Fatalf("frame %v, want %dx%d", img.Bounds(), an.Width, an.Height)
	}
	if got := frameChecksum(img); got != firstFrameChecksum196 && firstFrameChecksum196 != 0 {
		t.Fatalf("first-frame checksum = %d, want %d (decoder/output change)", got, firstFrameChecksum196)
	}
}

// frameChecksum is a simple stable sum over the RGBA bytes (FNV-1a).
func frameChecksum(img *image.RGBA) uint64 {
	var h uint64 = 14695981039346656037
	for _, b := range img.Pix {
		h ^= uint64(b)
		h *= 1099511628211
	}
	return h
}

// The expected checksum is pinned from the committed vector once; if the
// testdata file or the decode path changes intentionally, re-pin it by
// running: UNICLIENT_PIN=1 go test ./vp9anim/ -run TestFirstFramePixelsPinned -v
var firstFrameChecksum196 = uint64(16149418980420066017)

func TestPrintChecksum(t *testing.T) {
	if os.Getenv("UNICLIENT_PIN") == "" {
		t.Skip("set UNICLIENT_PIN=1 to print checksums for re-pinning")
	}
	data, err := os.ReadFile("testdata/vp90-2-03-size-196x196.webm")
	if err != nil {
		t.Skipf("testdata missing: %v", err)
	}
	an, err := Parse(data)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	dec := newDecodePair(an.Width, an.Height, an.fullRange, an.bt709)
	for i := 0; i < len(an.frames); i++ {
		img, err := dec.decode(an.frames[i].payload, an.frames[i].alpha)
		if err != nil {
			t.Fatalf("frame %d: %v", i, err)
		}
		t.Logf("FRAME %d CHECKSUM %d", i, frameChecksum(img))
	}
}

// ── Parse input validation ────────────────────────────────────────────────

func TestParseRejectsGarbage(t *testing.T) {
	if _, err := Parse([]byte("not a webm")); err == nil {
		t.Fatal("Parse accepted garbage")
	}
	if _, err := Parse(nil); err == nil {
		t.Fatal("Parse accepted nil")
	}
}

func TestParseAlphaDocument(t *testing.T) {
	// A real VP9 stream where every frame also carries an alpha payload:
	// parseDoc must expose it and the decode pair must decode both planes.
	data, err := os.ReadFile("testdata/vp90-2-03-size-196x196.webm")
	if err != nil {
		t.Skipf("testdata missing: %v", err)
	}
	doc, err := webm.Parse(data)
	if err != nil {
		t.Fatalf("webm.Parse: %v", err)
	}
	// Duplicate each frame payload as its own alpha side stream (a legal
	// alpha layout per the WebM spec: same dims, same VP9 profile).
	for i := range doc.Frames {
		doc.Frames[i].Alpha = doc.Frames[i].Payload
	}
	an, err := parseDoc(doc)
	if err != nil {
		t.Fatalf("parseDoc(with alpha): %v", err)
	}
	if len(an.frames) != 10 {
		t.Fatalf("frames = %d, want 10", len(an.frames))
	}
	for i, f := range an.frames {
		if len(f.alpha) == 0 {
			t.Fatalf("frame %d has no alpha payload", i)
		}
	}
	// Decode pair path: the alpha decode yields the same luma plane → the
	// RGBA alpha channel carries real values (not all-zero).
	dec := newDecodePair(an.Width, an.Height, an.fullRange, an.bt709)
	img, err := dec.decode(an.frames[0].payload, an.frames[0].alpha)
	if err != nil {
		t.Fatalf("decode with alpha: %v", err)
	}
	var sum uint64
	for i := 3; i < len(img.Pix); i += 4 {
		sum += uint64(img.Pix[i])
	}
	if sum == 0 {
		t.Fatal("alpha channel is all-zero: alpha stream not decoded")
	}
}

func TestSemaphorePermitsAllPlayers(t *testing.T) {
	// Regression pin (CI 2026-09-16 failure): the decode semaphore must
	// QUEUE excess producers, never deadlock them. More concurrent
	// players than permits — every one must still make progress within
	// the deadline. (The inverted acquire/release this test guards
	// against deadlocks the moment the permit buffer is full.)
	data, err := os.ReadFile("testdata/vp90-2-03-size-196x196.webm")
	if err != nil {
		t.Skipf("testdata missing: %v", err)
	}
	an, err := Parse(data)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	// Prime the permit pool to CAPACITY first: the inverted acquire
	// (a send instead of a receive) deadlocks instantly against a full
	// pool — without this, spare capacity on small machines masks the
	// bug exactly the way the 2-core dev VM did. The pool now lives in
	// vcodec (shared with h264vid), so prime it through its API.
	vcodec.PrimeToCapacity()
	const players = 6
	var wg sync.WaitGroup
	done := make(chan int, players)
	for i := 0; i < players; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			p := an.NewPlayer()
			p.Start()
			defer p.Stop()
			deadline := time.Now().Add(60 * time.Second)
			for p.DecodedCount() < 1 {
				if p.Failed() != nil {
					done <- -1
					return
				}
				if time.Now().After(deadline) {
					done <- -1
					return
				}
				time.Sleep(2 * time.Millisecond)
			}
			done <- 1
		}()
	}
	wg.Wait()
	close(done)
	ok := 0
	for r := range done {
		if r < 0 {
			t.Fatal("a producer starved under semaphore pressure (deadlock regression)")
		}
		ok++
	}
	if ok != players {
		t.Fatalf("only %d/%d players progressed", ok, players)
	}
}
