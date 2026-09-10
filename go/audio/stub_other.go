//go:build (!linux || android) && !windows && !js

package audio

const audioAvailable = false

// stubDevice returns ErrNoAudio for every operation. Android's audio
// layer (OpenSL ES / AudioTrack via JNI) is the top of the voice
// backlog; until it lands the GUI hides mic/speaker controls there
// rather than showing dead UI (AGENTS.md §1.10).
type stubDevice struct{}

func openDevice() (device, error) { return stubDevice{}, ErrNoAudio }

func (stubDevice) startMic() (<-chan []byte, error)  { return nil, ErrNoAudio }
func (stubDevice) stopMic()                          {}
func (stubDevice) startPlayback(func([]int16)) error { return ErrNoAudio }
func (stubDevice) stopPlayback()                     {}
func (stubDevice) close()                            {}
