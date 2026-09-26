package h264vid

// tests-first pins for the in-chat H.264 video pipeline (slice 219).
//
// The two fixtures under testdata/ were encoded with ffmpeg and are
// shaped like what Telegram actually sends:
//
//	round_video.mp4   Constrained Baseline, no B-frames — a round video
//	                  note / typical video message (avc1, yuv420p)
//	high_bframes.mp4  High profile + CABAC + 2 B-frames — worst case
//
// Both are 128x96, 12 frames, 400ms, untagged colour (ffprobe reports
// color_range=unknown), which is what Telegram's uploads look like.
//
// Two independent kinds of pin live here:
//
//  1. DECODE CORRECTNESS (byte-exact). The pinned SHA-256 values are the
//     digest of the raw YUV that ffmpeg writes for these same MP4s, NOT
//     of our decoder's output — so a passing test proves pixel equality
//     with ffmpeg rather than self-consistency. Planes are hashed in
//     their native yuv420p layout so no colour conversion can muddy the
//     comparison. Derivation, repeatable anywhere:
//
//     ffmpeg -i <fixture> -pix_fmt yuv420p -f rawvideo out.yuv && sha256sum out.yuv
//
//     TestReferenceIsGenuineFFmpeg re-runs exactly that when ffmpeg is
//     present, so the provenance of the constants never has to be taken
//     on trust.
//
//  2. COLOUR CONVERSION. ffmpeg converts untagged yuv420p as LIMITED
//     range BT.601 (measured: Y=16→0, Y=235→255). govid's own
//     convertYCbCr420ToRGBA uses the full-range JFIF formula instead
//     (Y=16→16), which renders limited-range video washed out — blacks
//     sit at 16 and whites at 235. TestYUVToRGBIsLimitedRange pins that
//     we do the right thing and do NOT inherit that defect.

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"image"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"uniclient/vcodec"
)

// Pinned ffmpeg reference hashes (see the comment above).
const (
	roundVideoSHA256  = "6f09b28e141aca691f1cf6a163fdbbe9ee7a8a7617aed6464816e6b85da9bd57"
	highBframesSHA256 = "34d26fe8c56b6c304fd1e702b7f25cdff772a2d236de78cf9f017c639a8721c9"

	wantFrames         = 12
	wantWidth          = 128
	wantHeight         = 96
	wantDurationMillis = 400
)

func fixture(t *testing.T, name string) []byte {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("testdata", name))
	if err != nil {
		t.Skipf("testdata missing: %v", err)
	}
	return b
}

// hashPlanes writes Y rows, then Cb rows, then Cr rows — the rawvideo
// yuv420p layout ffmpeg emits — so the digest is comparable with an
// ffmpeg-produced file without any colour conversion in between.
func hashPlanes(h interface{ Write([]byte) (int, error) }, img *image.YCbCr) {
	b := img.Rect
	w, ht := b.Dx(), b.Dy()
	y0 := b.Min.Y*img.YStride + b.Min.X
	for y := 0; y < ht; y++ {
		h.Write(img.Y[y0+y*img.YStride : y0+y*img.YStride+w])
	}
	cw, ch := w/2, ht/2
	c0 := (b.Min.Y/2)*img.CStride + b.Min.X/2
	for y := 0; y < ch; y++ {
		h.Write(img.Cb[c0+y*img.CStride : c0+y*img.CStride+cw])
	}
	for y := 0; y < ch; y++ {
		h.Write(img.Cr[c0+y*img.CStride : c0+y*img.CStride+cw])
	}
}

// ── parsing ──────────────────────────────────────────────────────────────

func TestParseRoundVideo(t *testing.T) {
	v, err := Parse(fixture(t, "round_video.mp4"))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if v.Width != wantWidth || v.Height != wantHeight {
		t.Errorf("dims = %dx%d, want %dx%d", v.Width, v.Height, wantWidth, wantHeight)
	}
	if v.FrameCount != wantFrames {
		t.Errorf("FrameCount = %d, want %d", v.FrameCount, wantFrames)
	}
	ms := v.Total.Milliseconds()
	if ms < wantDurationMillis-5 || ms > wantDurationMillis+5 {
		t.Errorf("Total = %v (%dms), want ~%dms", v.Total, ms, wantDurationMillis)
	}
	// The display-order timeline must be strictly increasing. B-frames
	// make raw sample order differ from presentation order, which is
	// exactly what the sort in Parse exists to fix.
	if len(v.frames) != v.FrameCount {
		t.Fatalf("timeline has %d entries, want %d", len(v.frames), v.FrameCount)
	}
	for i := 1; i < len(v.frames); i++ {
		if v.frames[i].pts <= v.frames[i-1].pts {
			t.Fatalf("timeline not strictly increasing at %d: %v <= %v",
				i, v.frames[i].pts, v.frames[i-1].pts)
		}
	}
}

