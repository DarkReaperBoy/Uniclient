//go:build js && wasm

package audio

import (
	"fmt"
	"sync"
	"syscall/js"
)

const audioAvailable = true

// webDevice uses the browser's WebAudio API for playback and
// getUserMedia + WebAudio for capture. Everything runs through
// syscall/js — pure Go, same GUI code.
type webDevice struct {
	mu sync.Mutex

	ctx     js.Value
	ctxRate float64

	playNode  js.Value
	playFn    js.Func // keep the Go callback alive
	playFnSet bool
	playFill  func(out []int16)

	// micStop is the LIVE attempt's stop channel; it is non-nil from
	// startMic until the attempt is ended (stopMic or a rejected
	// getUserMedia), which is exactly the "mic already running" window.
	// micDone closes when that attempt's cleanup goroutine finished.
	// Everything else a mic attempt needs lives in per-attempt locals
	// captured by its own goroutine, so overlapping attempts (a failed
	// one unwinding while a fresh one starts) never touch each other's
	// js.Funcs (risk R2).
	micStop chan struct{}
	micDone chan struct{}
}

func openDevice() (device, error) {
	ctor := js.Global().Get("AudioContext")
	if ctor.IsUndefined() {
		ctor = js.Global().Get("webkitAudioContext")
	}
	if ctor.IsUndefined() {
		return nil, fmt.Errorf("audio: browser has no WebAudio")
	}
	opts := js.Global().Get("Object").New()
	opts.Set("sampleRate", 48000)
	ctx := ctor.New(opts)
	rate := ctx.Get("sampleRate").Float()
	return &webDevice{ctx: ctx, ctxRate: rate}, nil
}

// resample linearly maps 48 kHz samples to the context's rate.
func resample(in []int16, fromRate, toRate float64) []int16 {
	if fromRate == toRate || len(in) == 0 {
		return in
	}
	ratio := toRate / fromRate
	n := int(float64(len(in)) * ratio)
	if n < 1 {
		n = 1
	}
	out := make([]int16, n)
	for i := 0; i < n; i++ {
		pos := float64(i) / ratio
		i0 := int(pos)
		if i0 >= len(in)-1 {
			out[i] = in[len(in)-1]
			continue
		}
		frac := pos - float64(i0)
		out[i] = int16(float64(in[i0])*(1-frac) + float64(in[i0+1])*frac)
	}
	return out
}

// startPlayback streams fill() through a ScriptProcessorNode.
func (d *webDevice) startPlayback(fill func(out []int16)) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if !d.playNode.IsNull() && !d.playNode.IsUndefined() {
		return fmt.Errorf("audio: playback already running")
	}
	d.playFill = fill
	scratch := make([]int16, 2048)

	fn := js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		buf := args[0].Get("outputBuffer")
		ch := buf.Get("getChannelData").Invoke(0)
		n := ch.Length()
		if len(scratch) < n {
			scratch = make([]int16, n)
		}
		fill(scratch[:n])
		// 48k fill → context rate (no-op when equal).
		out := resample(scratch[:n], 48000, d.ctxRate)
		for i := 0; i < n && i < len(out); i++ {
			ch.SetIndex(i, float64(out[i])/32768)
		}
		return nil
	})
	d.playFn, d.playFnSet = fn, true

	node := d.ctx.Get("createScriptProcessor").Invoke(2048, 1, 1)
	node.Set("onaudioprocess", fn)
	node.Call("connect", d.ctx.Get("destination"))
	if d.ctx.Get("state").String() == "suspended" {
		d.ctx.Call("resume")
	}
	d.playNode = node
	return nil
}

func (d *webDevice) stopPlayback() {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.playNode.IsNull() || d.playNode.IsUndefined() {
		return
	}
	d.playNode.Set("onaudioprocess", nil)
	d.playNode.Call("disconnect")
	d.playNode = js.Value{}
	if d.playFnSet {
		d.playFn.Release()
		d.playFnSet = false
	}
	d.playFill = nil
}

