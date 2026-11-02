package engine

import (
	"fmt"
	"io"
	"os"
	"sync"
	"time"

	"uniclient/audio"
	"uniclient/utils"
	"uniclient/voice"
)

type PlaybackState struct {
	AccountID string  `json:"account_id"`
	ChatID    string  `json:"chat_id"`
	MsgID     string  `json:"msg_id"`
	Playing   bool    `json:"playing"`
	Paused    bool    `json:"paused"`
	Position  float64 `json:"position"`
	Duration  float64 `json:"duration"`
	Speed     float64 `json:"speed"`
	Volume    float64 `json:"volume"`
	HasAudio  bool    `json:"has_audio"`
	Error     string  `json:"error,omitempty"`
}

var mediaSpeeds = []float64{1, 1.5, 2, 0.5}

type MediaPlayer struct {
	mu   sync.Mutex
	eng  *Engine
	sess *audio.Session

	pcm     []int16
	pos     float64
	speed   float64
	ident   [3]string
	dur     float64
	playing bool
	paused  bool

	gain float64

	lastEmit time.Time
	lastErr  string
}

func (e *Engine) newMediaPlayer() *MediaPlayer {
	return &MediaPlayer{eng: e, speed: 1, gain: 1}
}

func (e *Engine) Player() *MediaPlayer {
	e.mu.Lock()
	var (
		gain    float64
		haveCfg = e.config != nil
	)
	if haveCfg {
		gain = e.config.MediaVolumeValue()
	}
	e.mu.Unlock()

	e.mediaMu.Lock()
	if e.MediaPlayer == nil {
		e.MediaPlayer = e.newMediaPlayer()
		if haveCfg {
			e.MediaPlayer.gain = gain
		}
	}
	p := e.MediaPlayer
	e.mediaMu.Unlock()
	return p
}

func (e *Engine) MediaVolume() float64 {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.config == nil {
		return 1
	}
	return e.config.MediaVolumeValue()
}

func IsOpusOgg(path string) bool {
	f, err := os.Open(path)
	if err != nil {
		return false
	}
	defer f.Close()
	rd := NewOggPacketReader(f)
	pkt, err := rd.Next()
	if err != nil || len(pkt) < 8 {
		return false
	}
	return string(pkt[:8]) == "OpusHead"
}

func decodeOpusOgg(path string) ([]int16, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	rd := NewOggPacketReader(f)
	dec := voice.NewDecoder()
	var pcm []int16
	idx := 0
	for {
		pkt, err := rd.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("media: %w", err)
		}
		if idx < 2 {
			idx++
			continue
		}
		frame, err := dec.Decode(pkt)
		if err != nil {
			return nil, fmt.Errorf("media: packet %d: %w", idx, err)
		}
		pcm = append(pcm, frame...)
		idx++
	}
	if len(pcm) == 0 {
		return nil, fmt.Errorf("media: no audio in %s", path)
	}
	return pcm, nil
}

func (e *Engine) PlayMedia(acct, chat, msgID, path string) error {
	return e.playMediaAt(acct, chat, msgID, path, 0)
}

func (e *Engine) PlayMediaAt(acct, chat, msgID, path string, startAt time.Duration) error {
	return e.playMediaAt(acct, chat, msgID, path, startAt)
}

func MediaStartPos(startAt time.Duration, dur float64) float64 {
	if startAt <= 0 || dur <= 0 {
		return 0
	}
	s := startAt.Seconds()
	if s >= dur {
		return 0
	}
	return s
}

func (e *Engine) playMediaAt(acct, chat, msgID, path string, startAt time.Duration) error {
	var pcm []int16
	var err error
	switch {
	case IsOpusOgg(path):
		pcm, err = decodeOpusOgg(path)
	case IsMp3(path):
		pcm, err = DecodeMp3(path)
	case IsMp4(path):
		pcm, err = DecodeMp4Audio(path)
	default:
		return fmt.Errorf("media: %s is not Ogg/Opus, MP3 or MP4 audio — use the system player", path)
	}
	if err != nil {
		return err
	}

	e.mu.Lock()
	var cfgGain *float64
	if e.config != nil {
		v := e.config.MediaVolumeValue()
		cfgGain = &v
	}
	e.mu.Unlock()

	p := e.Player()
	p.mu.Lock()
	p.stopLocked()
	if cfgGain != nil {
		p.gain = *cfgGain
	}

	var hasAudio bool
	sess, aerr := audio.Open()
	if aerr == nil {
		p.sess = sess
		hasAudio = true
	} else {
		p.lastErr = aerr.Error()
	}
	p.pcm = pcm
	p.dur = float64(len(pcm)) / float64(voice.SampleRate)
	p.pos = MediaStartPos(startAt, p.dur) * float64(voice.SampleRate)
	p.speed = 1
	p.ident = [3]string{acct, chat, msgID}
	p.playing = hasAudio
	p.paused = false
	p.mu.Unlock()

	if hasAudio {
		sess.StartPlayback(p.fill)
	}
	e.emitPlayback()
	return nil
}

