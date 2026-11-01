package engine

import (
	"sync"
	"sync/atomic"
	"time"

	"uniclient/audio"
	"uniclient/cores"
	"uniclient/voice"
)

const voiceVADThreshold = 0.004

const voiceHangoverFrames = 5

type voiceVAD struct {
	wasVoiced  bool
	hangover   int
	terminator bool
}

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
			v.terminator = true
		}
		return false
	}
}

func (v *voiceVAD) needTerminator() bool {
	if v.terminator {
		v.terminator = false
		return true
	}
	return false
}

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
	g := x
	for i := 0; i < 24; i++ {
		g = (g + x/g) / 2
	}
	return g
}

type voiceTerminator interface {
	SendVoiceTerminator() error
}

type voiceRunner struct {
	eng       *Engine
	accountID string
	core      cores.VoiceCore

	stop     chan struct{}
	wg       sync.WaitGroup
	muted    atomic.Bool
	audioErr error

	enc   *voice.Encoder
	mix   *voice.Mixer
	decMu sync.Mutex
	dec   map[string]*voice.Decoder

	lastSeenMu sync.Mutex
	lastSeen   map[string]time.Time
}

func (e *Engine) startVoiceRunner(accountID string, core cores.VoiceCore) *voiceRunner {
	e.voiceMu.Lock()
	defer e.voiceMu.Unlock()

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

	if e.audioSession == nil {
		if sess, err := audio.Open(); err != nil {
			r.audioErr = err
		} else {
			e.audioSession = sess
		}
	}

	core.OnVoiceFrame(func(sender string, opusData []byte) {
		r.onRemoteVoice(sender, opusData)
	})

	if e.audioSession != nil && r.enc != nil {
		frames, err := e.audioSession.StartMic()
		if err != nil {
			r.audioErr = err
		} else {
			r.wg.Add(1)
			go r.micLoop(frames)
		}
		if err := e.audioSession.StartPlayback(func(out []int16) {
			r.mix.Mix(out)
		}); err != nil {
			r.audioErr = err
		}
	}

	r.wg.Add(1)
	go r.janitorLoop()

	e.voiceRun = r
	return r
}

func (e *Engine) stopVoiceRunner() {
	e.voiceMu.Lock()
	r := e.voiceRun
	e.voiceRun = nil
	e.voiceMu.Unlock()
	if r != nil {
		r.stopInternal()
	}
}

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

func (r *voiceRunner) stopInternal() {
	select {
	case <-r.stop:
		return
	default:
	}
	close(r.stop)
	if r.eng.audioSession != nil {
		r.eng.audioSession.StopMic()
		r.eng.audioSession.StopPlayback()
	}
	r.core.OnVoiceFrame(func(string, []byte) {})
}

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
				continue
			}
			if err := r.core.SendVoiceFrame(pkt); err != nil {
				continue
			}
		}
	}
}

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
		return
	}
	r.mix.Push(sender, samples)
	r.lastSeenMu.Lock()
	r.lastSeen[sender] = time.Now()
	r.lastSeenMu.Unlock()
}

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

func (e *Engine) AudioDeviceError() error {
	e.voiceMu.Lock()
	defer e.voiceMu.Unlock()
	if e.voiceRun == nil {
		return nil
	}
	return e.voiceRun.audioErr
}

func (e *Engine) VoiceActive() bool {
	e.voiceMu.Lock()
	defer e.voiceMu.Unlock()
	return e.voiceRun != nil
}
