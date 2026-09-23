// Package h264vid plays H.264/AVC video carried in MP4 containers — the
// format Telegram uses for video messages and round video notes — with
// nothing but pure Go (§1.1).
//
// It exists because the repo's research concluded twice that "no pure-Go
// full H.264 decoder exists". That conclusion was wrong: github.com/liqmix/govid
// ships one (CAVLC+CABAC, I/P/B, High profile) and it decodes our fixtures
// bit-for-bit identically to ffmpeg — see research/h264_decoder.md and the
// pinned hashes in h264vid_test.go.
//
// Architecture mirrors vp9anim (rated 9/10 in the slice-216 work) because
// the problem shape is the same: a background decode-ahead producer behind
// the shared vcodec permit pool, feeding a frame clock the Gio frame
// thread queries. Three things differ, all forced by H.264:
//
//   - Inter frames need SEQUENTIAL decode, so the decoder cannot jump
//     around; a loop or a seek has to rebuild the decoder and resume from
//     a keyframe (Seek is therefore GOP-aligned).
//   - MP4 sample order is DECODE order, but presentation order differs
//     once B-frames are involved, so the display timeline is built by
//     sorting composition timestamps (stts+ctts) ascending.
//   - Colour conversion must be limited-range BT.601 — ffmpeg's treatment
//     of untagged yuv420p — NOT the full-range JFIF formula govid's own
//     helper uses, which renders such video washed out (blacks parked at
//     16 instead of 0).
package h264vid

import (
	"bytes"
	"errors"
	"fmt"
	"image"
	"io"
	"sync"
	"time"

	"github.com/liqmix/govid/h264"

	"uniclient/vcodec"
)

// Errors reported by Parse. The GUI turns these into an honest static
// poster frame (§1.10 — never fake playback).
var (
	// ErrNotVideo: not a readable MP4 with a video track.
	ErrNotVideo = errors.New("h264vid: not an H.264 MP4")
	// ErrUnsupported: an MP4, but not an H.264 (avc1) video track.
	ErrUnsupported = errors.New("h264vid: unsupported video codec")
	// ErrTooLarge: exceeds a size guard; refused rather than allocated.
	ErrTooLarge = errors.New("h264vid: video exceeds size guard")
	// ErrDecodeFailed: the container could not be DECODED — on a stream
	// this is usually a failed/short read, not a verdict about the bytes
	// (slice 230 — see IsPermanent).
	ErrDecodeFailed = errors.New("h264vid: container decode failed")
)

// IsPermanent reports whether err is a verdict about the BYTES
// themselves (the same bytes fail the same way forever — pin the entry
// and never re-parse) versus a failure to READ them (retryable: a stream
// whose chunk fetch died must be attempted again — §1.10, a transient
// error must not dead-end a good clip forever). Pure — unit-tested in
// permfail_test.go.
func IsPermanent(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, ErrUnsupported) || errors.Is(err, ErrTooLarge) {
		return true
	}
	if errors.Is(err, ErrDecodeFailed) {
		return false
	}
	return errors.Is(err, ErrNotVideo)
}

const (
	// maxPixels bounds decoded frame size against a hostile/corrupt SPS
	// claiming absurd dimensions (would otherwise OOM the app).
	maxPixels = 4096 * 4096
	// maxFrames bounds a hostile file that claims millions of samples.
	maxFrames = 6000
	// ringBudget is how many decoded RGBA frames a single player may keep
	// resident. Clips that fit are decoded completely up front (smooth
	// playback, no mid-playback stalls); larger ones switch to a sliding
	// window that stays ringLookahead frames ahead of the playhead.
	ringBudget = 48 << 20
	// ringLookahead is how far the producer runs ahead of the playhead in
	// sliding-window mode.
	ringLookahead = 6

	// defaultFPS is the timeline fallback when a stream declares no usable
	// frame duration (matches vp9anim's fallback).
	defaultFrameDur = 40 * time.Millisecond
)

// timing is one frame's place in the display-order timeline.
type timing struct {
	pts time.Duration
	dur time.Duration
}

