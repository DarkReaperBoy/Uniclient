// Package vp9anim plays WebM/VP9 video stickers and video custom emoji:
// it demuxes through uniclient/webm, decodes the VP9 Profile 0 bitstream
// with the pure-Go govpx decoder (a byte-for-byte libvpx port verified
// against the official VP9 conformance corpus), pairs the WebM alpha
// side stream where present, converts planar YUV to RGBA with the
// colorimetry signaled in the bitstream, and exposes a looping
// frame-clock API for the GUI.
//
// Decoding runs on a background producer goroutine (the VP9 decode of a
// 512×512 inter frame costs tens of milliseconds — never on the frame
// thread) behind a global semaphore that bounds concurrent decoders, so
// a wall of stickers round-robins the CPU instead of thrashing it.
package vp9anim

import (
	"errors"
	"fmt"
	"image"
	"sync"
	"time"

	"github.com/thesyncim/govpx"

	"uniclient/vcodec"
	"uniclient/webm"
)

// Errors reported by Parse.
var (
	ErrNotVP9Profile0 = errors.New("vp9anim: stream is not VP9 profile 0 (8-bit 4:2:0)")
	ErrNoFrames       = errors.New("vp9anim: document has no decodable frames")
	ErrTooLarge       = errors.New("vp9anim: animation exceeds the size guard")
)

// Size guards: a sticker document larger than this is rejected (a
// malformed/hostile file should never OOM the app).
const (
	maxPixels     = 4096 * 4096
	maxFrames     = 600
	cacheBudget   = 24 << 20 // full-cache byte budget (RGBA frames)
	ringLookahead = 6        // sliding-window decode-ahead
)

// frameSlot is one frame of the parsed animation.
type frameSlot struct {
	payload []byte
	alpha   []byte
	start   time.Duration
	dur     time.Duration
}

// Animation is a parsed, validated WebM/VP9 document ready to play.
type Animation struct {
	Width, Height int
	Total         time.Duration
	fullRange     bool // full-range YUV (else studio/limited range)
	bt709         bool // BT.709 matrix (else BT.601)
	hasAlpha      bool
	keepAll       bool // small enough to cache every decoded frame
	frames        []frameSlot
}

// Parse demuxes and validates a complete WebM document.
func Parse(data []byte) (*Animation, error) {
	doc, err := webm.Parse(data)
	if err != nil {
		return nil, err
	}
	return parseDoc(doc)
}

// parseDoc validates the VP9 stream of a demuxed document and builds the
// frame timeline. Exposed separately so tests can inject alpha-paired
// documents without re-muxing bytes.
func parseDoc(doc *webm.Document) (*Animation, error) {
	if len(doc.Frames) == 0 {
		return nil, ErrNoFrames
	}
	// Sniff the first keyframe header: profile + colorimetry (and an
	// early honest rejection of non-profile-0 streams).
	var sniff *vp9ColorConfig
	for _, f := range doc.Frames {
		if len(f.Payload) == 0 {
			continue
		}
		cc, err := sniffVP9Header(f.Payload)
		if err != nil {
			continue // not a frame start (e.g. lone alt-ref); try the next
		}
		sniff = &cc
		break
	}
	if sniff == nil {
		return nil, ErrNotVP9Profile0
	}
	if sniff.profile != 0 {
		return nil, ErrNotVP9Profile0
	}

	w, h := doc.Track.PixelWidth, doc.Track.PixelHeight
	if w <= 0 || h <= 0 {
		w, h = sniff.width, sniff.height
	}
	if w <= 0 || h <= 0 || w*h > maxPixels {
		return nil, ErrTooLarge
	}
	if len(doc.Frames) > maxFrames {
		return nil, ErrTooLarge
	}

	an := &Animation{
		Width:     w,
		Height:    h,
		fullRange: sniff.fullRange,
		bt709:     sniff.bt709,
	}
	for _, f := range doc.Frames {
		if len(f.Payload) == 0 {
			continue
		}
		slot := frameSlot{
			payload: f.Payload,
			alpha:   f.Alpha,
			start:   time.Duration(f.TimecodeNs),
		}
		if len(f.Alpha) > 0 {
			an.hasAlpha = true
		}
		an.frames = append(an.frames, slot)
	}
	if len(an.frames) == 0 {
		return nil, ErrNoFrames
	}
	an.buildTimeline(time.Duration(doc.DurationNs), time.Duration(doc.Track.DefaultDuration))
	if an.Total <= 0 {
		return nil, ErrNoFrames
	}
	frameBytes := w * h * 4
	an.keepAll = frameBytes*len(an.frames) <= cacheBudget
	return an, nil
}

