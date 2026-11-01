//go:build js && wasm

package tests

import (
	"testing"
	"time"
	. "uniclient/audio"
)

func TestStartMicResamplesNon48kContextRate(t *testing.T) {
	f := NewJSFakes(t)
	defer f.release()

	dev, err := OpenDevice()
	if err != nil {
		t.Fatalf("OpenDevice: %v", err)
	}
	web := dev.(*WebDevice)
	defer web.Close()

	frames, err := web.StartMic()
	if err != nil {
		t.Fatalf("startMic: %v", err)
	}

	time.Sleep(100 * time.Millisecond)

	const inRate = 44100
	const seconds = 0.4
	total := int(float64(inRate) * seconds)
	phase := 0
	delivered := 0
	got := 0
	for delivered < total {
		n := 2048
		if total-delivered < n {
			n = total - delivered
		}
		f.PumpAudioBuffer(SineChunk(n, inRate, 440, phase), inRate)
		phase += n
		delivered += n
		for {
			select {
			case fr, ok := <-frames:
				if !ok {
					t.Fatal("frames closed mid-capture")
				}
				if len(fr) != 1920 {
					t.Fatalf("frame size = %d bytes, want 1920 (20 ms s16 mono @48k)", len(fr))
				}
				got++
			default:
				goto next
			}
		}
	next:
	}

	if got != 19 {
		t.Fatalf("captured 0.4s at %d Hz: got %d frames, want 19 (resampled 20 ms framing at 48 kHz; a non-resampling slicer yields 18)", inRate, got)
	}

	web.StopMic()
	web.ForTestMu().Lock()
	stopped := web.MicStop == nil
	web.ForTestMu().Unlock()
	if !stopped {
		t.Fatal("stopMic left the attempt armed")
	}
}

func TestStartMicPassthroughAt48k(t *testing.T) {
	f := NewJSFakes(t)
	defer f.release()

	dev, err := OpenDevice()
	if err != nil {
		t.Fatalf("OpenDevice: %v", err)
	}
	web := dev.(*WebDevice)
	defer web.Close()

	frames, err := web.StartMic()
	if err != nil {
		t.Fatalf("startMic: %v", err)
	}

	time.Sleep(100 * time.Millisecond)

	const inRate = 48000
	total := 4800
	phase := 0
	delivered := 0
	var gotFrames [][]byte
	for delivered < total {
		n := 2048
		if total-delivered < n {
			n = total - delivered
		}
		f.PumpAudioBuffer(SineChunk(n, inRate, 440, phase), inRate)
		phase += n
		delivered += n
		for {
			select {
			case fr := <-frames:
				gotFrames = append(gotFrames, fr)
			default:
				goto next
			}
		}
	next:
	}

	if len(gotFrames) != 4 {
		t.Fatalf("got %d frames for 0.1 s @48k before look-ahead flush, want 4", len(gotFrames))
	}
	f.PumpAudioBuffer([]float64{0.5, 0.5}, inRate)
	select {
	case fr := <-frames:
		gotFrames = append(gotFrames, fr)
	case <-time.After(2 * time.Second):
		t.Fatal("look-ahead sample did not flush the pending frame")
	}
	first := int16(gotFrames[0][0]) | int16(gotFrames[0][1])<<8
	wantFirst := int16(0.5 * 32767 * 0)
	if first != wantFirst {
		t.Fatalf("identity path output[0] = %d, want %d (bit-exact passthrough)", first, wantFirst)
	}
	web.StopMic()
}
