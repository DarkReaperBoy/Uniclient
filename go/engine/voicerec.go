package engine

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"uniclient/audio"
	"uniclient/cores"
	"uniclient/voice"
)

// Hold-to-record voice notes (slice 114): the mic layer (slice 110)
// captures 20 ms frames, the pure-Go Opus encoder packs them, and the
// Ogg writer (the page builder from engine/ogg.go — the same container
// the player demuxes) produces a Telegram-shaped voice-note file. The
// GUI sends it through UploadFileEx with IsVoice + duration.

// VoiceRecording is the recorder's public snapshot.
type VoiceRecording struct {
	Active  bool    `json:"active"`
	Seconds float64 `json:"seconds"`
	Level   float64 `json:"level"` // smoothed RMS, 0..1 (UI bars)
	HasMic  bool    `json:"has_mic"`
}

// minVoiceNote is the shortest sendable recording (Telegram's own
// floor); shorter holds are discarded as accidental taps.
const minVoiceNote = 900 * time.Millisecond

type voiceRecorder struct {
	mu   sync.Mutex
	eng  *Engine
	sess *audio.Session

	enc     *voice.Encoder
	samples int      // encoded samples so far (960/frame)
	packets [][]byte // opus packets
	granule []int64  // cumulative sample count at each packet's end
	level   float64  // smoothed RMS for the UI
	started time.Time

	micCh   <-chan []byte
	stopMic func()
	done    chan struct{}
}

func (e *Engine) newVoiceRecorder() *voiceRecorder {
	return &voiceRecorder{eng: e}
}

func (e *Engine) recorder() *voiceRecorder {
	e.recMu.Lock()
	if e.voiceRecorder == nil {
		e.voiceRecorder = e.newVoiceRecorder()
	}
	r := e.voiceRecorder
	e.recMu.Unlock()
	return r
}

// VoiceRecordingSupported reports whether the account's core can send
// voice notes (UploadFileWithOptions with IsVoice — Telegram and Bale).
func (e *Engine) VoiceRecordingSupported(accountID string) bool {
	e.accountsMu.RLock()
	acc := e.accounts[accountID]
	e.accountsMu.RUnlock()
	if acc == nil || acc.Core == nil {
		return false
	}
	_, ok := acc.Core.(cores.UploadWithOptionsSupporter)
	return ok
}

// StartVoiceRecording begins capturing. Fails honestly when no
// microphone exists on this platform (§1.10 — the GUI hides the
// affordance, and this is the second gate).
func (e *Engine) StartVoiceRecording() error {
	r := e.recorder()
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.enc != nil {
		return fmt.Errorf("voice: recording already active")
	}
	sess, err := audio.Open()
	if err != nil {
		return fmt.Errorf("voice: %w", err)
	}
	frames, err := sess.StartMic()
	if err != nil {
		sess.Close()
		return fmt.Errorf("voice: mic: %w", err)
	}
	enc, err := voice.NewEncoder(24000) // Telegram-ish voice bitrate
	if err != nil {
		sess.StopMic()
		sess.Close()
		return fmt.Errorf("voice: %w", err)
	}
	r.sess = sess
	r.enc = enc
	r.packets = nil
	r.granule = nil
	r.samples = 0
	r.level = 0
	r.started = time.Now()
	r.micCh = frames
	r.done = make(chan struct{})
	go r.micLoop(frames)
	return nil
}

// micLoop drains the device's frame channel until Stop/Cancel closes
// the mic (channel close ends the loop).
func (r *voiceRecorder) micLoop(frames <-chan []byte) {
	defer close(r.done)
	for frame := range frames {
		r.mu.Lock()
		stopped := r.enc == nil
		r.mu.Unlock()
		if stopped {
			return
		}
		r.feedFrame(frame)
	}
}

// feedFrame encodes one 20 ms s16le mono frame and tracks the UI level.
// Package-internal: tests drive it directly, no device needed.
func (r *voiceRecorder) feedFrame(frame []byte) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.enc == nil {
		return fmt.Errorf("voice: not recording")
	}
	pkt, err := r.enc.Encode(frame)
	if err != nil {
		return err
	}
	cp := make([]byte, len(pkt))
	copy(cp, pkt)
	r.packets = append(r.packets, cp)
	r.samples += voice.FrameSamples
	r.granule = append(r.granule, int64(r.samples))
	r.level = voiceLevel(frame, r.level)
	return nil
}

// voiceLevel computes the smoothed RMS of an s16le mono frame, mixed
// toward the previous value (UI smoothing).
func voiceLevel(frame []byte, prev float64) float64 {
	if len(frame) < 2 {
		return prev
	}
	var acc float64
	n := 0
	for i := 0; i+1 < len(frame); i += 2 {
		s := float64(int16(frame[i])|int16(frame[i+1])<<8) / 32768
		acc += s * s
		n++
	}
	if n == 0 {
		return prev
	}
	rms := acc / float64(n)
	return 0.7*prev + 0.3*rms
}