// syncEntry is one keyframe: where it sits in decode order (so a session
// can be resumed there) and which display frame it produces.
type syncEntry struct {
	pts    time.Duration
	sample uint32 // 1-based decode-order sample number
	index  int    // display-order frame index this keyframe produces
}

// Video is a parsed, validated MP4/H.264 clip ready to play.
//
// Parse takes ownership of data; the caller must not mutate it
// afterwards. Payloads are read through ra on demand (from the backing
// array for a byte clip, fetch-by-fetch for a stream), so a Video can
// be parsed from a file that has not fully downloaded yet (slice 229,
// streamsrc.go).
type Video struct {
	// Width, Height are the displayed dimensions.
	Width, Height int
	// Total is the clip duration used to drive the looping playhead.
	Total time.Duration
	// FrameCount is the number of display frames.
	FrameCount int

	ra      io.ReaderAt // payload source: bytes.Reader, os.File, or a stream section
	moov    *moovInfo   // sample ranges + timing tables
	frames  []timing    // display order: strictly increasing pts
	syncs   []syncEntry // keyframes, pts ascending
	keepAll bool        // the whole clip fits in ringBudget
}

// indexSample is one sample as recorded by Parse's index pass: its
// presentation time, whether it is a sync sample, and its 1-based
// position in DECODE order.
type indexSample struct {
	pts    time.Duration
	sync   bool
	decode uint32
}

// Parse reads a MP4's index (dimensions, display timeline, keyframe map)
// without decoding it. Decoding happens later, on the producer goroutine.
// Ownership of data transfers to the Video (it must not be mutated
// afterwards). Parse and ParseSeek share one implementation in
// streamsrc.go, so a byte clip and a streamed clip cannot diverge.
func Parse(data []byte) (*Video, error) {
	if len(data) == 0 {
		return nil, ErrNotVideo
	}
	return parseSource(bytes.NewReader(data))
}

// finishTimeline turns the raw per-sample index (decode-order pts +
// sync flags, built from the moov tables without touching a single
// payload byte — streamsrc.go) into the display-order timeline, the
// sync map and the ring budget. container is the mdhd-derived clip
// duration; the timeline never ends before the last frame starts.
//
// Decode order != display order once B-frames exist (the high_bframes
// fixture reads 0,100ms,33ms,67ms,…) in sample order. Sort by
// presentation time to get the display order the GUI must paint.
func (v *Video) finishTimeline(order []indexSample, container time.Duration) error {
	if len(order) == 0 {
		return fmt.Errorf("%w: no samples", ErrNotVideo)
	}
	if len(order) > maxFrames {
		return fmt.Errorf("%w: %d frames > %d", ErrTooLarge, len(order), maxFrames)
	}
	v.FrameCount = len(order)

	rank := make([]int, len(order)) // decode index -> display index
	sorted := make([]indexSample, len(order))
	copy(sorted, order)
	// Stable permutation: sort a slice of indices by pts.
	idx := make([]int, len(order))
	for i := range idx {
		idx[i] = i
	}
	sortByPTS(idx, order)
	for display, di := range idx {
		sorted[display] = order[di]
		rank[di] = display
	}

	v.frames = make([]timing, len(sorted))
	for i, s := range sorted {
		v.frames[i] = timing{pts: s.pts}
	}
	total := container
	if last := sorted[len(sorted)-1].pts; total <= last {
		// Derive from the cadence: same fallback chain as vp9anim.
		if len(sorted) >= 2 {
			total = last + (last - sorted[len(sorted)-2].pts)
		} else {
			total = last + defaultFrameDur
		}
	}
	for i := range v.frames {
		if i+1 < len(v.frames) {
			v.frames[i].dur = v.frames[i+1].pts - v.frames[i].pts
		} else {
			v.frames[i].dur = total - v.frames[i].pts
		}
		if v.frames[i].dur <= 0 {
			v.frames[i].dur = defaultFrameDur
		}
	}
	v.Total = total

	for di, s := range order {
		if s.sync {
			v.syncs = append(v.syncs, syncEntry{pts: s.pts, sample: s.decode, index: rank[di]})
		}
	}
	// A stream with no stss declares every sample a sync sample; the
	// tables report them all as keyframes, which is fine. But a stream
	// with NO keyframe at all cannot be decoded sequentially — refuse it.
	if len(v.syncs) == 0 {
		return fmt.Errorf("%w: no keyframes", ErrNotVideo)
	}

	v.keepAll = int64(v.FrameCount)*int64(v.Width*v.Height*4) <= ringBudget
	return nil
}

