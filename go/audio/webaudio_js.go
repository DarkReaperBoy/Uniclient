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

	micStream js.Value
	micNode   js.Value
	micFn     js.Func
	micFnSet  bool
	micCh     chan []byte
	micStop   chan struct{}
	micDone   chan struct{}
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
	if !d.micNode.IsNull() && !d.micNode.IsUndefined() {
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
	d.micCh, d.micStop, d.micDone = frames, stop, done

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
	d.micFn, d.micFnSet = fn, true

	setup := js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		stream := args[0]
		d.mu.Lock()
		defer d.mu.Unlock()
		select {
		case <-stop:
			return nil // stopped while permission dialog was open
		default:
		}
		d.micStream = stream
		src := d.ctx.Call("createMediaStreamSource", stream)
		node := d.ctx.Get("createScriptProcessor").Invoke(2048, 1, 1)
		node.Set("onaudioprocess", fn)
		src.Call("connect", node)
		// A ScriptProcessor needs a destination to actually run; route
		// it through a zero-gain node so nothing is echoed.
		zero := d.ctx.Get("createGain").Invoke()
		zero.Get("gain").Set("value", 0)
		node.Call("connect", zero)
		zero.Call("connect", d.ctx.Get("destination"))
		if d.ctx.Get("state").String() == "suspended" {
			d.ctx.Call("resume")
		}
		d.micNode = node
		return nil
	})
	failed := js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		close(frames)
		return nil
	})
	promise.Call("then", setup, failed)

	go func() {
		defer close(done)
		<-stop
		d.mu.Lock()
		node, stream, fnv, fnSet := d.micNode, d.micStream, d.micFn, d.micFnSet
		d.micNode, d.micStream, d.micFn, d.micFnSet = js.Value{}, js.Value{}, js.Func{}, false
		d.mu.Unlock()
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
		if fnSet {
			fnv.Release()
		}
	}()
	return frames, nil
}

func (d *webDevice) stopMic() {
	d.mu.Lock()
	stop := d.micStop
	d.micStop = nil
	d.mu.Unlock()
	if stop == nil {
		return
	}
	close(stop)
	<-d.micDone
	d.mu.Lock()
	d.micCh, d.micDone = nil, nil
	d.mu.Unlock()
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