// VoiceRecording snapshots the recorder state for the UI.
func (e *Engine) VoiceRecording() VoiceRecording {
	r := e.recorder()
	r.mu.Lock()
	defer r.mu.Unlock()
	st := VoiceRecording{HasMic: r.sess != nil}
	if r.enc != nil {
		st.Active = true
		st.Seconds = time.Since(r.started).Seconds()
		st.Level = r.level
		st.HasMic = true
	}
	return st
}

// StopVoiceRecording finishes the capture and writes the Ogg/Opus file
// (media dir). Returns the path + duration; the GUI uploads it with
// UploadFileEx(IsVoice). Recordings shorter than minVoiceNote return
// os.ErrNotExist-style empty path (the caller shows a hint instead).
func (e *Engine) StopVoiceRecording() (path string, seconds float64, err error) {
	r := e.recorder()
	r.mu.Lock()
	frames, enc := r.packets, r.enc
	r.mu.Unlock()
	if enc == nil {
		return "", 0, fmt.Errorf("voice: not recording")
	}

	r.stopDevice()
	<-r.done // wait for the mic loop to drain

	r.mu.Lock()
	r.enc = nil
	frames = r.packets
	granules := r.granule
	samples := r.samples
	r.packets = nil
	r.granule = nil
	r.mu.Unlock()

	seconds = float64(samples) / float64(voice.SampleRate)
	if time.Duration(seconds*float64(time.Second)) < minVoiceNote {
		return "", seconds, nil // too short: caller hints, nothing sent
	}
	path, err = writeVoiceOgg(frames, granules, e.mediaDir)
	return path, seconds, err
}

// CancelVoiceRecording discards the capture.
func (e *Engine) CancelVoiceRecording() {
	r := e.recorder()
	r.mu.Lock()
	if r.enc == nil {
		r.mu.Unlock()
		return
	}
	r.mu.Unlock()
	r.stopDevice()
	<-r.done
	r.mu.Lock()
	r.enc = nil
	r.packets = nil
	r.granule = nil
	r.mu.Unlock()
}

// stopDevice closes the mic and audio session (ends the mic loop).
func (r *voiceRecorder) stopDevice() {
	r.mu.Lock()
	sess := r.sess
	r.sess = nil
	r.mu.Unlock()
	if sess != nil {
		sess.StopMic() // closes the frame channel
		sess.Close()
	}
}

// ── Ogg/Opus writer ─────────────────────────────────────────────────────

// opusHead builds the mandatory 19-byte OpusHead packet: mono, 48 kHz,
// no preskip, no gain, no channel mapping.
func opusHead() []byte {
	p := make([]byte, 19)
	copy(p, "OpusHead")
	p[8] = 1 // version
	p[9] = 1 // channels
	// p[10:12] preskip = 0
	// p[12:16] input sample rate (informational)
	p[12] = 0x80 // 48000 LE → 0xBB80
	p[13] = 0xBB
	// p[16:18] gain = 0; p[18] mapping family = 0
	return p
}

// opusTags builds the minimal OpusTags packet (empty vendor/comments).
func opusTags() []byte {
	p := make([]byte, 16)
	copy(p, "OpusTags")
	return p
}

// writeVoiceOgg assembles the recorded packets into an Ogg page stream.
// Pages: header (OpusHead), tags (OpusTags), then audio packets in
// batches of 25 (500 ms) with running granule positions — the layout
// ffmpeg/libopus produce and every player (ours included) demuxes.
func writeVoiceOgg(packets [][]byte, granules []int64, dir string) (string, error) {
	if len(packets) == 0 || len(granules) != len(packets) {
		return "", fmt.Errorf("voice: no audio captured")
	}
	if dir == "" {
		dir = os.TempDir()
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	f, err := os.CreateTemp(dir, "voicenote-*.ogg")
	if err != nil {
		return "", err
	}
	defer f.Close()

	const serial = 0x55434C59 // "UCLY"
	var seq uint32
	pages := [][]byte{
		buildOggPage([][]byte{opusHead()}, 0, serial, seq, false),
	}
	seq++
	pages = append(pages, buildOggPage([][]byte{opusTags()}, 0, serial, seq, false))
	seq++

	const batch = 25
	for i := 0; i < len(packets); i += batch {
		end := i + batch
		if end > len(packets) {
			end = len(packets)
		}
		last := end - 1
		pages = append(pages, buildOggPage(packets[i:end], granules[last], serial, seq, last == len(packets)-1))
		seq++
	}
	for _, pg := range pages {
		if _, err := f.Write(pg); err != nil {
			return "", err
		}
	}
	return f.Name(), nil
}

// SendVoiceNote uploads a finished recording as a voice message.
func (e *Engine) SendVoiceNote(accountID, chatID, path string, seconds int) (string, error) {
	if !e.VoiceRecordingSupported(accountID) {
		return "", fmt.Errorf("voice: account does not support voice notes")
	}
	return e.UploadFileEx(accountID, chatID, path, cores.UploadOptions{
		IsVoice:  true,
		Duration: seconds,
	})
}

// VoiceNoteTempDir returns the directory recordings are written to.
func (e *Engine) VoiceNoteTempDir() string {
	if e.mediaDir != "" {
		return e.mediaDir
	}
	return filepath.Join(os.TempDir(), "uniclient-voice")
}
