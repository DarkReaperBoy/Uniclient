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

var (
	ErrNotVideo     = errors.New("h264vid: not an H.264 MP4")
	ErrUnsupported  = errors.New("h264vid: unsupported video codec")
	ErrTooLarge     = errors.New("h264vid: video exceeds size guard")
	ErrDecodeFailed = errors.New("h264vid: container decode failed")
)

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
	maxPixels     = 4096 * 4096
	maxFrames     = 6000
	ringBudget    = 48 << 20
	ringLookahead = 6

	defaultFrameDur = 40 * time.Millisecond
)

type timing struct {
	pts time.Duration
	dur time.Duration
}

type syncEntry struct {
	pts    time.Duration
	sample uint32
	index  int
}

type Video struct {
	Width, Height int
	Total         time.Duration
	FrameCount    int

	ra      io.ReaderAt
	moov    *moovInfo
	frames  []timing
	syncs   []syncEntry
	keepAll bool
}

type indexSample struct {
	pts    time.Duration
	sync   bool
	decode uint32
}

func Parse(data []byte) (*Video, error) {
	if len(data) == 0 {
		return nil, ErrNotVideo
	}
	return parseSource(bytes.NewReader(data))
}

func (v *Video) finishTimeline(order []indexSample, container time.Duration) error {
	if len(order) == 0 {
		return fmt.Errorf("%w: no samples", ErrNotVideo)
	}
	if len(order) > maxFrames {
		return fmt.Errorf("%w: %d frames > %d", ErrTooLarge, len(order), maxFrames)
	}
	v.FrameCount = len(order)

	rank := make([]int, len(order))
	sorted := make([]indexSample, len(order))
	copy(sorted, order)
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
	if len(v.syncs) == 0 {
		return fmt.Errorf("%w: no keyframes", ErrNotVideo)
	}

	v.keepAll = int64(v.FrameCount)*int64(v.Width*v.Height*4) <= ringBudget
	return nil
}

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

func (v *Video) validateDims() error {
	if v.Width <= 0 || v.Height <= 0 {
		return fmt.Errorf("%w: bad dimensions %dx%d", ErrNotVideo, v.Width, v.Height)
	}
	if v.Width*v.Height > maxPixels {
		return fmt.Errorf("%w: %dx%d exceeds %d pixels", ErrTooLarge, v.Width, v.Height, maxPixels)
	}
	return nil
}

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

func (v *Video) decodePass(startSample uint32, base int, fn func(idx int, img *image.YCbCr) error) error {
	if startSample < 1 {
		startSample = 1
	}
	p := v.packetSrc()
	p.skip(startSample - 1)

	c := h264.NewCodec()
	idx := base
	emit := func(y *image.YCbCr) error {
		if y == nil {
			return nil
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

type restartReq struct {
	sample uint32
	base   int
	at     time.Duration
}

type ringFrame = image.RGBA

type Player struct {
	v *Video

	mu       sync.Mutex
	cond     *sync.Cond
	ring     map[int]*ringFrame
	oldest   int
	next     int
	consumed int
	fail     error
	stopped  bool
	started  bool
	loop     bool
	restart  *restartReq
	keepAll  bool

	playing  bool
	start    time.Time
	pausePos time.Duration

	wg sync.WaitGroup
}

func (v *Video) NewPlayer() *Player {
	p := &Player{
		v:       v,
		ring:    make(map[int]*ringFrame),
		keepAll: v.keepAll,
		oldest:  0,
		next:    0,
	}
	p.cond = sync.NewCond(&p.mu)
	return p
}

func (p *Player) SetLoop(v bool) {
	p.mu.Lock()
	p.loop = v
	p.cond.Broadcast()
	p.mu.Unlock()
}

func (p *Player) Start() {
	p.mu.Lock()
	p.startLocked()
	p.mu.Unlock()
}

func (p *Player) startLocked() {
	if p.started || p.stopped {
		return
	}
	p.started = true
	if !p.playing && p.pausePos == 0 {
		p.playing = true
		p.start = time.Now()
	}
	p.wg.Add(1)
	go p.produce()
}

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

func (p *Player) Play() {
	p.mu.Lock()
	if !p.playing {
		p.playing = true
		p.start = time.Now().Add(-p.pausePos)
		p.cond.Broadcast()
	}
	p.mu.Unlock()
}

func (p *Player) Pause() {
	p.mu.Lock()
	if p.playing {
		p.pausePos = time.Since(p.start)
		p.playing = false
		p.cond.Broadcast()
	}
	p.mu.Unlock()
}

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

func (p *Player) Playing() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.playing
}

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

func (p *Player) Duration() time.Duration { return p.v.Total }

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
	if _, ok := p.ring[s.index]; !ok || s.index > p.next || s.index < p.oldest {
		p.restart = &restartReq{sample: s.sample, base: s.index, at: t}
	}
	p.cond.Broadcast()
	p.mu.Unlock()
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

func (p *Player) frameAtIndex(i int) *image.RGBA {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.ring[i]
}

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

		vcodec.Acquire()
		p.mu.Lock()
		if p.stopped || p.restart != nil || p.next != want {
			p.mu.Unlock()
			vcodec.Release()
			continue
		}
		p.mu.Unlock()

		idx, yuv, err := pass.next()
		vcodec.Release()

		if err == io.EOF {
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
			continue
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

func (p *Player) workReadyLocked() bool {
	if p.next >= p.v.FrameCount {
		return false
	}
	if p.keepAll {
		return p.ring[p.next] == nil
	}
	return p.next <= p.consumed+ringLookahead
}

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
		e = v.Total - time.Nanosecond
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
	if p.restart == nil && looping && p.next >= v.FrameCount && idx < p.next && p.ring[idx] == nil {
		p.restart = &restartReq{sample: 1, base: 0, at: e}
		p.cond.Broadcast()
	}
	if idx > p.consumed {
		p.consumed = idx
	}
	if !p.keepAll {
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
	for i := idx - 1; i >= p.oldest; i-- {
		if img := p.ring[i]; img != nil {
			return img
		}
	}
	return nil
}

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
		return time.Second
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
			return time.Millisecond
		}
	}
	return time.Millisecond
}

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
	p.skip(startSample - 1)
	return &passRunner{p: p, c: h264.NewCodec(), idx: base}, nil
}

func (pr *passRunner) next() (int, *image.YCbCr, error) {
	for {
		pkt, err := pr.p.next()
		if err == io.EOF {
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