func TestParseHighBframes(t *testing.T) {
	v, err := Parse(fixture(t, "high_bframes.mp4"))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if v.FrameCount != wantFrames {
		t.Errorf("FrameCount = %d, want %d", v.FrameCount, wantFrames)
	}
	// If every sample were a sync sample there would be no B-frames and
	// the headline claim would be unproven by this fixture.
	if len(v.syncs) == wantFrames {
		t.Fatalf("every sample is a sync sample (%d) — no B-frames present", len(v.syncs))
	}
	if len(v.syncs) > 3 {
		t.Errorf("sync samples = %d, want a couple of GOP starts", len(v.syncs))
	}
}

// ── the headline pin: pixels equal ffmpeg's ──────────────────────────────

func TestDecodeMatchesFFmpegReference(t *testing.T) {
	for _, c := range []struct {
		file, want string
	}{
		{"round_video.mp4", roundVideoSHA256},
		{"high_bframes.mp4", highBframesSHA256},
	} {
		t.Run(c.file, func(t *testing.T) {
			v, err := Parse(fixture(t, c.file))
			if err != nil {
				t.Fatalf("Parse: %v", err)
			}
			h := sha256.New()
			n := 0
			// decodePass is the exact routine the playback producer uses;
			// only the final colour conversion is skipped here.
			if err := v.decodePass(0, 0, func(_ int, img *image.YCbCr) error {
				hashPlanes(h, img)
				n++
				return nil
			}); err != nil {
				t.Fatalf("decodePass: %v", err)
			}
			if n != wantFrames {
				t.Errorf("decoded %d frames, want %d", n, wantFrames)
			}
			if got := hex.EncodeToString(h.Sum(nil)); got != c.want {
				t.Errorf("decoded sha256 = %s\nwant           %s\n"+
					"— decoded output differs from ffmpeg", got, c.want)
			}
		})
	}
}

// Provenance: re-derive the pinned constants from the committed MP4s with
// ffmpeg itself. This is what makes the pins trustworthy rather than
// merely self-consistent — skipped when ffmpeg is absent (CI).
func TestReferenceIsGenuineFFmpeg(t *testing.T) {
	ff, err := exec.LookPath("ffmpeg")
	if err != nil {
		t.Skip("ffmpeg not available")
	}
	for _, c := range []struct{ file, want string }{
		{"round_video.mp4", roundVideoSHA256},
		{"high_bframes.mp4", highBframesSHA256},
	} {
		t.Run(c.file, func(t *testing.T) {
			src := filepath.Join("testdata", c.file)
			if _, err := os.Stat(src); err != nil {
				t.Skipf("testdata missing: %v", err)
			}
			out := filepath.Join(t.TempDir(), "ref.yuv")
			cmd := exec.Command(ff, "-loglevel", "error", "-y", "-i", src,
				"-pix_fmt", "yuv420p", "-f", "rawvideo", out)
			if b, err := cmd.CombinedOutput(); err != nil {
				t.Skipf("ffmpeg failed: %v (%s)", err, b)
			}
			raw, err := os.ReadFile(out)
			if err != nil {
				t.Fatal(err)
			}
			sum := sha256.Sum256(raw)
			if got := hex.EncodeToString(sum[:]); got != c.want {
				t.Errorf("ffmpeg produced sha256 = %s\nwant             %s\n"+
					"— the pinned constant does not come from ffmpeg; fix the pin",
					got, c.want)
			}
		})
	}
}

