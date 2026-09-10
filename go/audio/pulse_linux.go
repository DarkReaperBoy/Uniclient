//go:build linux && !android

package audio

import (
	"fmt"
	"sync"

	"github.com/jfreymuth/pulse"
)

const audioAvailable = true

// pulseDevice talks to the local PulseAudio/PipeWire daemon over its
// native protocol — pure Go, no cgo, no new build-time dependencies.
type pulseDevice struct {
	mu     sync.Mutex
	client *pulse.Client

	micOn   bool
	micStop chan struct{}
	micCh   chan []byte
	micDone chan struct{}

	playOn   bool
	playStop chan struct{}
	playDone chan struct{}
}

func openDevice() (device, error) {
	c, err := pulse.NewClient()
	if err != nil {
		return nil, fmt.Errorf("audio: pulse connect: %w", err)
	}
	return &pulseDevice{client: c}, nil
}

// startMic captures mono 48 kHz float samples and repackages them into
// 20 ms s16le frames on the returned channel.
func (d *pulseDevice) startMic() (<-chan []byte, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.client == nil {
		return nil, ErrNoAudio
	}
	if d.micOn {
		return nil, fmt.Errorf("audio: mic already running")
	}

	frames := make(chan []byte, 8)
	stop := make(chan struct{})
	done := make(chan struct{})
	d.micOn, d.micCh, d.micStop, d.micDone = true, frames, stop, done

	// Pulse pushes float32 buffers of arbitrary length; we bank them
	// into 960-sample s16le frames.
	var pending []float32
	toS16 := func(in []float32) (int, error) {
		pending = append(pending, in...)
		for len(pending) >= 960 {
			frame := make([]byte, 1920)
			for i := 0; i < 960; i++ {
				v := pending[i]
				if v > 1 {
					v = 1
				} else if v < -1 {
					v = -1
				}
				s := int16(v * 32767)
				frame[2*i] = byte(s)
				frame[2*i+1] = byte(s >> 8)
			}
			pending = pending[960:]
			select {
			case frames <- frame:
			case <-stop:
				return len(in), nil
			}
		}
		// Never let a stalled reader grow the backlog unboundedly.
		if len(pending) > 960*8 {
			pending = pending[len(pending)-960:]
		}
		return len(in), nil
	}

	stream, err := d.client.NewRecord(
		pulse.Float32Writer(toS16),
		pulse.RecordSampleRate(48000),
		pulse.RecordLatency(0.05),
		pulse.RecordMediaName("Uniclient microphone"),
	)
	if err != nil {
		d.micOn = false
		return nil, fmt.Errorf("audio: pulse record: %w", err)
	}
	stream.Start()

	go func() {
		defer close(done)
		<-stop
		stream.Stop()
		stream.Close()
		close(frames)
	}()
	return frames, nil
}

func (d *pulseDevice) stopMic() {
	d.mu.Lock()
	defer d.mu.Unlock()
	if !d.micOn {
		return
	}
	d.micOn = false
	close(d.micStop)
	<-d.micDone
	d.micCh, d.micStop, d.micDone = nil, nil, nil
}

// startPlayback pulls mixed audio via fill on Pulse's clock.
func (d *pulseDevice) startPlayback(fill func(out []int16)) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.client == nil {
		return ErrNoAudio
	}
	if d.playOn {
		return fmt.Errorf("audio: playback already running")
	}
	stop := make(chan struct{})
	done := make(chan struct{})
	d.playOn, d.playStop, d.playDone = true, stop, done

	// Scratch buffers sized for whatever Pulse asks for (its buffer
	// length in samples varies with the negotiated latency).
	var pcm []int16
	reader := func(out []float32) (int, error) {
		if len(pcm) < len(out) {
			pcm = make([]int16, len(out))
		}
		fill(pcm[:len(out)])
		for i, s := range pcm[:len(out)] {
			out[i] = float32(s) / 32768
		}
		return len(out), nil
	}

	stream, err := d.client.NewPlayback(
		pulse.Float32Reader(reader),
		pulse.PlaybackSampleRate(48000),
		pulse.PlaybackLatency(0.08),
		pulse.PlaybackMediaName("Uniclient speaker"),
	)
	if err != nil {
		d.playOn = false
		return fmt.Errorf("audio: pulse playback: %w", err)
	}
	stream.Start()

	go func() {
		defer close(done)
		<-stop
		stream.Stop()
		stream.Drain()
		stream.Close()
	}()
	return nil
}

func (d *pulseDevice) stopPlayback() {
	d.mu.Lock()
	defer d.mu.Unlock()
	if !d.playOn {
		return
	}
	d.playOn = false
	close(d.playStop)
	<-d.playDone
	d.playStop, d.playDone = nil, nil
}

func (d *pulseDevice) close() {
	d.stopMic()
	d.stopPlayback()
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.client != nil {
		d.client.Close()
		d.client = nil
	}
}
