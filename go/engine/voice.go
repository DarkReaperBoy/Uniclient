// engine/voice.go — the shared audio pipeline for live-voice backends
// (Mumble, TeamSpeak). The engine owns the mic → Opus → core and
// core → decode → mix → speaker loops; the cores only speak their wire
// protocol through cores.VoiceCore.
package engine

import (
	"sync"
	"sync/atomic"
	"time"

	"uniclient/audio"
	"uniclient/cores"
	"uniclient/voice"
)

// voiceVADThreshold is the RMS gate for "this frame carries speech".
// Mumble's own client uses a comparable default for activity VAD.
const voiceVADThreshold = 0.004

// voiceHangoverFrames: how many quiet frames still transmit after the
// last voiced one (avoids chopping word tails).
const voiceHangoverFrames = 5

// voiceVAD is the per-stream activity gate.
type voiceVAD struct {
	wasVoiced  bool // a voiced frame was sent recently
	hangover   int  // quiet frames still allowed to send
	terminator bool // speech stopped: one end-of-stream marker owed
}

// gate reports whether this frame should be transmitted.
func (v *voiceVAD) gate(frame []byte) bool {
	voiced := frameRMS(frame) > voiceVADThreshold
	switch {
	case voiced:
		v.wasVoiced = true
		v.hangover = voiceHangoverFrames
		v.terminator = false
		return true
	case v.hangover > 0:
		v.hangover--
		return true
	default:
		if v.wasVoiced {
			v.wasVoiced = false
			v.terminator = true // owed exactly once, on the next poll
		}
		return false
	}
}

// needTerminator consumes the end-of-stream marker obligation.
func (v *voiceVAD) needTerminator() bool {
	if v.terminator {
		v.terminator = false
		return true
	}
	return false
}

// frameRMS returns the root-mean-square amplitude of an s16le frame.
func frameRMS(frame []byte) float64 {
	if len(frame) < 2 {
		return 0
	}
	n := len(frame) / 2
	var acc float64
	for i := 0; i < n; i++ {
		s := float64(int16(uint16(frame[2*i])|uint16(frame[2*i+1])<<8)) / 32768
		acc += s * s
	}
	return sqrt(acc / float64(n))
}

func sqrt(x float64) float64 {
	if x <= 0 {
		return 0
	}
	// Newton-Raphson from a float64 seed — good enough for a gate.
	g := x
	for i := 0; i < 24; i++ {
		g = (g + x/g) / 2
	}
	return g
}

// voiceTerminator is implemented by cores whose protocol has an
// end-of-transmission marker (Mumble).
type voiceTerminator interface {
	SendVoiceTerminator() error
}

// voiceRunner drives one account's live voice session.
type voiceRunner struct {
	eng       *Engine
	accountID string
	core      cores.VoiceCore

	stop     chan struct{}
	wg       sync.WaitGroup
	muted    atomic.Bool
	audioErr error // why the device layer is unavailable (nil = live)

	enc   *voice.Encoder
	mix   *voice.Mixer
	decMu sync.Mutex
	dec   map[string]*voice.Decoder

	lastSeenMu sync.Mutex
	lastSeen   map[string]time.Time
}

// startVoiceRunner wires the audio pipeline for a voice-capable core.
// The engine's single audio session is opened lazily and shared.
func (e *Engine) startVoiceRunner(accountID string, core cores.VoiceCore) *voiceRunner {
	e.voiceMu.Lock()
	defer e.voiceMu.Unlock()

	// One live runner at a time (the GUI tracks one joined call).
	if e.voiceRun != nil {
		e.voiceRun.stopInternal()
	}

	r := &voiceRunner{
		eng:       e,
		accountID: accountID,
		core:      core,
		stop:      make(chan struct{}),
		dec:       make(map[string]*voice.Decoder),
		lastSeen:  make(map[string]time.Time),
	}
	r.mix = voice.NewMixer()

	enc, err := voice.NewEncoder(24000)
	if err != nil {
		r.audioErr = err
	} else {
		r.enc = enc
	}

	// Device layer: shared, opened once per engine.
	if e.audioSession == nil {
		if sess, err := audio.Open(); err != nil {
			r.audioErr = err
		} else {
			e.audioSession = sess
		}
	}

	// Remote voice → decode → mix.
	core.OnVoiceFrame(func(sender string, opusData []byte) {
		r.onRemoteVoice(sender, opusData)
	})

	if e.audioSession != nil && r.enc != nil {
		// Mic → encode → core (VAD-gated).
		frames, err := e.audioSession.StartMic()
		if err != nil {
			r.audioErr = err
		} else {
			r.wg.Add(1)
			go r.micLoop(frames)
		}
		// Mixer → speaker.
		if err := e.audioSession.StartPlayback(func(out []int16) {
			r.mix.Mix(out)
		}); err != nil {
			r.audioErr = err
		}
	}

	// Stale-sender janitor: forget decoders/mix sources of users who
	// left the room.
	r.wg.Add(1)
	go r.janitorLoop()

	e.voiceRun = r
	return r
}