// The playback producer must store the very frames decodePass produces —
// otherwise the ffmpeg pin above would not cover what the GUI draws.
func TestPlayerFramesMatchDecodePass(t *testing.T) {
	v, err := Parse(fixture(t, "round_video.mp4"))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	var ref []*image.YCbCr
	if err := v.decodePass(0, 0, func(_ int, img *image.YCbCr) error {
		ref = append(ref, img)
		return nil
	}); err != nil {
		t.Fatalf("decodePass: %v", err)
	}

	p := v.NewPlayer()
	defer p.Stop()
	p.SetLoop(false)
	p.Start()
	waitDecoded(t, p, v.FrameCount)

	for i := 0; i < v.FrameCount; i++ {
		got := p.frameAtIndex(i)
		if got == nil {
			t.Fatalf("frame %d missing from ring", i)
		}
		want := yuvToRGB(ref[i])
		if !bytes.Equal(got.Pix, want.Pix) {
			t.Errorf("frame %d: ring pixels differ from decodePass output", i)
			break
		}
	}
}

// ── colour conversion: limited range, NOT govid's full range ─────────────

func TestYUVToRGBIsLimitedRange(t *testing.T) {
	conv := func(y, cb, cr uint8) (uint8, uint8, uint8) {
		mk := func(yy uint8) *image.YCbCr {
			return &image.YCbCr{
				// 2x2 is the smallest 4:2:0 plane set that is legal: one
				// chroma sample covers the whole block. Strides must match.
				Y: []byte{yy, yy, yy, yy}, Cb: []byte{cb}, Cr: []byte{cr},
				YStride: 2, CStride: 1,
				SubsampleRatio: image.YCbCrSubsampleRatio420,
				Rect:           image.Rect(0, 0, 2, 2),
			}
		}
		rgba := yuvToRGB(mk(y))
		return rgba.Pix[0], rgba.Pix[1], rgba.Pix[2]
	}

	// Limited range: Y=16 is black, Y=235 is white. (Full range would
	// give 16 and 235 — the washed-out rendering we are fixing. ffmpeg
	// measured at exactly these values.)
	if r, g, b := conv(16, 128, 128); r != 0 || g != 0 || b != 0 {
		t.Errorf("Y=16 → (%d,%d,%d), want (0,0,0) — not limited range", r, g, b)
	}
	if r, g, b := conv(235, 128, 128); r != 255 || g != 255 || b != 255 {
		t.Errorf("Y=235 → (%d,%d,%d), want (255,255,255) — not limited range", r, g, b)
	}
	// Neutral chroma in the middle of the range → neutral grey, and it
	// must land near mid-grey rather than at raw Y.
	if r, g, b := conv(128, 128, 128); r < 125 || r > 134 || g != r || b != r {
		t.Errorf("Y=128 neutral → (%d,%d,%d), want ~ (131,131,131)", r, g, b)
	}
	// Strong blue chroma (Cb high) with mid luma must push blue up and
	// pull green down — Cb drives the blue axis, Cr the red one.
	if _, g, b := conv(128, 240, 128); b <= 131 {
		t.Errorf("blue chroma did not raise blue: B=%d", b)
	} else if g >= 131 {
		t.Errorf("blue chroma did not lower green: G=%d", g)
	}
	// Above-white / below-black must clamp, never wrap.
	if r, _, _ := conv(255, 128, 240); r != 255 {
		t.Errorf("over-range red clamped to %d, want 255", r)
	}
}

// ── guards (hostile/malformed input must never OOM or panic the app) ─────

func TestParseRejectsGarbage(t *testing.T) {
	mp4 := fixture(t, "round_video.mp4")
	truncated := append([]byte{}, mp4...)
	if len(truncated) > 64 {
		truncated = truncated[:64]
	}
	moovLess := append([]byte{}, mp4...)
	if len(moovLess) > 1024 {
		moovLess = moovLess[len(moovLess)-1024:] // tail only: mdat without moov
	}
	for name, in := range map[string][]byte{
		"empty":     {},
		"random":    bytes.Repeat([]byte{0xDE, 0xAD, 0xBE, 0xEF}, 64),
		"text":      []byte("this is definitely not an mp4 container at all"),
		"truncated": truncated,
		"nullbytes": make([]byte, 4096),
		"moov-less": moovLess,
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := Parse(in); err == nil {
				t.Errorf("%s: Parse accepted invalid input", name)
			} else {
				t.Logf("%s: rejected with: %v", name, err)
			}
		})
	}
}

func TestParseRejectsOversizedDimensions(t *testing.T) {
	// A crafted SPS claiming absurd dimensions must be refused rather
	// than allocated.
	v := &Video{Width: maxPixels + 1, Height: 1}
	if !errors.Is(v.validateDims(), ErrTooLarge) {
		t.Errorf("validateDims on %d px did not report ErrTooLarge", v.Width)
	}
}