// sortByPTS orders idx so that order[idx[i]] is ascending by pts.
// Insertion sort is fine here (a few thousand entries at most) and keeps
// equal timestamps in their original order.
func sortByPTS(idx []int, order []indexSample) {
	for i := 1; i < len(idx); i++ {
		v := idx[i]
		j := i - 1
		for j >= 0 && order[idx[j]].pts > order[v].pts {
			idx[j+1] = idx[j]
			j--
		}
		idx[j+1] = v
	}
}

// validateDims refuses absurd dimensions before anything is allocated.
func (v *Video) validateDims() error {
	if v.Width <= 0 || v.Height <= 0 {
		return fmt.Errorf("%w: bad dimensions %dx%d", ErrNotVideo, v.Width, v.Height)
	}
	if v.Width*v.Height > maxPixels {
		return fmt.Errorf("%w: %dx%d exceeds %d pixels", ErrTooLarge, v.Width, v.Height, maxPixels)
	}
	return nil
}

// syncFor returns the keyframe at or before the given presentation time.
func (v *Video) syncFor(t time.Duration) syncEntry {
	best := v.syncs[0]
	for _, s := range v.syncs {
		if s.pts <= t {
			best = s
		} else {
			break
		}
	}
	return best
}

// decodePass runs a sequential decode from a keyframe and reports every
// frame it produces, in display order, starting at display index base.
//
// This is the ONE decode routine in the package: the playback producer
// uses it (converting each frame to RGBA for the ring) and the tests use
// it to hash raw planes against ffmpeg. Sharing it is what makes the
// ffmpeg pin cover the pixels the GUI actually draws.
func (v *Video) decodePass(startSample uint32, base int, fn func(idx int, img *image.YCbCr) error) error {
	if startSample < 1 {
		startSample = 1
	}
	p := v.packetSrc()
	// Resume exactly at the requested sample. The skip is METADATA-ONLY:
	// the old demuxer read and discarded every skipped payload, which a
	// fetch-on-read stream would pay 512 KiB per miss for. The pump
	// prepends SPS/PPS to each sync sample itself, which is what lets a
	// fresh decoder start mid-file.
	p.skip(startSample - 1)

	c := h264.NewCodec()
	idx := base
	emit := func(y *image.YCbCr) error {
		if y == nil {
			return nil // reorder buffer still filling, or parameter sets only
		}
		if err := fn(idx, y); err != nil {
			return err
		}
		idx++
		return nil
	}
	for {
		pkt, err := p.next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		fr, err := c.Decode(pkt)
		if err != nil {
			return fmt.Errorf("h264: decode: %w", err)
		}
		if fr == nil {
			continue
		}
		if err := emit(fr.YCbCr); err != nil {
			return err
		}
	}
	// Drain the B-frame reorder buffer's tail.
	for {
		fr := c.Drain()
		if fr == nil {
			return nil
		}
		if err := emit(fr.YCbCr); err != nil {
			return err
		}
	}
}

