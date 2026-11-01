package audio

import "errors"

var ErrNoAudio = errors.New("audio: no audio devices on this platform")

func Available() bool { return audioAvailable }

type Session struct {
	dev device
}

func Open() (*Session, error) {
	dev, err := openDevice()
	if err != nil {
		return nil, err
	}
	return &Session{dev: dev}, nil
}

func (s *Session) Close() {
	if s == nil || s.dev == nil {
		return
	}
	s.dev.close()
	s.dev = nil
}

func (s *Session) StartMic() (<-chan []byte, error) {
	if s == nil || s.dev == nil {
		return nil, ErrNoAudio
	}
	return s.dev.startMic()
}

func (s *Session) StopMic() {
	if s == nil || s.dev == nil {
		return
	}
	s.dev.stopMic()
}

func (s *Session) StartPlayback(fill func(out []int16)) error {
	if s == nil || s.dev == nil {
		return ErrNoAudio
	}
	return s.dev.startPlayback(fill)
}

func (s *Session) StopPlayback() {
	if s == nil || s.dev == nil {
		return
	}
	s.dev.stopPlayback()
}

type device interface {
	startMic() (<-chan []byte, error)
	stopMic()
	startPlayback(fill func(out []int16)) error
	stopPlayback()
	close()
}
