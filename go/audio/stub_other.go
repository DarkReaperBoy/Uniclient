//go:build !linux && !windows && !js

package audio

const audioAvailable = false

type stubDevice struct{}

func openDevice() (device, error) { return stubDevice{}, ErrNoAudio }

func (stubDevice) startMic() (<-chan []byte, error)  { return nil, ErrNoAudio }
func (stubDevice) stopMic()                          {}
func (stubDevice) startPlayback(func([]int16)) error { return ErrNoAudio }
func (stubDevice) stopPlayback()                     {}
func (stubDevice) close()                            {}
