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

// In-app playback of downloaded media (Ogg/Opus voice notes + opus
// audio, and MP3 music since slice 185). The file is decoded fully into
// PCM at load (voice notes are seconds-to-minutes — a few MB of PCM at
// most), then played through the pure-Go audio device layer in pull
// mode with position and speed (linear-interpolation resampling).
// Formats neither decoder covers stay with the system-player handoff
// (§1.10).

// PlaybackState is the player's public snapshot.
type PlaybackState struct {
	AccountID string  `json:"account_id"`
	ChatID    string  `json:"chat_id"`
	MsgID     string  `json:"msg_id"`
	Playing   bool    `json:"playing"`
	Paused    bool    `json:"paused"`
	Position  float64 `json:"position"` // seconds
	Duration  float64 `json:"duration"` // seconds
	Speed     float64 `json:"speed"`
	Volume    float64 `json:"volume"`    // output gain, 0..1 (row 276's control)
	HasAudio  bool    `json:"has_audio"` // false where no audio backend exists
	Error     string  `json:"error,omitempty"`
}

// mediaSpeeds are the offered playback factors (Telegram's ladder).
var mediaSpeeds = []float64{1, 1.5, 2, 0.5}

type mediaPlayer struct {
	mu   sync.Mutex
	eng  *Engine
	sess *audio.Session

	pcm     []int16 // mono 48 kHz
	pos     float64 // sample position, fractional under speed != 1
	speed   float64
	ident   [3]string
	dur     float64 // seconds
	playing bool
	paused  bool

	// gain is the output volume, 0..1 (slice 224, parity row 276). It is
	// applied to the samples fill hands the device and is deliberately
	// NOT reset by stopLocked — the next track keeps the volume the user
	// chose instead of jumping back to loud.
	gain float64

	lastEmit time.Time
	lastErr  string
}

// newMediaPlayer lazily constructs the app-wide player.
func (e *Engine) newMediaPlayer() *mediaPlayer {
	return &mediaPlayer{eng: e, speed: 1, gain: 1}
}

func (e *Engine) player() *mediaPlayer {
	e.mediaMu.Lock()
	if e.mediaPlayer == nil {
		e.mediaPlayer = e.newMediaPlayer()
	}
	p := e.mediaPlayer
	e.mediaMu.Unlock()
	return p
}

// IsOpusOgg reports whether the file at path is Ogg/Opus (the only
// in-app playable format). Sniffs the first page's magic packets.
func IsOpusOgg(path string) bool {
	f, err := os.Open(path)
	if err != nil {
		return false
	}
	defer f.Close()
	rd := newOggPacketReader(f)
	pkt, err := rd.Next()
	if err != nil || len(pkt) < 8 {
		return false
	}
	return string(pkt[:8]) == "OpusHead"
}