// FrameCount returns the number of frames.
func (a *Animation) FrameCount() int { return len(a.frames) }

// HasAlpha reports whether the stream carries an alpha side channel.
func (a *Animation) HasAlpha() bool { return a.hasAlpha }

// buildTimeline derives per-frame durations from the presentation
// timecodes: frame i spans [start_i, start_{i+1}); the last frame runs to
// the container duration, else DefaultDuration, else a 40ms fallback.
func (a *Animation) buildTimeline(containerDur, defaultDur time.Duration) {
	for i := range a.frames {
		if i+1 < len(a.frames) {
			a.frames[i].dur = a.frames[i+1].start - a.frames[i].start
		}
	}
	last := &a.frames[len(a.frames)-1]
	if containerDur > last.start {
		last.dur = containerDur - last.start
	} else if defaultDur > 0 {
		last.dur = defaultDur
	} else {
		last.dur = 40 * time.Millisecond
	}
	for i := range a.frames {
		if a.frames[i].dur <= 0 {
			a.frames[i].dur = 40 * time.Millisecond
		}
	}
	total := time.Duration(0)
	for i := range a.frames {
		total += a.frames[i].dur
	}
	a.Total = total
}

// frameIndexAt maps an elapsed play time to the looping frame index.
func (a *Animation) frameIndexAt(elapsed time.Duration) int {
	if len(a.frames) == 0 || a.Total <= 0 {
		return 0
	}
	e := elapsed % a.Total
	if e < 0 {
		e = 0
	}
	// Linear walk with early exit: animations are short and the caller
	// hits this once per painted frame.
	acc := time.Duration(0)
	for i := range a.frames {
		acc += a.frames[i].dur
		if e < acc {
			return i
		}
	}
	return len(a.frames) - 1
}

// ── VP9 header sniffing (color config of the first keyframe) ──────────────

// vp9ColorConfig carries the fields the player needs from the
// uncompressed header of a keyframe.
type vp9ColorConfig struct {
	profile   int
	width     int
	height    int
	fullRange bool
	bt709     bool
}

// sniffVP9Header reads the VP9 uncompressed header prefix of a frame
// payload far enough to learn the profile, dimensions and colorimetry.
// Returns an error for payloads that do not start a frame (bad marker,
// truncated) or do not carry color info (show-existing, inter frames).
func sniffVP9Header(payload []byte) (vp9ColorConfig, error) {
	var cc vp9ColorConfig
	br := &bitReader{data: payload}
	marker, ok := br.bits(2)
	if !ok || marker != 0x2 {
		return cc, errors.New("vp9: bad frame marker")
	}
	lo, _ := br.bit()
	hi, _ := br.bit()
	cc.profile = hi<<1 | lo
	if cc.profile == 3 {
		br.bit() // reserved_zero
	}
	if showExisting, _ := br.bit(); showExisting == 1 {
		return cc, errors.New("vp9: show-existing frame carries no color config")
	}
	frameType, _ := br.bit()
	if frameType != 0 {
		return cc, errors.New("vp9: not a keyframe")
	}
	br.bit() // show_frame
	br.bit() // error_resilient
	// sync code 0x49 0x83 0x42
	var sync [3]byte
	for i := range sync {
		b, ok := br.bits(8)
		if !ok {
			return cc, errors.New("vp9: truncated header")
		}
		sync[i] = byte(b)
	}
	if sync[0] != 0x49 || sync[1] != 0x83 || sync[2] != 0x42 {
		return cc, errors.New("vp9: bad sync code")
	}
	// color config (profile 0: no subsampling / bit-depth extras follow)
	cs, ok := br.bits(3)
	if !ok {
		return cc, errors.New("vp9: truncated color config")
	}
	colorRange := 0
	if cs != 7 {
		colorRange, _ = br.bit()
	}
	// frame size (16+16 bits; the render-size bit is irrelevant here).
	w, ok := br.bits(16)
	if !ok {
		return cc, errors.New("vp9: truncated frame size")
	}
	h, ok := br.bits(16)
	if !ok {
		return cc, errors.New("vp9: truncated frame size")
	}
	cc.width, cc.height = int(w), int(h)
	switch cs {
	case 2, 4, 5: // BT.709, SMPTE-240, BT.2020
		cc.bt709 = true
	}
	cc.fullRange = cs == 7 || colorRange == 1
	return cc, nil
}