// ── colour conversion ───────────────────────────────────────────────────
//
// Limited-range BT.601, which is what ffmpeg does with untagged yuv420p
// (measured: Y=16→0, Y=235→255; a BT.709 matrix would give G=154 where
// BT.601 gives 174 for the same chroma). govid's own helper uses the
// full-range JFIF formula instead, which would park blacks at 16 and
// whites at 235 — visibly washed out — so we convert ourselves.
//
// Integer form of the CCIR-601 equations, valid for 8-bit 4:2:0:
//
//	C = Y-16, D = Cb-128, E = Cr-128
//	R = (298*C           + 409*E + 128) >> 8
//	G = (298*C - 100*D   - 208*E + 128) >> 8
//	B = (298*C + 516*D           + 128) >> 8
func yuvToRGB(src *image.YCbCr) *image.RGBA {
	b := src.Rect
	w, h := b.Dx(), b.Dy()
	dst := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		yi := (b.Min.Y+y)*src.YStride + b.Min.X
		ci := ((b.Min.Y+y)/2)*src.CStride + b.Min.X/2
		for x := 0; x < w; x++ {
			c := int(src.Y[yi+x]) - 16
			if c < 0 {
				c = 0
			}
			d := int(src.Cb[ci+x/2]) - 128
			e := int(src.Cr[ci+x/2]) - 128

			r := (298*c + 409*e + 128) >> 8
			g := (298*c - 100*d - 208*e + 128) >> 8
			bl := (298*c + 516*d + 128) >> 8

			o := dst.PixOffset(x, y)
			dst.Pix[o] = clamp8(r)
			dst.Pix[o+1] = clamp8(g)
			dst.Pix[o+2] = clamp8(bl)
			dst.Pix[o+3] = 0xFF
		}
	}
	return dst
}

func clamp8(v int) uint8 {
	if v < 0 {
		return 0
	}
	if v > 255 {
		return 255
	}
	return uint8(v)
}

// ── player ──────────────────────────────────────────────────────────────

// restartReq tells the producer to rebuild its decoder and resume at a
// keyframe. Produced by Seek and by the loop wrap.
type restartReq struct {
	sample uint32        // decode-order sample to resume from (1-based)
	base   int           // display index that sample yields
	at     time.Duration // playhead to adopt
}

// Video frames are keyed by display index in ring, exactly like vp9anim.
type ringFrame = image.RGBA

// Player plays one Video on a background producer goroutine.
type Player struct {
	v *Video

	mu       sync.Mutex
	cond     *sync.Cond
	ring     map[int]*ringFrame
	oldest   int // lowest display index still resident
	next     int // decode frontier: next display index to decode
	consumed int // highest display index the playhead has asked for
	fail     error
	stopped  bool
	started  bool
	loop     bool
	restart  *restartReq // pending GOP-aligned resume
	keepAll  bool

	// Playhead. pausePos holds the position while stopped; when playing,
	// the position is measured from start.
	playing  bool
	start    time.Time
	pausePos time.Duration

	wg sync.WaitGroup
}

// NewPlayer creates a player for the clip. Nothing starts until Start.
func (v *Video) NewPlayer() *Player {
	p := &Player{
		v:       v,
		ring:    make(map[int]*ringFrame),
		keepAll: v.keepAll,
		// Begin on the clock's frame 0.
		oldest: 0,
		next:   0,
	}
	p.cond = sync.NewCond(&p.mu)
	return p
}

// SetLoop controls whether the playhead wraps at Total. Round video notes
// loop; ordinary video messages play once and hold the last frame.
// Call before Start for a clean producer, or any time afterwards — a
// running producer picks it up on its next clock check.
func (p *Player) SetLoop(v bool) {
	p.mu.Lock()
	p.loop = v
	p.cond.Broadcast()
	p.mu.Unlock()
}

// Start launches the background producer (idempotent).
func (p *Player) Start() {
	p.mu.Lock()
	p.startLocked()
	p.mu.Unlock()
}

// startLocked launches the producer goroutine. Caller holds p.mu.
func (p *Player) startLocked() {
	if p.started || p.stopped {
		return
	}
	p.started = true
	if !p.playing && p.pausePos == 0 {
		// Play by default: callers that want a frozen frame simply do not
		// advance the clock (FrameAt takes an explicit elapsed anyway).
		p.playing = true
		p.start = time.Now()
	}
	p.wg.Add(1)
	go p.produce()
}

