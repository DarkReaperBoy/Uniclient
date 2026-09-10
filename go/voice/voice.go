// Package voice provides the shared audio engine for voice-capable
// backends (Mumble, TeamSpeak, later group calls): a pure-Go Opus
// codec wrapper (github.com/pion/opus) and a per-sender mixing layer
// that turns N decoded remote streams into one output stream for the
// speaker device.
//
// All audio in Uniclient is mono 48 kHz with 20 ms frames — the native
// Opus interaction mode and the frame size both Mumble and TeamSpeak
// voice run at.
package voice

import (
	"fmt"
	"sync"
	"time"

	"github.com/pion/opus"
)

// Audio format constants: mono 48 kHz, 20 ms frames.
const (
	SampleRate    = 48000
	Channels      = 1
	FrameSamples  = 960  // 20 ms at 48 kHz
	FrameBytes    = 1920 // 960 s16le samples
	MaxFrameMilli = 120  // longest legal Opus frame
	// MaxDecodeSamples is the largest frame a decoder may return
	// (120 ms at 48 kHz).
	MaxDecodeSamples = 5760
)

// FrameDuration is the wall-clock length of one audio frame.
const FrameDuration = 20 * time.Millisecond

// Encoder wraps a pion Opus encoder tuned for VoIP: mono 48 kHz,
// VBR at the requested bitrate.
type Encoder struct {
	enc     *opus.Encoder
	bitrate int
	out     []byte
}

// NewEncoder creates a VoIP encoder. bitrate is in bits/s; values are
// clamped to Opus' legal range (6k..510k). 24000 is the Mumble default.
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

// Encode compresses exactly one 20 ms mono 48 kHz s16le frame
// (FrameBytes bytes) into one Opus packet. The returned slice is valid
// until the next Encode call on the same encoder.
func (e *Encoder) Encode(pcm []byte) ([]byte, error) {
	n, err := e.enc.Encode(pcm, e.out)
	if err != nil {
		return nil, fmt.Errorf("voice: opus encode: %w", err)
	}
	return e.out[:n], nil
}

// Bitrate returns the encoder's configured bitrate (bits/s).
func (e *Encoder) Bitrate() int {
	if e == nil {
		return 0
	}
	return e.bitrate
}

// Decoder wraps a pion Opus decoder for one remote sender. Decoders
// are per-sender because Opus state (mode, band tracking) is
// stream-specific.
type Decoder struct {
	dec opus.Decoder
	pcm []int16
}

// NewDecoder creates a mono 48 kHz Opus decoder.
func NewDecoder() *Decoder {
	d, err := opus.NewDecoderWithOutput(SampleRate, Channels)
	if err != nil {
		// NewDecoderWithOutput only errors on illegal rate/channels —
		// both constants here, so this cannot fire; keep it honest
		// anyway.
		return &Decoder{}
	}
	return &Decoder{dec: d, pcm: make([]int16, MaxDecodeSamples)}
}

// Decode expands one Opus packet into s16 samples (0..5760). The
// returned slice is valid until the next Decode call.
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

// mixerSrc is one remote speaker's state inside the Mixer.
type mixerSrc struct {
	buf   []int16 // pending samples, head at buf[0]
	vol   float64
	level float64 // smoothed RMS level, 0..1
}

// mixerBufFrames caps how many frames a source may bank up before the
// oldest audio is dropped (network burst absorption).
const mixerBufFrames = 8

// Mixer mixes per-sender decoded PCM into one pull-mode output stream
// and tracks per-sender levels for speaking indicators.
//
// Push happens whenever a voice packet is decoded; Mix happens on the
// playback device's clock (every 20 ms). Sources that have nothing
// buffered contribute silence — their stream simply has a gap, which
// is the honest behavior for lost packets.
type Mixer struct {
	mu   sync.Mutex
	srcs map[string]*mixerSrc
}

// NewMixer creates an empty mixer.
func NewMixer() *Mixer {
	return &Mixer{srcs: make(map[string]*mixerSrc)}
}

// SetVolume sets a source's volume 0..1 (values clamp). Creating the
// source if needed so volume can be set before audio arrives.
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

// Push appends decoded samples from a source. Audio beyond the buffer
// cap drops the oldest samples (never grows unbounded).
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
	// Level: RMS of this push, smoothed with the previous estimate.
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

// Remove drops a source and its buffered audio.
func (m *Mixer) Remove(id string) {
	m.mu.Lock()
	delete(m.srcs, id)
	m.mu.Unlock()
}

// Sources returns the ids of all known sources.
func (m *Mixer) Sources() []string {
	m.mu.Lock()
	defer m.mu.Unlock()
	ids := make([]string, 0, len(m.srcs))
	for id := range m.srcs {
		ids = append(ids, id)
	}
	return ids
}

// Levels returns the recent activity level (smoothed RMS, 0..1) per
// source. Speaking indicators threshold around 0.01.
func (m *Mixer) Levels() map[string]float64 {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make(map[string]float64, len(m.srcs))
	for id, s := range m.srcs {
		out[id] = s.level
	}
	return out
}

// Mix fills out (any length) with the volume-scaled sum of every
// source's pending samples. Sources with fewer buffered samples than
// requested contribute what they have; the remainder is silence.
// Mix also decays levels so indicators go quiet when audio stops.
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
			// Mix in float and clamp once into the accumulator.
			acc := float64(out[i]) + v
			if acc > 32767 {
				acc = 32767
			} else if acc < -32768 {
				acc = -32768
			}
			out[i] = int16(acc)
		}
		s.buf = s.buf[take:] // cheap: reslice, reallocate on next Push
		// Level decay so indicators fade after speech stops.
		s.level *= 0.85
		if s.level < 0.0005 {
			s.level = 0
		}
	}
}

// PCMBytesToSamples converts s16le bytes to samples (no allocation
// beyond the slice header when the input is full frames).
func PCMBytesToSamples(pcm []byte) []int16 {
	n := len(pcm) / 2
	out := make([]int16, n)
	for i := 0; i < n; i++ {
		out[i] = int16(uint16(pcm[2*i]) | uint16(pcm[2*i+1])<<8)
	}
	return out
}

// SamplesToPCMBytes converts samples to s16le bytes.
func SamplesToPCMBytes(samples []int16) []byte {
	out := make([]byte, len(samples)*2)
	for i, s := range samples {
		out[2*i] = byte(s)
		out[2*i+1] = byte(s >> 8)
	}
	return out
}