func (e *Engine) TogglePauseMedia() {
	p := e.Player()
	p.mu.Lock()
	if p.playing {
		p.paused = !p.paused
	}
	p.mu.Unlock()
	e.emitPlayback()
}

func (e *Engine) StopMedia() {
	p := e.Player()
	p.mu.Lock()
	had := p.stopLocked()
	p.mu.Unlock()
	if had {
		e.emitPlayback()
	}
}

func (e *Engine) CycleMediaSpeed() {
	p := e.Player()
	p.mu.Lock()
	next := mediaSpeeds[0]
	for i, s := range mediaSpeeds {
		if s == p.speed {
			next = mediaSpeeds[(i+1)%len(mediaSpeeds)]
			break
		}
	}
	p.speed = next
	p.mu.Unlock()
	e.emitPlayback()
}

func (e *Engine) SeekMedia(frac float64) error {
	p := e.Player()
	p.mu.Lock()
	if len(p.pcm) == 0 || p.dur <= 0 {
		p.mu.Unlock()
		return fmt.Errorf("media: nothing playing to seek")
	}
	if frac < 0 {
		frac = 0
	}
	if frac > 1 {
		frac = 1
	}
	p.pos = frac * float64(len(p.pcm))
	if p.sess != nil && !p.playing && !p.paused && p.pos < float64(len(p.pcm))-1 {
		p.playing = true
	}
	p.mu.Unlock()
	e.emitPlayback()
	return nil
}

func (e *Engine) SetMediaVolume(v float64) {
	v = utils.ClampMediaVolume(v)
	p := e.Player()
	p.mu.Lock()
	p.gain = v
	p.mu.Unlock()
	e.emitPlayback()
}

func (e *Engine) MediaState() PlaybackState {
	p := e.Player()
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.stateLocked()
}

func (p *MediaPlayer) stateLocked() PlaybackState {
	st := PlaybackState{
		AccountID: p.ident[0],
		ChatID:    p.ident[1],
		MsgID:     p.ident[2],
		Playing:   p.playing,
		Paused:    p.paused,
		Position:  p.pos / float64(voice.SampleRate),
		Duration:  p.dur,
		Speed:     p.speed,
		Volume:    p.gain,
		HasAudio:  p.sess != nil,
		Error:     p.lastErr,
	}
	return st
}

func (p *MediaPlayer) stopLocked() (had bool) {
	if p.sess != nil {
		p.sess.StopPlayback()
		p.sess.Close()
		p.sess = nil
	}
	had = p.playing
	p.playing = false
	p.paused = false
	p.pos = 0
	p.pcm = nil
	p.dur = 0
	p.ident = [3]string{}
	return had
}

func (p *MediaPlayer) fill(out []int16) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if !p.playing || p.paused || len(p.pcm) == 0 {
		for i := range out {
			out[i] = 0
		}
		return
	}
	n := float64(len(p.pcm))
	for i := range out {
		if p.pos >= n-1 {
			out[i] = int16(float64(p.pcm[int(n)-1]) * p.gain)
			p.pos = n
			continue
		}
		i0 := int(p.pos)
		frac := p.pos - float64(i0)
		s := int16(float64(p.pcm[i0])*(1-frac) + float64(p.pcm[i0+1])*frac)
		out[i] = int16(float64(s) * p.gain)
		p.pos += p.speed
	}
	if p.pos >= n {
		p.pos = n
		p.playing = false
	}
	if time.Since(p.lastEmit) > 250*time.Millisecond || !p.playing {
		p.lastEmit = time.Now()
		snap := p.stateLocked()
		go p.eng.emitEvent(EventPlaybackState, snap.AccountID, snap)
	}
}

func (e *Engine) emitPlayback() {
	p := e.Player()
	p.mu.Lock()
	snap := p.stateLocked()
	p.mu.Unlock()
	e.emitEvent(EventPlaybackState, snap.AccountID, snap)
}
