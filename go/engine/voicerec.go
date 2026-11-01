package engine

import (
	"fmt"
	"os"
	"sync"
	"time"

	"uniclient/audio"
	"uniclient/cores"
	"uniclient/utils"
	"uniclient/voice"
)

type VoiceRecording struct {
	Active  bool    `json:"active"`
	Seconds float64 `json:"seconds"`
	Level   float64 `json:"level"`
	HasMic  bool    `json:"has_mic"`
}

const minVoiceNote = 900 * time.Millisecond

type voiceRecorder struct {
	mu   sync.Mutex
	eng  *Engine
	sess *audio.Session

	enc     *voice.Encoder
	samples int
	packets [][]byte
	granule []int64
	level   float64
	started time.Time

	micCh <-chan []byte
	done  chan struct{}
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
	enc, err := voice.NewEncoder(24000)
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

func (e *Engine) StopVoiceRecording() (path string, seconds float64, err error) {
	r := e.recorder()
	r.mu.Lock()
	enc := r.enc
	r.mu.Unlock()
	if enc == nil {
		return "", 0, fmt.Errorf("voice: not recording")
	}

	r.stopDevice()
	<-r.done

	r.mu.Lock()
	r.enc = nil
	frames := r.packets
	granules := r.granule
	samples := r.samples
	r.packets = nil
	r.granule = nil
	r.mu.Unlock()

	seconds = float64(samples) / float64(voice.SampleRate)
	if time.Duration(seconds*float64(time.Second)) < minVoiceNote {
		return "", seconds, nil
	}
	path, err = writeVoiceOgg(frames, granules, e.mediaDir)
	return path, seconds, err
}

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

func (r *voiceRecorder) stopDevice() {
	r.mu.Lock()
	sess := r.sess
	r.sess = nil
	r.mu.Unlock()
	if sess != nil {
		sess.StopMic()
		sess.Close()
	}
}

func opusHead() []byte {
	p := make([]byte, 19)
	copy(p, "OpusHead")
	p[8] = 1
	p[9] = 1
	p[12] = 0x80
	p[13] = 0xBB
	return p
}

func opusTags() []byte {
	p := make([]byte, 16)
	copy(p, "OpusTags")
	return p
}

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

	const serial = 0x55434C59
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

func (e *Engine) SendVoiceNote(accountID, chatID, path string, seconds int) (string, error) {
	if !e.VoiceRecordingSupported(accountID) {
		return "", fmt.Errorf("voice: account does not support voice notes")
	}
	return e.UploadFileEx(accountID, chatID, path, cores.UploadOptions{
		IsVoice:  true,
		Duration: seconds,
	})
}

func (e *Engine) VoiceNoteTempDir() string {
	if e.mediaDir != "" {
		return e.mediaDir
	}
	dir, err := utils.PrivateCacheDir("voice-notes")
	if err != nil {
		return os.TempDir()
	}
	return dir
}