// bitReader is an MSB-first bit reader over a byte slice.
type bitReader struct {
	data []byte
	pos  int // bit position
}

func (b *bitReader) bit() (int, bool) {
	if b.pos >= len(b.data)*8 {
		return 0, false
	}
	byteIdx := b.pos / 8
	bitIdx := 7 - uint(b.pos%8)
	v := (b.data[byteIdx] >> bitIdx) & 1
	b.pos++
	return int(v), true
}

func (b *bitReader) bits(n int) (int, bool) {
	v := 0
	for i := 0; i < n; i++ {
		bit, ok := b.bit()
		if !ok {
			return 0, false
		}
		v = v<<1 | bit
	}
	return v, true
}

// ── decode pair (primary + optional alpha stream) ─────────────────────────

// decodePair decodes the primary VP9 stream and, when present, the alpha
// side stream (a second VP9 sequence whose luma plane is the alpha
// channel: 0=transparent, 255=opaque per the WebM alpha spec).
type decodePair struct {
	primary   *govpx.VP9Decoder
	alpha     *govpx.VP9Decoder
	img       govpx.Image
	alphaImg  govpx.Image
	w, h      int
	fullRange bool
	bt709     bool
}

// newDecodePair prepares decoders sized for w×h with the animation's
// colorimetry.
func newDecodePair(w, h int, fullRange, bt709 bool) *decodePair {
	d := &decodePair{w: w, h: h, fullRange: fullRange, bt709: bt709}
	d.primary, _ = govpx.NewVP9Decoder(govpx.VP9DecoderOptions{})
	alloc := func() govpx.Image {
		return govpx.Image{
			Width: w, Height: h,
			YStride: w, UStride: w / 2, VStride: w / 2,
			Y: make([]byte, w*h),
			U: make([]byte, (w/2)*(h/2)),
			V: make([]byte, (w/2)*(h/2)),
		}
	}
	d.img = alloc()
	d.alphaImg = alloc()
	return d
}

// decode decodes one frame payload pair into a fresh RGBA image. Both
// streams must decode sequentially. A broken alpha stream degrades to
// opaque (honest, matches tdesktop's corrupt-side-data behavior). An
// invisible alt-ref returns (nil, nil): the caller holds the previous
// shown frame.
func (d *decodePair) decode(payload, alpha []byte) (*image.RGBA, error) {
	info, err := d.primary.DecodeInto(payload, &d.img)
	if err != nil {
		return nil, fmt.Errorf("vp9 decode: %w", err)
	}
	var alphaPlane *govpx.Image
	if len(alpha) > 0 && d.alpha != nil {
		if _, err := d.alpha.DecodeInto(alpha, &d.alphaImg); err != nil {
			alphaPlane = nil
		} else {
			alphaPlane = &d.alphaImg
		}
	}
	if !info.ShowFrame {
		return nil, nil
	}
	dst := image.NewRGBA(image.Rect(0, 0, d.w, d.h))
	yuvToRGBAExt(&d.img, alphaPlane, dst, d.fullRange, d.bt709)
	return dst, nil
}

// ── YUV → RGBA conversion ─────────────────────────────────────────────────

