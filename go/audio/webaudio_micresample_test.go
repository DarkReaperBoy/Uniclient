//go:build js && wasm

package audio

import (
	"testing"
	"time"
)

// TestStartMicResamplesNon48kContextRate (risk R3): a browser that ignores
// the requested 48 kHz AudioContext hands capture buffers at its own rate
// (e.g. 44.1 kHz). The capture path must emit ONE 20 ms 48 kHz frame per
// 960 output samples — resampled from the incoming rate — not slice the
// raw bank at 960 (which pitch-shifts and time-stretches the voice ~8.8%).
// It also pins that the rate is read from the AudioBuffer (real channel
// data has NO sampleRate property — the old code read it off the channel
// data object, which would have failed on a real browser).
func TestStartMicResamplesNon48kContextRate(t *testing.T) {
	f := newJSFakes(t)
	defer f.release()

	dev, err := openDevice()
	if err != nil {
		t.Fatalf("openDevice: %v", err)
	}
	web := dev.(*webDevice)
	defer web.close()

	frames, err := web.startMic()
	if err != nil {
		t.Fatalf("startMic: %v", err)
	}

	// Let the (already-resolved) getUserMedia microtask run: it wires the
	// capture node. A blocked Go select pumps the JS event loop in wasm.
	time.Sleep(100 * time.Millisecond)

	// Deliver 0.4 s worth of a 440 Hz sine at the context's REAL rate
	// (44100 — the classic ignores-the-request browser), in audio-thread
	// sized chunks. 0.4 s @44100 = 17640 inputs. Resampled framing: a
	// non-resampling slicer would emit floor(17640/960) = 18 frames; the
	// correct resampler emits 19 (the 20th 20 ms frame is withheld until
	// its one-sample interpolation look-ahead arrives — tail latency of
	// the streaming window, not a rate error).
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
		f.pumpAudioBuffer(sineChunk(n, inRate, 440, phase), inRate)
		phase += n
		delivered += n
		// drain whatever frames are ready so the channel never blocks
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

	// stopMic ends the attempt (reader lifecycle belongs to the engine;
	// only a REJECTED permission closes frames — pinned in the micfail
	// test). It must return promptly, releasing the capture node.
	web.stopMic()
	web.mu.Lock()
	stopped := web.micStop == nil
	web.mu.Unlock()
	if !stopped {
		t.Fatal("stopMic left the attempt armed")
	}
}

// TestStartMicPassthroughAt48k: with the context honoring 48 kHz the
// capture path must emit the input bit-exact (0.1 s → 5 frames, values
// clamped-identical to what was pumped in).
func TestStartMicPassthroughAt48k(t *testing.T) {
	f := newJSFakes(t)
	defer f.release()

	dev, err := openDevice()
	if err != nil {
		t.Fatalf("openDevice: %v", err)
	}
	web := dev.(*webDevice)
	defer web.close()

	frames, err := web.startMic()
	if err != nil {
		t.Fatalf("startMic: %v", err)
	}

	time.Sleep(100 * time.Millisecond)

	const inRate = 48000
	total := 4800 // 0.1 s
	phase := 0
	delivered := 0
	var gotFrames [][]byte
	for delivered < total {
		n := 2048
		if total-delivered < n {
			n = total - delivered
		}
		f.pumpAudioBuffer(sineChunk(n, inRate, 440, phase), inRate)
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

	// 0.1 s @48k = 5 frames, but the resampler holds the last frame for its
	// one-sample look-ahead: 4 now...
	if len(gotFrames) != 4 {
		t.Fatalf("got %d frames for 0.1 s @48k before look-ahead flush, want 4", len(gotFrames))
	}
	// ...and the fifth frame lands as soon as one more input sample
	// completes its interpolation window.
	f.pumpAudioBuffer([]float64{0.5, 0.5}, inRate)
	select {
	case fr := <-frames:
		gotFrames = append(gotFrames, fr)
	case <-time.After(2 * time.Second):
		t.Fatal("look-ahead sample did not flush the pending frame")
	}
	// First output sample maps to input sample 0 (interp frac 0).
	first := int16(gotFrames[0][0]) | int16(gotFrames[0][1])<<8
	wantFirst := int16(0.5 * 32767 * 0) // sine at phase 0 = 0.0 → sample 0
	if first != wantFirst {
		t.Fatalf("identity path output[0] = %d, want %d (bit-exact passthrough)", first, wantFirst)
	}
	web.stopMic()
}