// stopVoiceRunner tears down the live voice pipeline (nil-safe).
func (e *Engine) stopVoiceRunner() {
	e.voiceMu.Lock()
	r := e.voiceRun
	e.voiceRun = nil
	e.voiceMu.Unlock()
	if r != nil {
		r.stopInternal()
	}
}

// setVoiceMuted flips the mic gate and mirrors it server-side.
func (e *Engine) setVoiceMuted(muted bool) {
	e.voiceMu.Lock()
	r := e.voiceRun
	e.voiceMu.Unlock()
	if r == nil {
		return
	}
	r.muted.Store(muted)
	_ = r.core.SetVoiceMuted(muted)
}

// stopInternal is the unsynchronized teardown.
func (r *voiceRunner) stopInternal() {
	select {
	case <-r.stop:
		return // already stopped
	default:
	}
	close(r.stop)
	if r.eng.audioSession != nil {
		r.eng.audioSession.StopMic()
		r.eng.audioSession.StopPlayback()
	}
	// Drop the core's voice handler so late packets stop decoding.
	r.core.OnVoiceFrame(func(string, []byte) {})
}

// micLoop reads 20 ms frames from the capture channel and ships them
// through the Opus encoder to the core. Muted frames are drained and
// dropped locally.
func (r *voiceRunner) micLoop(frames <-chan []byte) {
	defer r.wg.Done()
	var vad voiceVAD
	for {
		select {
		case <-r.stop:
			return
		case f, ok := <-frames:
			if !ok {
				return
			}
			if r.muted.Load() {
				continue
			}
			if !vad.gate(f) {
				if vad.needTerminator() {
					if term, ok := r.core.(voiceTerminator); ok {
						_ = term.SendVoiceTerminator()
					}
				}
				continue
			}
			pkt, err := r.enc.Encode(f)
			if err != nil {
				continue // malformed frame length — skip it
			}
			if err := r.core.SendVoiceFrame(pkt); err != nil {
				// One failed frame is a blip (UDP write hiccup); the room
				// stays live and the next frame retries. Only a dead stop
				// channel ends the loop.
				continue
			}
		}
	}
}

// onRemoteVoice decodes one Opus packet from a sender into the mixer.
func (r *voiceRunner) onRemoteVoice(sender string, opusData []byte) {
	select {
	case <-r.stop:
		return
	default:
	}
	r.decMu.Lock()
	d := r.dec[sender]
	if d == nil {
		d = voice.NewDecoder()
		r.dec[sender] = d
	}
	r.decMu.Unlock()
	samples, err := d.Decode(opusData)
	if err != nil {
		return // corrupt packet: silence is the honest fallback
	}
	r.mix.Push(sender, samples)
	r.lastSeenMu.Lock()
	r.lastSeen[sender] = time.Now()
	r.lastSeenMu.Unlock()
}

// janitorLoop forgets senders that have been silent past the deadline
// (they left the room; their mixer source would otherwise contribute
// gaps forever).
func (r *voiceRunner) janitorLoop() {
	defer r.wg.Done()
	t := time.NewTicker(10 * time.Second)
	defer t.Stop()
	const stale = 60 * time.Second
	for {
		select {
		case <-r.stop:
			return
		case now := <-t.C:
			r.lastSeenMu.Lock()
			for id, seen := range r.lastSeen {
				if now.Sub(seen) > stale {
					delete(r.lastSeen, id)
					r.mix.Remove(id)
					r.decMu.Lock()
					delete(r.dec, id)
					r.decMu.Unlock()
				}
			}
			r.lastSeenMu.Unlock()
		}
	}
}

// AudioDeviceError explains why the mic/speaker path is unavailable
// (Android today; devices missing; PulseAudio down). Callers surface
// it honestly instead of pretending voice works.
func (e *Engine) AudioDeviceError() error {
	e.voiceMu.Lock()
	defer e.voiceMu.Unlock()
	if e.voiceRun == nil {
		return nil // not in a voice session
	}
	return e.voiceRun.audioErr
}

// VoiceActive reports whether a voice session is live.
func (e *Engine) VoiceActive() bool {
	e.voiceMu.Lock()
	defer e.voiceMu.Unlock()
	return e.voiceRun != nil
}
