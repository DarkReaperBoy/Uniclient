//go:build !linux && !windows && !js

package audio

const audioAvailable = false

// stubDevice returns ErrNoAudio for every operation. Android ships a real
// OpenSL ES backend (opensl_android.go); every other platform we target
// (linux/windows/js) has its own device file. This stub only covers
// unusual GOOS values that Go can still compile for, keeping them honest
// rather than fake (AGENTS.md §1.10).
type stubDevice struct{}

func openDevice() (device, error) { return stubDevice{}, ErrNoAudio }

func (stubDevice) startMic() (<-chan []byte, error)  { return nil, ErrNoAudio }
func (stubDevice) stopMic()                          {}
func (stubDevice) startPlayback(func([]int16)) error { return ErrNoAudio }
func (stubDevice) stopPlayback()                     {}
func (stubDevice) close()                            {}
