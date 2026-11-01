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

var (
	ErrNotVP9Profile0 = errors.New("vp9anim: stream is not VP9 profile 0 (8-bit 4:2:0)")
	ErrNoFrames       = errors.New("vp9anim: document has no decodable frames")
	ErrTooLarge       = errors.New("vp9anim: animation exceeds the size guard")
)

const (
	maxPixels     = 4096 * 4096
	maxFrames     = 600
	cacheBudget   = 24 << 20
	ringLookahead = 6
)

type frameSlot struct {
	payload []byte
	alpha   []byte
	start   time.Duration
	dur     time.Duration
}

type Animation struct {
	Width, Height int
	Total         time.Duration
	fullRange     bool
	bt709         bool
	hasAlpha      bool
	keepAll       bool
	frames        []frameSlot
}

func Parse(data []byte) (*Animation, error) {
	doc, err := webm.Parse(data)
	if err != nil {
		return nil, err
	}
	return parseDoc(doc)
}

func parseDoc(doc *webm.Document) (*Animation, error) {
	if len(doc.Frames) == 0 {
		return nil, ErrNoFrames
	}
	var sniff *vp9ColorConfig
	for _, f := range doc.Frames {
		if len(f.Payload) == 0 {
			continue
		}
		cc, err := sniffVP9Header(f.Payload)
		if err != nil {
			continue
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

func (a *Animation) FrameCount() int { return len(a.frames) }

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

func (a *Animation) frameIndexAt(elapsed time.Duration) int {
	if len(a.frames) == 0 || a.Total <= 0 {
		return 0
	}
	e := elapsed % a.Total
	if e < 0 {
		e = 0
	}
	acc := time.Duration(0)
	for i := range a.frames {
		acc += a.frames[i].dur
		if e < acc {
			return i
		}
	}
	return len(a.frames) - 1
}

type vp9ColorConfig struct {
	profile   int
	width     int
	height    int
	fullRange bool
	bt709     bool
}

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
		br.bit()
	}
	if showExisting, _ := br.bit(); showExisting == 1 {
		return cc, errors.New("vp9: show-existing frame carries no color config")
	}
	frameType, _ := br.bit()
	if frameType != 0 {
		return cc, errors.New("vp9: not a keyframe")
	}
	br.bit()
	br.bit()
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
	cs, ok := br.bits(3)
	if !ok {
		return cc, errors.New("vp9: truncated color config")
	}
	colorRange := 0
	if cs != 7 {
		var ok bool
		colorRange, ok = br.bit()
		if !ok {
			return cc, errors.New("vp9: truncated color config")
		}
	}
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
	case 2, 4, 5:
		cc.bt709 = true
	}
	cc.fullRange = cs == 7 || colorRange == 1
	return cc, nil
}

type bitReader struct {
	data []byte
	pos  int
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

type decodePair struct {
	primary   *govpx.VP9Decoder
	alpha     *govpx.VP9Decoder
	img       govpx.Image
	alphaImg  govpx.Image
	w, h      int
	fullRange bool
	bt709     bool
}

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

func yuvToRGBA(src *govpx.Image, alpha *govpx.Image, dst *image.RGBA, fullRange bool) {
	yuvToRGBAExt(src, alpha, dst, fullRange, false)
}

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
				r = y + ((91881*v + 32768) >> 16)
				g = y - ((22554*u + 46802*v + 32768) >> 16)
				b = y + ((116130*u + 32768) >> 16)
			} else {
				yy := (y-16)*19077 + 8192
				if bt709 {
					r = (yy + 37945*v) >> 14
					g = (yy - 9534*u - 18267*v) >> 14
					b = (yy + 49168*u) >> 14
				} else {
					r = (yy + 52274*v) >> 14
					g = (yy - 13320*u - 32942*v) >> 14
					b = (yy + 66098*u) >> 14
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

type Player struct {
	anim *Animation

	mu       sync.Mutex
	cond     *sync.Cond
	ring     map[int]*image.RGBA
	oldest   int
	next     int
	consumed int
	fail     error
	stopped  bool
	started  bool

	wg sync.WaitGroup
}

func (a *Animation) NewPlayer() *Player {
	p := &Player{anim: a}
	p.cond = sync.NewCond(&p.mu)
	return p
}

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

func (p *Player) Stop() {
	p.mu.Lock()
	p.stopped = true
	p.cond.Broadcast()
	p.mu.Unlock()
	p.wg.Wait()
}

func (p *Player) DecodedCount() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.next
}

func (p *Player) Failed() error {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.fail
}

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

		vcodec.Acquire()
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

func (p *Player) workReady() bool {
	if p.next >= len(p.anim.frames) {
		return false
	}
	if p.anim.keepAll {
		return p.ring[p.next] == nil
	}
	return p.next <= p.consumed+ringLookahead
}

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
	if p.ring[idx] == nil && idx < p.next {
		p.ring = make(map[int]*image.RGBA)
		p.oldest, p.next = 0, 0
	}
	if idx > p.consumed {
		p.consumed = idx
	}
	if !p.anim.keepAll {
		for i := p.oldest; i < idx; i++ {
			delete(p.ring, i)
		}
	}
	if p.oldest < idx {
		p.oldest = idx
	}
	p.cond.Broadcast()
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