// ── frame clock ──────────────────────────────────────────────────────────

func TestFrameClockAdvancesAndLoops(t *testing.T) {
	v, err := Parse(fixture(t, "round_video.mp4"))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	p := v.NewPlayer()
	defer p.Stop()
	p.SetLoop(true)
	p.Start()
	waitDecoded(t, p, v.FrameCount)

	first := p.frameAtIndex(0)
	if first == nil {
		t.Fatal("frame 0 missing after full decode")
	}
	// Mid-clip must be a different frame than frame 0.
	mid := p.FrameAt(v.Total / 2)
	if mid == nil {
		t.Fatal("FrameAt(mid) = nil after full decode")
	}
	if bytes.Equal(first.Pix, mid.Pix) {
		t.Error("mid-clip frame identical to frame 0 (clock not advancing)")
	}
	// Looping: past the end wraps back to frame 0.
	wrapped := p.FrameAt(v.Total + v.frames[0].dur/2)
	if wrapped == nil {
		t.Fatal("FrameAt past Total = nil while looping")
	}
	if !bytes.Equal(wrapped.Pix, first.Pix) {
		t.Error("loop did not wrap to frame 0")
	}
	// NextFrameIn must always be a sane repaint delay.
	for _, e := range []time.Duration{0, v.Total / 3, v.Total - time.Millisecond} {
		d := p.NextFrameIn(e)
		if d < time.Millisecond || d > v.Total {
			t.Errorf("NextFrameIn(%v) = %v, out of range", e, d)
		}
	}
}

func TestFrameClockClampsWhenNotLooping(t *testing.T) {
	v, err := Parse(fixture(t, "round_video.mp4"))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	p := v.NewPlayer()
	defer p.Stop()
	p.SetLoop(false)
	p.Start()
	waitDecoded(t, p, v.FrameCount)

	last := p.frameAtIndex(v.FrameCount - 1)
	if last == nil {
		t.Fatal("last frame missing")
	}
	// Far past the end: hold the final frame, never wrap.
	img := p.FrameAt(v.Total * 10)
	if img == nil {
		t.Fatal("FrameAt far past end = nil (should hold last frame)")
	}
	if !bytes.Equal(img.Pix, last.Pix) {
		t.Error("past-the-end frame is not the last frame")
	}
}

// ── seek (GOP-aligned restart) ───────────────────────────────────────────

func TestSeekRestartsAtKeyframe(t *testing.T) {
	data := fixture(t, "round_video.mp4")
	v, err := Parse(data)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if len(v.syncs) < 2 {
		t.Skipf("fixture has %d sync sample(s); need >=2 to test mid-stream seek", len(v.syncs))
	}

	// Reference: a full sequential decode of the same file.
	ref, err := Parse(data)
	if err != nil {
		t.Fatal(err)
	}
	rp := ref.NewPlayer()
	defer rp.Stop()
	rp.SetLoop(true)
	rp.Start()
	waitDecoded(t, rp, ref.FrameCount)

	p := v.NewPlayer()
	defer p.Stop()
	p.SetLoop(true)
	// Seek BEFORE starting so the producer is guaranteed to begin at the
	// GOP containing the target — this is what makes the restart real
	// rather than a race against an already-finished decode.
	target := v.frames[v.FrameCount-2].pts
	p.Seek(target)
	p.Start()
	waitDecoded(t, p, v.FrameCount)

	got := p.frameAtIndex(v.FrameCount - 1)
	want := rp.frameAtIndex(ref.FrameCount - 1)
	if got == nil || want == nil {
		t.Fatalf("missing frames after seek (missing=%v/%v)", got == nil, want == nil)
	}
	if !bytes.Equal(got.Pix, want.Pix) {
		t.Error("frame after seek differs from a full sequential decode")
	}
}

// ── lifecycle ────────────────────────────────────────────────────────────

func TestStopReleasesAndIsIdempotent(t *testing.T) {
	v, err := Parse(fixture(t, "round_video.mp4"))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	p := v.NewPlayer()
	p.Start()
	waitDecoded(t, p, 1)
	p.Stop()
	p.Stop() // second Stop must not panic or block
	if p.Failed() != nil {
		t.Errorf("Stop surfaced failure: %v", p.Failed())
	}
}