// startMic captures getUserMedia audio and repackages it into 20 ms
// 48 kHz s16le frames.
func (d *webDevice) startMic() (<-chan []byte, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.micStop != nil {
		return nil, fmt.Errorf("audio: mic already running")
	}

	media := js.Global().Get("navigator").Get("mediaDevices")
	if media.IsUndefined() {
		return nil, fmt.Errorf("audio: browser has no mediaDevices")
	}
	constraints := js.Global().Get("Object").New()
	audio := js.Global().Get("Object").New()
	audio.Set("channelCount", 1)
	audio.Set("echoCancellation", true)
	audio.Set("noiseSuppression", true)
	audio.Set("autoGainControl", true)
	constraints.Set("audio", audio)

	promise := media.Call("getUserMedia", constraints)
	// The promise resolves asynchronously; wire the node up in the
	// then-callback while the frame channel exists from the start.
	frames := make(chan []byte, 8)
	stop := make(chan struct{})
	done := make(chan struct{})
	d.micStop, d.micDone = stop, done

	// endMicAttempt is the single "this attempt is over" transition: it
	// un-publishes the attempt from the device exactly once (so a fresh
	// startMic may begin immediately) and releases the cleanup goroutine.
	// The identity check under the mutex is the close guard: if stopMic
	// already ended this attempt (permission dialog still open), the
	// channel is closed and nil-published, and a late failure callback
	// must not close it twice.
	endMicAttempt := func() {
		d.mu.Lock()
		defer d.mu.Unlock()
		if d.micStop == stop {
			d.micStop, d.micDone = nil, nil
			close(stop)
		}
	}

	var pending []float64 // banked input samples at the mic's rate
	var micRate float64
	fn := js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		buf := args[0].Get("inputBuffer")
		ch := buf.Get("getChannelData").Invoke(0)
		n := ch.Length()
		if micRate == 0 {
			micRate = ch.Get("sampleRate").Float()
			if micRate == 0 {
				micRate = 48000
			}
		}
		for i := 0; i < n; i++ {
			pending = append(pending, ch.Index(i).Float())
		}
		// Convert to s16 at 48 kHz in 960-sample frames.
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
				return nil
			}
		}
		if len(pending) > 960*8 {
			pending = pending[len(pending)-960:]
		}
		return nil
	})

	// node/stream are this attempt's js handles, published by setup and
	// torn down by the cleanup goroutine below — both see the same
	// per-attempt values, never another attempt's.
	var node, stream js.Value
	setup := js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		d.mu.Lock()
		defer d.mu.Unlock()
		select {
		case <-stop:
			return nil // stopped while permission dialog was open
		default:
		}
		stream = args[0]
		src := d.ctx.Call("createMediaStreamSource", stream)
		n := d.ctx.Get("createScriptProcessor").Invoke(2048, 1, 1)
		n.Set("onaudioprocess", fn)
		src.Call("connect", n)
		// A ScriptProcessor needs a destination to actually run; route
		// it through a zero-gain node so nothing is echoed.
		zero := d.ctx.Get("createGain").Invoke()
		zero.Get("gain").Set("value", 0)
		n.Call("connect", zero)
		zero.Call("connect", d.ctx.Get("destination"))
		if d.ctx.Get("state").String() == "suspended" {
			d.ctx.Call("resume")
		}
		node = n
		return nil
	})
	// A rejected getUserMedia is an honest mic-end for the reader AND an
	// attempt-end for cleanup — without the second half the attempt's
	// goroutine and all its js.Funcs leaked forever (risk R2).
	failed := js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		close(frames)
		endMicAttempt()
		return nil
	})
	promise.Call("then", setup, failed)

	// One cleanup goroutine per attempt, owning ONLY this attempt's
	// resources. It cannot race a newer attempt: every value it touches
	// is captured here, and the js teardown happens at most once per
	// attempt because `stop` closes exactly once.
	go func() {
		defer close(done)
		<-stop
		if !node.IsNull() && !node.IsUndefined() {
			node.Set("onaudioprocess", nil)
			node.Call("disconnect")
		}
		if !stream.IsNull() && !stream.IsUndefined() {
			tracks := stream.Call("getTracks")
			for i := 0; i < tracks.Length(); i++ {
				tracks.Index(i).Call("stop")
			}
		}
		fn.Release()
		setup.Release()
		failed.Release()
	}()
	return frames, nil
}

func (d *webDevice) stopMic() {
	d.mu.Lock()
	stop := d.micStop
	done := d.micDone
	d.micStop, d.micDone = nil, nil
	d.mu.Unlock()
	if stop != nil {
		close(stop)
	}
	if done != nil {
		<-done
	}
}

func (d *webDevice) close() {
	d.stopMic()
	d.stopPlayback()
	d.mu.Lock()
	defer d.mu.Unlock()
	if !d.ctx.IsNull() && !d.ctx.IsUndefined() {
		d.ctx.Call("close")
		d.ctx = js.Value{}
	}
}