// Stop terminates the producer and releases the frame cache. Safe to
// call twice.
func (p *Player) Stop() {
	p.mu.Lock()
	if p.stopped {
		p.mu.Unlock()
		return
	}
	p.stopped = true
	p.cond.Broadcast()
	p.mu.Unlock()
	p.wg.Wait()
	p.mu.Lock()
	p.ring = nil
	p.mu.Unlock()
}

// Play resumes the playhead.
func (p *Player) Play() {
	p.mu.Lock()
	if !p.playing {
		p.playing = true
		p.start = time.Now().Add(-p.pausePos)
		p.cond.Broadcast()
	}
	p.mu.Unlock()
}

// Pause freezes the playhead where it is.
func (p *Player) Pause() {
	p.mu.Lock()
	if p.playing {
		p.pausePos = time.Since(p.start)
		p.playing = false
		p.cond.Broadcast()
	}
	p.mu.Unlock()
}

// TogglePlay flips between Play and Pause.
func (p *Player) TogglePlay() {
	p.mu.Lock()
	if p.playing {
		p.pausePos = time.Since(p.start)
		p.playing = false
	} else {
		p.playing = true
		p.start = time.Now().Add(-p.pausePos)
	}
	p.cond.Broadcast()
	p.mu.Unlock()
}

// Playing reports whether the playhead is advancing.
func (p *Player) Playing() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.playing
}

// Position reports the current playhead.
func (p *Player) Position() time.Duration {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.positionLocked()
}

func (p *Player) positionLocked() time.Duration {
	if !p.playing {
		return p.pausePos
	}
	return time.Since(p.start)
}

// Duration reports the clip length.
func (p *Player) Duration() time.Duration { return p.v.Total }

// Seek moves the playhead and, if the target is not already resident,
// has the producer rebuild its decoder at the keyframe at or before t.
// Seeking is therefore GOP-aligned: the first frame shown after a seek is
// always a correct decode, never a mid-GOP guess.
func (p *Player) Seek(t time.Duration) {
	if t < 0 {
		t = 0
	}
	if p.v.Total > 0 && t > p.v.Total {
		t = p.v.Total
	}
	s := p.v.syncFor(t)

	p.mu.Lock()
	p.pausePos = t
	if p.playing {
		p.start = time.Now().Add(-t)
	}
	// Only rebuild when the target frame is not already in the ring.
	if _, ok := p.ring[s.index]; !ok || s.index > p.next || s.index < p.oldest {
		p.restart = &restartReq{sample: s.sample, base: s.index, at: t}
	}
	p.cond.Broadcast()
	p.mu.Unlock()
}

// DecodedCount reports the decode frontier (test/progress hook).
func (p *Player) DecodedCount() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.next
}

// Failed reports a permanent decode failure (corrupt stream).
func (p *Player) Failed() error {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.fail
}

// frameAtIndex returns a decoded frame straight from the ring — used by
// tests to compare pixels across decodes.
func (p *Player) frameAtIndex(i int) *image.RGBA {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.ring[i]
}

