package voice

import (
	"fmt"
	"sync"
	"time"

	"github.com/pion/opus"
)

const (
	SampleRate       = 48000
	Channels         = 1
	FrameSamples     = 960
	FrameBytes       = 1920
	MaxFrameMilli    = 120
	MaxDecodeSamples = 5760
)

const FrameDuration = 20 * time.Millisecond

type Encoder struct {
	enc     *opus.Encoder
	bitrate int
	out     []byte
}

func NewEncoder(bitrate int) (*Encoder, error) {
	if bitrate < 6000 {
		bitrate = 6000
	}
	if bitrate > 510000 {
		bitrate = 510000
	}
	enc, err := opus.NewEncoder(
		opus.WithSampleRate(SampleRate),
		opus.WithChannels(Channels),
		opus.WithBitrate(bitrate),
		opus.WithApplication(opus.ApplicationVoIP),
		opus.WithVBR(true),
	)
	if err != nil {
		return nil, fmt.Errorf("voice: opus encoder: %w", err)
	}
	return &Encoder{enc: enc, bitrate: bitrate, out: make([]byte, 1276)}, nil
}

func (e *Encoder) Encode(pcm []byte) ([]byte, error) {
	n, err := e.enc.Encode(pcm, e.out)
	if err != nil {
		return nil, fmt.Errorf("voice: opus encode: %w", err)
	}
	return e.out[:n], nil
}

func (e *Encoder) Bitrate() int {
	if e == nil {
		return 0
	}
	return e.bitrate
}

type Decoder struct {
	dec opus.Decoder
	pcm []int16
}

func NewDecoder() *Decoder {
	d, err := opus.NewDecoderWithOutput(SampleRate, Channels)
	if err != nil {
		return &Decoder{}
	}
	return &Decoder{dec: d, pcm: make([]int16, MaxDecodeSamples)}
}

func (d *Decoder) Decode(packet []byte) ([]int16, error) {
	if len(packet) == 0 {
		return nil, fmt.Errorf("voice: empty packet")
	}
	n, err := d.dec.DecodeToInt16(packet, d.pcm)
	if err != nil {
		return nil, fmt.Errorf("voice: opus decode: %w", err)
	}
	return d.pcm[:n], nil
}

type mixerSrc struct {
	buf   []int16
	vol   float64
	level float64
}

const mixerBufFrames = 8

type Mixer struct {
	mu   sync.Mutex
	srcs map[string]*mixerSrc
}

func NewMixer() *Mixer {
	return &Mixer{srcs: make(map[string]*mixerSrc)}
}

func (m *Mixer) SetVolume(id string, vol float64) {
	if vol < 0 {
		vol = 0
	}
	if vol > 1 {
		vol = 1
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	s := m.srcs[id]
	if s == nil {
		s = &mixerSrc{vol: vol}
		m.srcs[id] = s
		return
	}
	s.vol = vol
}

func (m *Mixer) Push(id string, samples []int16) {
	if len(samples) == 0 {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	s := m.srcs[id]
	if s == nil {
		s = &mixerSrc{vol: 1}
		m.srcs[id] = s
	}
	s.buf = append(s.buf, samples...)
	var acc float64
	for _, v := range samples {
		f := float64(v) / 32768
		acc += f * f
	}
	rms := acc / float64(len(samples))
	s.level = s.level*0.6 + 0.4*rms
	if cap := mixerBufFrames * FrameSamples; len(s.buf) > cap {
		s.buf = append(s.buf[:0], s.buf[len(s.buf)-cap:]...)
	}
}

func (m *Mixer) Remove(id string) {
	m.mu.Lock()
	delete(m.srcs, id)
	m.mu.Unlock()
}

func (m *Mixer) Sources() []string {
	m.mu.Lock()
	defer m.mu.Unlock()
	ids := make([]string, 0, len(m.srcs))
	for id := range m.srcs {
		ids = append(ids, id)
	}
	return ids
}

func (m *Mixer) Levels() map[string]float64 {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make(map[string]float64, len(m.srcs))
	for id, s := range m.srcs {
		out[id] = s.level
	}
	return out
}

func (m *Mixer) Mix(out []int16) {
	m.mu.Lock()
	defer m.mu.Unlock()

	for i := range out {
		out[i] = 0
	}
	n := len(out)
	for _, s := range m.srcs {
		take := len(s.buf)
		if take > n {
			take = n
		}
		for i := 0; i < take; i++ {
			v := float64(s.buf[i]) * s.vol
			acc := float64(out[i]) + v
			if acc > 32767 {
				acc = 32767
			} else if acc < -32768 {
				acc = -32768
			}
			out[i] = int16(acc)
		}
		s.buf = s.buf[take:]
		s.level *= 0.85
		if s.level < 0.0005 {
			s.level = 0
		}
	}
}

func PCMBytesToSamples(pcm []byte) []int16 {
	n := len(pcm) / 2
	out := make([]int16, n)
	for i := 0; i < n; i++ {
		out[i] = int16(uint16(pcm[2*i]) | uint16(pcm[2*i+1])<<8)
	}
	return out
}

func SamplesToPCMBytes(samples []int16) []byte {
	out := make([]byte, len(samples)*2)
	for i, s := range samples {
		out[2*i] = byte(s)
		out[2*i+1] = byte(s >> 8)
	}
	return out
}