// decodeOpusOgg decodes an Ogg/Opus file into mono 48 kHz PCM.
// Stereo input is mixed down; OpusHead rates other than 48k are
// accepted (Opus decodes to the requested rate; the decoder is fixed
// at 48k here, matching every Telegram voice note and opus-in-ogg
// default the ecosystem produces).
func decodeOpusOgg(path string) ([]int16, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	rd := newOggPacketReader(f)
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
		if idx < 2 { // OpusHead / OpusTags
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

// PlayMedia starts in-app playback of a downloaded message's file.
// Switches playback from any previous message; emits EventPlaybackState.
func (e *Engine) PlayMedia(acct, chat, msgID, path string) error {
	// In-app playable formats: Ogg/Opus (voice notes, opus audio), MP3
	// (music files, slice 185) and the AAC track of an MP4 (video and
	// round video notes, slice 224) decode through the pure-Go pipeline;
	// everything else stays with the system-player handoff (§1.10).
	var pcm []int16
	var err error
	switch {
	case IsOpusOgg(path):
		pcm, err = decodeOpusOgg(path)
	case IsMp3(path):
		pcm, err = decodeMp3(path)
	case IsMp4(path):
		pcm, err = decodeMp4Audio(path)
	default:
		return fmt.Errorf("media: %s is not Ogg/Opus, MP3 or MP4 audio — use the system player", path)
	}
	if err != nil {
		return err
	}

	// Restore the configured volume for this track. With no config in
	// memory (headless, tests) cfgGain stays nil and the runtime value
	// set by SetMediaVolume stands — otherwise a fresh player in a test
	// would start muted instead of at unity.
	e.mu.Lock()
	var cfgGain *float64
	if e.config != nil {
		v := e.config.MediaVolumeValue()
		cfgGain = &v
	}
	e.mu.Unlock()

	p := e.player()
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
	p.pos = 0
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

// TogglePauseMedia pauses/resumes the active playback.
func (e *Engine) TogglePauseMedia() {
	p := e.player()
	p.mu.Lock()
	if p.playing {
		p.paused = !p.paused
	}
	p.mu.Unlock()
	e.emitPlayback()
}

// StopMedia stops playback and releases the audio session.
func (e *Engine) StopMedia() {
	p := e.player()
	p.mu.Lock()
	had := p.stopLocked()
	p.mu.Unlock()
	if had {
		e.emitPlayback()
	}
}

// CycleMediaSpeed steps through 1x → 1.5x → 2x → 0.5x.
func (e *Engine) CycleMediaSpeed() {
	p := e.player()
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

// SeekMedia jumps the active playback to a fraction (0..1) of its
// duration. A playback that already finished re-arms and resumes from
// the seek point (tdesktop's replay-on-seek behavior); seeking with no
// active playback is an honest error.
func (e *Engine) SeekMedia(frac float64) error {
	p := e.player()
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
		// Finished playback re-arms and resumes from the seek point
		// (tdesktop's replay-on-seek) — only with a live audio device;
		// a no-device player never fakes a Playing state (§1.10).
		p.playing = true
	}
	p.mu.Unlock()
	e.emitPlayback()
	return nil
}

// SetMediaVolume sets the live playback gain, clamped to 0..1. A drag on
// a slider is the caller, so out-of-range input is bounded rather than
// rejected. Persistence is the other half: the GUI also sends
// ConfigChanges.MediaVolume, which is what survives a restart — this call
// is the half that changes what is audible right now.
func (e *Engine) SetMediaVolume(v float64) {
	v = utils.ClampMediaVolume(v)
	p := e.player()
	p.mu.Lock()
	p.gain = v
	p.mu.Unlock()
	e.emitPlayback()
}

// MediaState snapshots the player.
func (e *Engine) MediaState() PlaybackState {
	p := e.player()
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.stateLocked()
}

func (p *mediaPlayer) stateLocked() PlaybackState {
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

// stopLocked halts playback and resets state. Returns whether
// anything was playing (the caller emits AFTER releasing the lock —
// emitPlayback re-locks).
func (p *mediaPlayer) stopLocked() (had bool) {
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

// fill is the pull-mode audio callback (runs on the device thread; must
// not block). Advances the fractional source position by speed per
// output sample with linear interpolation; emits throttled progress.
func (p *mediaPlayer) fill(out []int16) {
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
			// At the tail: emit the final sample once and pin the
			// position at the end so the completion check below fires.
			// Volume scales the OUTPUT only: p.pcm is never modified,
			// so turning one track down cannot turn down the next one
			// (TestMediaVolumeScalesPlayback pins this).
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
	// Throttled progress events (~4/s) keep the GUI's bar and elapsed
	// label live without flooding the event channel.
	if time.Since(p.lastEmit) > 250*time.Millisecond || !p.playing {
		p.lastEmit = time.Now()
		snap := p.stateLocked()
		go p.eng.emitEvent(EventPlaybackState, snap.AccountID, snap)
	}
}

// emitPlayback pushes a state snapshot to the host.
func (e *Engine) emitPlayback() {
	p := e.player()
	p.mu.Lock()
	snap := p.stateLocked()
	p.mu.Unlock()
	e.emitEvent(EventPlaybackState, snap.AccountID, snap)
}