// produce decodes frames sequentially, staying ahead of the playhead by
// ringLookahead frames in sliding-window mode (or decoding the whole
// clip up front when it fits the ring budget). Parks on the condition
// variable when there is nothing to do.
//
// H.264 inter frames need the decoder fed in order, so a loop wrap or a
// seek does not "jump": it rebuilds the demuxer+decoder at a keyframe.
func (p *Player) produce() {
	defer p.wg.Done()

	var (
		pass *passRunner
	)
	newPass := func(sample uint32, b int) error {
		if pass != nil {
			pass.close()
		}
		pr, err := p.v.newPass(sample, b)
		if err != nil {
			return err
		}
		pass = pr
		return nil
	}
	if err := newPass(1, 0); err != nil {
		p.mu.Lock()
		p.fail = err
		p.cond.Broadcast()
		p.mu.Unlock()
		return
	}
	defer func() {
		if pass != nil {
			pass.close()
		}
	}()

	for {
		p.mu.Lock()
		for !p.workReadyLocked() && !p.stopped && p.restart == nil {
			p.cond.Wait()
		}
		if p.stopped {
			p.mu.Unlock()
			return
		}
		if r := p.restart; r != nil {
			p.restart = nil
			p.ring = make(map[int]*ringFrame)
			p.next = r.base
			p.oldest = r.base
			p.consumed = r.base
			pauseAt := r.at
			p.pausePos = pauseAt
			if p.playing {
				p.start = time.Now().Add(-pauseAt)
			}
			p.mu.Unlock()
			if err := newPass(r.sample, r.base); err != nil {
				p.mu.Lock()
				p.fail = err
				p.cond.Broadcast()
				p.mu.Unlock()
				return
			}
			continue
		}
		want := p.next
		p.mu.Unlock()

		// Decode exactly one frame off the lock, under the shared budget.
		vcodec.Acquire()
		p.mu.Lock()
		if p.stopped || p.restart != nil || p.next != want {
			// State moved while queued for the permit: drop it and redo.
			p.mu.Unlock()
			vcodec.Release()
			continue
		}
		p.mu.Unlock()

		idx, yuv, err := pass.next()
		vcodec.Release()

		if err == io.EOF {
			// End of the clip. Non-looping: nothing more to do until a
			// Seek restarts us. Looping: wait for the playhead to wrap,
			// which FrameAt turns into a restart at the first keyframe —
			// re-decoding immediately would spin the CPU on a full lap.
			p.mu.Lock()
			for !p.stopped && p.restart == nil && p.loop {
				p.cond.Wait()
			}
			if p.stopped {
				p.mu.Unlock()
				return
			}
			if p.restart != nil {
				p.mu.Unlock()
				continue
			}
			// Non-loop, no restart: park until Seek/Stop.
			for !p.stopped && p.restart == nil {
				p.cond.Wait()
			}
			if p.stopped {
				p.mu.Unlock()
				return
			}
			p.mu.Unlock()
			continue
		}
		if err != nil {
			p.mu.Lock()
			p.fail = err
			p.stopped = true
			p.cond.Broadcast()
			p.mu.Unlock()
			return
		}
		if yuv == nil {
			continue // reorder buffer filling
		}

		img := yuvToRGB(yuv)
		p.mu.Lock()
		if p.stopped {
			p.mu.Unlock()
			return
		}
		if p.ring == nil {
			p.ring = make(map[int]*ringFrame)
		}
		p.ring[idx] = img
		p.next = idx + 1
		if !p.keepAll {
			// Sliding window: drop frames far behind the playhead so a
			// long video cannot grow without bound.
			limit := p.consumed - ringLookahead
			for i := p.oldest; i <= limit && i < p.next; i++ {
				delete(p.ring, i)
				p.oldest = i + 1
			}
		}
		p.cond.Broadcast()
		p.mu.Unlock()
	}
}

// workReadyLocked reports whether the producer has a frame to decode.
// Caller holds p.mu.
func (p *Player) workReadyLocked() bool {
	if p.next >= p.v.FrameCount {
		return false // lap complete: wait for a wrap/seek restart
	}
	if p.keepAll {
		return p.ring[p.next] == nil
	}
	return p.next <= p.consumed+ringLookahead
}