// yuvToRGBA converts one planar 4:2:0 frame (with strides) to RGBA with
// the BT.601 studio-range matrix. When alpha is non-nil its luma plane
// becomes the RGBA alpha channel.
func yuvToRGBA(src *govpx.Image, alpha *govpx.Image, dst *image.RGBA, fullRange bool) {
	yuvToRGBAExt(src, alpha, dst, fullRange, false)
}

// yuvToRGBAExt is yuvToRGBA with the BT.709 matrix switch.
func yuvToRGBAExt(src *govpx.Image, alpha *govpx.Image, dst *image.RGBA, fullRange, bt709 bool) {
	w := src.Width
	h := src.Height
	if w <= 0 || h <= 0 {
		return
	}
	if dst.Bounds().Dx() < w || dst.Bounds().Dy() < h {
		return
	}
	for row := 0; row < h; row++ {
		yRow := src.Y[row*src.YStride:]
		uRow := src.U[(row/2)*src.UStride:]
		vRow := src.V[(row/2)*src.VStride:]
		var aRow []byte
		if alpha != nil {
			aRow = alpha.Y[row*alpha.YStride:]
		}
		pix := dst.Pix[row*dst.Stride:]
		for col := 0; col < w; col++ {
			y := int(yRow[col])
			u := int(uRow[col/2]) - 128
			v := int(vRow[col/2]) - 128
			var r, g, b int
			if fullRange {
				// JPEG/JFIF full-range matrix (round-half-up).
				r = y + ((91881*v + 32768) >> 16)
				g = y - ((22554*u + 46802*v + 32768) >> 16)
				b = y + ((116130*u + 32768) >> 16)
			} else {
				// Studio range, 1.164 scale in Q14 with round-half-up:
				// Y235 maps to 255 (not 254), Y16 to 0.
				yy := (y-16)*19077 + 8192
				if bt709 {
					r = (yy + 37945*v) >> 14 // 1.793
					g = (yy - 9534*u - 18267*v) >> 14
					b = (yy + 49168*u) >> 14 // 2.112
				} else {
					r = (yy + 52274*v) >> 14 // 1.596
					g = (yy - 13320*u - 32942*v) >> 14
					b = (yy + 66098*u) >> 14 // 2.018
				}
			}
			a := 255
			if aRow != nil {
				a = int(aRow[col])
			}
			pix[col*4+0] = clamp8(r)
			pix[col*4+1] = clamp8(g)
			pix[col*4+2] = clamp8(b)
			pix[col*4+3] = byte(a)
		}
	}
}

func clamp8(v int) byte {
	if v < 0 {
		return 0
	}
	if v > 255 {
		return 255
	}
	return byte(v)
}

// ── player ────────────────────────────────────────────────────────────────

// Decode permits come from vcodec, the app-wide budget shared with
// h264vid — one bounded pool for every video/sticker decoder in the app
// rather than one pool per codec (a VP9 wall plus video bubbles could
// otherwise open 2×NumCPU decoders together). The acquire-before-frame /
// release-after-frame shape is unchanged.
//
// The direction still matters: a counting semaphore whose "acquire" sends
// deadlocks the moment the buffer is full — caught by the multi-player
// regression test, which hangs under the inversion on any machine.

// Player plays one Animation on a background producer.
type Player struct {
	anim *Animation

	mu       sync.Mutex
	cond     *sync.Cond
	ring     map[int]*image.RGBA // decoded frames by index
	oldest   int                 // oldest ring index
	next     int                 // next frame index to decode
	consumed int                 // highest FrameAt-requested index
	fail     error               // permanent decode failure
	stopped  bool
	started  bool

	wg sync.WaitGroup
}

// NewPlayer creates a player for the animation.
func (a *Animation) NewPlayer() *Player {
	p := &Player{anim: a}
	p.cond = sync.NewCond(&p.mu)
	return p
}

// Start launches the background producer.
func (p *Player) Start() {
	p.mu.Lock()
	if p.started || p.stopped {
		p.mu.Unlock()
		return
	}
	p.started = true
	p.mu.Unlock()
	p.wg.Add(1)
	go p.produce()
}

// Stop terminates the producer and frees the frame cache.
func (p *Player) Stop() {
	p.mu.Lock()
	p.stopped = true
	p.cond.Broadcast()
	p.mu.Unlock()
	p.wg.Wait()
}

