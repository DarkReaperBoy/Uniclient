package audio

import (
	"errors"
	"sync"
)

var ErrNoAudio = errors.New("audio: no audio devices on this platform")

var (
	deviceFactoryMu sync.Mutex
	deviceFactory   func() (Device, error)
)

func SetDeviceFactory(f func() (Device, error)) {
	deviceFactoryMu.Lock()
	defer deviceFactoryMu.Unlock()
	deviceFactory = f
}

func deviceFactoryInstalled() bool {
	deviceFactoryMu.Lock()
	defer deviceFactoryMu.Unlock()
	return deviceFactory != nil
}

func Available() bool { return audioAvailable || deviceFactoryInstalled() }

type Session struct {
	dev Device
}

func Open() (*Session, error) {
	deviceFactoryMu.Lock()
	factory := deviceFactory
	deviceFactoryMu.Unlock()
	if factory != nil {
		dev, err := factory()
		if err != nil {
			return nil, err
		}
		return &Session{dev: dev}, nil
	}
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
