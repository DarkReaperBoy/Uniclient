// Package audio abstracts microphone capture and speaker playback.
//
// Implementations are pure Go on every supported platform: PulseAudio's
// native protocol on Linux (PipeWire-compatible), winmm
// (waveIn/waveOut) syscalls on Windows, and WebAudio + getUserMedia via
// syscall/js on the web target. No cgo in our tree; the Windows build
// stays CGO_ENABLED=0.
package audio

import "errors"

// ErrNoAudio is returned on platforms where the device layer is not
// wired up yet (Android). The GUI surfaces it honestly and hides the
// mic/speaker affordances (AGENTS.md §1.10 — hide, never fake).
var ErrNoAudio = errors.New("audio: no audio devices on this platform")

// Available reports whether this build has a real device backend.
func Available() bool { return audioAvailable }

// Session is one process-wide audio connection. All voice users
// (voice rooms, later calls) share it: capture frames fan out,
// playback pulls from the active mixer callback.
type Session struct {
	dev device
}

// Open connects to the platform audio system. It returns ErrNoAudio
// when the platform has no backend.
func Open() (*Session, error) {
	dev, err := openDevice()
	if err != nil {
		return nil, err
	}
	return &Session{dev: dev}, nil
}

// Close releases the audio system. Safe to call on a nil or closed
// session.
func (s *Session) Close() {
	if s == nil || s.dev == nil {
		return
	}
	s.dev.close()
	s.dev = nil
}

// StartMic starts microphone capture. The returned channel carries
// 20 ms frames of s16le mono at 48 kHz (voice.FrameBytes bytes each).
// The channel is closed by StopMic. Callers must drain it.
func (s *Session) StartMic() (<-chan []byte, error) {
	if s == nil || s.dev == nil {
		return nil, ErrNoAudio
	}
	return s.dev.startMic()
}

// StopMic stops capture and closes the frame channel.
func (s *Session) StopMic() {
	if s == nil || s.dev == nil {
		return
	}
	s.dev.stopMic()
}

// StartPlayback starts speaker playback. fill is called whenever the
// device needs audio; it receives an output buffer of s16le mono
// samples at 48 kHz (variable length — fill what you can, silence the
// rest). fill must not block.
func (s *Session) StartPlayback(fill func(out []int16)) error {
	if s == nil || s.dev == nil {
		return ErrNoAudio
	}
	return s.dev.startPlayback(fill)
}

// StopPlayback stops the speaker stream.
func (s *Session) StopPlayback() {
	if s == nil || s.dev == nil {
		return
	}
	s.dev.stopPlayback()
}

// device is the per-platform backend.
type device interface {
	startMic() (<-chan []byte, error)
	stopMic()
	startPlayback(fill func(out []int16)) error
	stopPlayback()
	close()
}