// A permanently broken stream reports through Failed() instead of
// spinning forever (the GUI falls back to the poster frame).
func TestCorruptStreamReportsFailure(t *testing.T) {
	good := fixture(t, "round_video.mp4")
	if len(good) < 4096 {
		t.Skip("fixture too small to corrupt safely")
	}
	// Corrupt ONLY inside the mdat payload. The old second-half flip
	// also destroyed moov (it rides at the tail of this fixture):
	// Parse rejected the file upfront, the test skipped, and the
	// runtime p.Failed() path was never exercised (slice-280 finding).
	mdatStart, mdatEnd := -1, -1
	for off := 0; off+8 <= len(good); {
		sz := int(binary.BigEndian.Uint32(good[off : off+4]))
		typ := string(good[off+4 : off+8])
		if sz < 8 || off+sz > len(good) {
			break
		}
		if typ == "mdat" {
			mdatStart, mdatEnd = off+8, off+sz
		}
		off += sz
	}
	if mdatStart < 0 || mdatEnd-mdatStart < 2048 {
		t.Skipf("no usable mdat payload in fixture (%d..%d)", mdatStart, mdatEnd)
	}
	bad := append([]byte{}, good...)
	mid := (mdatStart + mdatEnd) / 2
	for i := mid - 512; i < mid+512 && i < mdatEnd; i++ {
		bad[i] ^= 0xFF
	}
	v, err := Parse(bad)
	if err != nil {
		// A parse-time rejection is also an honest failure report —
		// log it instead of silently skipping coverage.
		t.Logf("corruption reported at parse (honest failure): %v", err)
		return
	}
	p := v.NewPlayer()
	defer p.Stop()
	p.SetLoop(false)
	p.Start()
	deadline := time.Now().Add(30 * time.Second)
	for time.Now().Before(deadline) {
		if p.Failed() != nil {
			return // honest failure reported
		}
		if p.DecodedCount() >= v.FrameCount {
			return // corruption was survivable; we terminated either way
		}
		time.Sleep(10 * time.Millisecond)
	}
	if p.Failed() == nil && p.DecodedCount() < v.FrameCount {
		t.Fatalf("neither completed nor failed: decoded %d/%d",
			p.DecodedCount(), v.FrameCount)
	}
}

// ── shared decode budget (regression pin, see vcodec) ────────────────────

// More concurrent video producers than permits must QUEUE, never deadlock.
// The pool is primed to CAPACITY first so an inverted Acquire (a send
// rather than a receive) blocks instantly on ANY machine — the slice-216
// CI failure only surfaced where NumCPU filled the buffer.
func TestProducersQueueUnderFullDecodePool(t *testing.T) {
	v, err := Parse(fixture(t, "round_video.mp4"))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	vcodec.PrimeToCapacity()

	players := vcodec.Cap() * 4
	var wg sync.WaitGroup
	done := make(chan struct{})
	for i := 0; i < players; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			p := v.NewPlayer()
			p.SetLoop(false)
			p.Start()
			waitDecodedQuiet(t, p, v.FrameCount)
			p.Stop()
		}()
	}
	go func() { wg.Wait(); close(done) }()
	select {
	case <-done:
	case <-time.After(180 * time.Second):
		t.Fatal("a video producer starved under semaphore pressure (deadlock regression)")
	}
}

// ── helpers ──────────────────────────────────────────────────────────────

func waitDecoded(t *testing.T, p *Player, n int) {
	t.Helper()
	deadline := time.Now().Add(60 * time.Second)
	for time.Now().Before(deadline) {
		if err := p.Failed(); err != nil {
			t.Fatalf("decode failed: %v", err)
		}
		if p.DecodedCount() >= n {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %d frames (got %d)", n, p.DecodedCount())
}

// waitDecodedQuiet is waitDecoded for worker goroutines (no *testing.T
// Fatal from a non-test goroutine).
func waitDecodedQuiet(t *testing.T, p *Player, n int) {
	t.Helper()
	deadline := time.Now().Add(150 * time.Second)
	for time.Now().Before(deadline) {
		if p.Failed() != nil {
			return
		}
		if p.DecodedCount() >= n {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Errorf("worker timed out: decoded %d/%d", p.DecodedCount(), n)
}