// FrameAt returns the decoded RGBA frame for the given playhead time,
// falling back to the most recent decoded frame when the producer has not
// reached that point yet (§1.10 — stale is honest, never a fake).
//
// The playhead is passed explicitly rather than sampled internally so the
// Gio frame thread never has to take p.mu to read a clock, and so tests
// can drive the clock deterministically.
func (p *Player) FrameAt(elapsed time.Duration) *image.RGBA {
	v := p.v
	if v.Total <= 0 || len(v.frames) == 0 {
		return nil
	}
	p.mu.Lock()
	looping := p.loop
	p.mu.Unlock()

	e := elapsed
	if looping {
		e %= v.Total
	} else if e >= v.Total {
		e = v.Total - time.Nanosecond // clamp to the final frame
	}
	if e < 0 {
		e = 0
	}
	idx := v.frameIndexAt(e)

	p.mu.Lock()
	defer p.mu.Unlock()
	if p.fail != nil || p.stopped {
		return nil
	}
	if !p.started {
		p.startLocked()
	}
	// The playhead wrapped behind the decode frontier and that frame has
	// been evicted: rebuild the pipeline at the first keyframe. Doing it
	// here (instead of eagerly at the producer's end-of-clip) is what
	// stops a looping video from re-decoding the whole clip in a tight
	// loop while nobody is watching it.
	if p.restart == nil && looping && p.next >= v.FrameCount && idx < p.next && p.ring[idx] == nil {
		p.restart = &restartReq{sample: 1, base: 0, at: e}
		p.cond.Broadcast()
	}
	if idx > p.consumed {
		p.consumed = idx
	}
	if !p.keepAll {
		// Sliding window: discard everything the playhead has passed.
		for i := p.oldest; i < idx; i++ {
			delete(p.ring, i)
		}
		if idx > p.oldest {
			p.oldest = idx
		}
	}
	p.cond.Broadcast()

	if img := p.ring[idx]; img != nil {
		return img
	}
	// Not decoded yet: give the playhead the nearest earlier frame rather
	// than a black hole.
	for i := idx - 1; i >= p.oldest; i-- {
		if img := p.ring[i]; img != nil {
			return img
		}
	}
	return nil
}

// NextFrameIn reports how long until the timeline next changes, so the
// Gio loop can schedule the repaint instead of burning a full 60 FPS on a
// static clip (the same contract vp9anim exposes).
func (p *Player) NextFrameIn(elapsed time.Duration) time.Duration {
	v := p.v
	if v.Total <= 0 || len(v.frames) == 0 {
		return time.Second
	}
	p.mu.Lock()
	looping := p.loop
	p.mu.Unlock()

	var e time.Duration
	if looping {
		e = elapsed % v.Total
	} else if elapsed >= v.Total {
		return time.Second // resting on the final frame: nothing further
	} else {
		e = elapsed
	}
	if e < 0 {
		e = 0
	}
	acc := time.Duration(0)
	for i := range v.frames {
		acc += v.frames[i].dur
		if e < acc {
			if rem := acc - e; rem > time.Millisecond {
				return rem
			}
			// Never schedule nearer than a millisecond away — a sub-frame
			// timer would just spin the frame thread.
			return time.Millisecond
		}
	}
	return time.Millisecond
}

// frameIndexAt maps a playhead time onto a display frame index.
func (v *Video) frameIndexAt(e time.Duration) int {
	acc := time.Duration(0)
	for i := range v.frames {
		acc += v.frames[i].dur
		if e < acc {
			return i
		}
	}
	return len(v.frames) - 1
}

// ── session (one sequential decode) ─────────────────────────────────────

// passRunner wraps a packet-pump + codec pair positioned at a keyframe.
type passRunner struct {
	p   *packetSrc
	c   *h264.Codec
	idx int
}

func (v *Video) newPass(startSample uint32, base int) (*passRunner, error) {
	if startSample < 1 {
		startSample = 1
	}
	p := v.packetSrc()
	p.skip(startSample - 1) // metadata-only: zero payload before the keyframe
	return &passRunner{p: p, c: h264.NewCodec(), idx: base}, nil
}

// next decodes the next frame, returning its display index. io.EOF marks
// the end of the clip.
func (pr *passRunner) next() (int, *image.YCbCr, error) {
	for {
		pkt, err := pr.p.next()
		if err == io.EOF {
			// Flush the B-frame reorder buffer before declaring the end.
			if fr := pr.c.Drain(); fr != nil && fr.YCbCr != nil {
				idx := pr.idx
				pr.idx++
				return idx, fr.YCbCr, nil
			}
			return 0, nil, io.EOF
		}
		if err != nil {
			return 0, nil, err
		}
		fr, err := pr.c.Decode(pkt)
		if err != nil {
			return 0, nil, fmt.Errorf("h264: decode: %w", err)
		}
		if fr == nil || fr.YCbCr == nil {
			continue
		}
		idx := pr.idx
		pr.idx++
		return idx, fr.YCbCr, nil
	}
}

func (pr *passRunner) close() {
	pr.p = nil
}
