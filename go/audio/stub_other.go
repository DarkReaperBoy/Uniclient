//go:build !linux && !windows && !js

package audio

const audioAvailable = false

type StubDevice struct{}

func OpenDevice() (Device, error) { return StubDevice{}, ErrNoAudio }

func (StubDevice) startMic() (<-chan []byte, error)  { return nil, ErrNoAudio }
func (StubDevice) stopMic()                          {}
func (StubDevice) startPlayback(func([]int16)) error { return ErrNoAudio }
func (StubDevice) stopPlayback()                     {}
func (StubDevice) close()                            {}