// DecodedCount reports how many frames the producer has decoded
// (test/progress hook).
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

// produce decodes frames sequentially, staying ahead of the display
// clock by up to ringLookahead frames (or caching everything for small
// animations). Parks on the condition variable while ahead.
func (p *Player) produce() {
	defer p.wg.Done()
	dec := newDecodePair(p.anim.Width, p.anim.Height, p.anim.fullRange, p.anim.bt709)
	for {
		p.mu.Lock()
		for !p.workReady() && !p.stopped {
			p.cond.Wait()
		}
		if p.stopped {
			p.mu.Unlock()
			return
		}
		idx := p.next
		p.mu.Unlock()

		// Decode one frame off the lock, under the global semaphore.
		vcodec.Acquire()
		// A Stop() that landed while we were queued for the permit must
		// not wait for one more decode: check and bail, permit returned.
		p.mu.Lock()
		if p.stopped {
			p.mu.Unlock()
			vcodec.Release()
			return
		}
		p.mu.Unlock()
		frame := p.anim.frames[idx]
		img, err := dec.decode(frame.payload, frame.alpha)
		vcodec.Release()

		p.mu.Lock()
		if err != nil {
			// A corrupt frame is terminal for the sequential stream.
			p.fail = err
			p.stopped = true
			p.cond.Broadcast()
			p.mu.Unlock()
			return
		}
		if img != nil {
			if p.ring == nil {
				p.ring = make(map[int]*image.RGBA)
			}
			p.ring[idx] = img
		}
		p.next = idx + 1
		p.cond.Broadcast()
		p.mu.Unlock()
	}
}

// workReady reports whether the producer should decode the next frame.
// Called with p.mu held.
func (p *Player) workReady() bool {
	if p.next >= len(p.anim.frames) {
		return false // wrapped: wait for the display clock to reset us
	}
	if p.anim.keepAll {
		return p.ring[p.next] == nil
	}
	// Stay ahead of consumption by ringLookahead.
	return p.next <= p.consumed+ringLookahead
}

// NextFrameIn returns how long until the next frame boundary after the
// given elapsed time (repaint-scheduling helper; floored at 1ms).
func (p *Player) NextFrameIn(elapsed time.Duration) time.Duration {
	a := p.anim
	if a == nil || a.Total <= 0 || len(a.frames) == 0 {
		return time.Second
	}
	e := elapsed % a.Total
	if e < 0 {
		e = 0
	}
	acc := time.Duration(0)
	for i := range a.frames {
		acc += a.frames[i].dur
		if e < acc {
			if rem := acc - e; rem > 0 {
				return rem
			}
			return time.Millisecond
		}
	}
	return time.Millisecond
}

// FrameAt returns the frame for an elapsed play time (looping), or nil
// while the producer has not decoded that far yet. The caller repaints
// on its own clock; nil means "hold the last drawn frame / placeholder".
func (p *Player) FrameAt(elapsed time.Duration) *image.RGBA {
	idx := p.anim.frameIndexAt(elapsed)
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.fail != nil {
		return nil
	}
	if p.stopped {
		return nil
	}
	if !p.started {
		p.started = true
		p.wg.Add(1)
		go p.produce()
	}
	// Loop wrap (or eviction) below the decode frontier: restart the
	// pipeline from frame 0 (VP9 inter frames need sequential decode).
	if p.ring[idx] == nil && idx < p.next {
		p.ring = make(map[int]*image.RGBA)
		p.oldest, p.next = 0, 0
	}
	if idx > p.consumed {
		p.consumed = idx
	}
	// Evict behind the display position (sliding-window mode).
	if !p.anim.keepAll {
		for i := p.oldest; i < idx; i++ {
			delete(p.ring, i)
		}
	}
	if p.oldest < idx {
		p.oldest = idx
	}
	p.cond.Broadcast()
	// Best available frame at or before idx.
	if img := p.ring[idx]; img != nil {
		return img
	}
	for i := idx; i >= p.oldest; i-- {
		if img := p.ring[i]; img != nil {
			return img
		}
	}
	return nil
}
