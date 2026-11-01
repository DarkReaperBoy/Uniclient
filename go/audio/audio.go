package audio

import "errors"

var ErrNoAudio = errors.New("audio: no audio devices on this platform")

func Available() bool { return audioAvailable }

type Session struct {
	dev Device
}

func Open() (*Session, error) {
	dev, err := OpenDevice()
	if err != nil {
		return nil, err
	}
	return &Session{dev: dev}, nil
}

func (s *Session) Close() {
	if s == nil || s.dev == nil {
		return
	}
	s.dev.Close()
	s.dev = nil
}

func (s *Session) StartMic() (<-chan []byte, error) {
	if s == nil || s.dev == nil {
		return nil, ErrNoAudio
	}
	return s.dev.StartMic()
}

func (s *Session) StopMic() {
	if s == nil || s.dev == nil {
		return
	}
	s.dev.StopMic()
}

func (s *Session) StartPlayback(fill func(out []int16)) error {
	if s == nil || s.dev == nil {
		return ErrNoAudio
	}
	return s.dev.StartPlayback(fill)
}

func (s *Session) StopPlayback() {
	if s == nil || s.dev == nil {
		return
	}
	s.dev.StopPlayback()
}

type Device interface {
	StartMic() (<-chan []byte, error)
	StopMic()
	StartPlayback(fill func(out []int16)) error
	StopPlayback()
	Close()
}
