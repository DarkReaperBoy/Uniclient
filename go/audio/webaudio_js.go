//go:build js && wasm

package audio

import (
	"fmt"
	"math"
	"sync"
	"syscall/js"
)

const audioAvailable = true

type WebDevice struct {
	mu sync.Mutex

	ctx     js.Value
	ctxRate float64

	playNode  js.Value
	playFn    js.Func
	playFnSet bool
	playFill  func(out []int16)

	MicStop chan struct{}
	micDone chan struct{}
}

func OpenDevice() (Device, error) {
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
	return &WebDevice{ctx: ctx, ctxRate: rate}, nil
}

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

func (d *WebDevice) StartPlayback(fill func(out []int16)) error {
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

func (d *WebDevice) StopPlayback() {
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

func (d *WebDevice) StartMic() (<-chan []byte, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.MicStop != nil {
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
	frames := make(chan []byte, 8)
	stop := make(chan struct{})
	done := make(chan struct{})
	d.MicStop, d.micDone = stop, done

	endMicAttempt := func() {
		d.mu.Lock()
		defer d.mu.Unlock()
		if d.MicStop == stop {
			d.MicStop, d.micDone = nil, nil
			close(stop)
		}
	}

	var pending []float64
	var micRate float64
	fn := js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		buf := args[0].Get("inputBuffer")
		if micRate == 0 {
			micRate = buf.Get("sampleRate").Float()
			if micRate == 0 {
				micRate = 48000
			}
		}
		ch := buf.Get("getChannelData").Invoke(0)
		n := ch.Length()
		for i := 0; i < n; i++ {
			pending = append(pending, ch.Index(i).Float())
		}
		const outRate = 48000.0
		step := micRate * 960 / outRate
		need := int(step*959/960) + 2
		for len(pending) >= need {
			frame := make([]byte, 1920)
			for j := 0; j < 960; j++ {
				pos := float64(j) * step / 960
				i0 := int(pos)
				frac := pos - float64(i0)
				v := pending[i0]*(1-frac) + pending[i0+1]*frac
				if v > 1 {
					v = 1
				} else if v < -1 {
					v = -1
				}
				s := int16(v * 32767)
				frame[2*j] = byte(s)
				frame[2*j+1] = byte(s >> 8)
			}
			pending = pending[int(math.Ceil(step)):]
			select {
			case frames <- frame:
			case <-stop:
				return nil
			}
		}
		if len(pending) > need*9 {
			pending = pending[len(pending)-need:]
		}
		return nil
	})

	var node, stream js.Value
	setup := js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		d.mu.Lock()
		defer d.mu.Unlock()
		select {
		case <-stop:
			return nil
		default:
		}
		stream = args[0]
		src := d.ctx.Call("createMediaStreamSource", stream)
		n := d.ctx.Get("createScriptProcessor").Invoke(2048, 1, 1)
		n.Set("onaudioprocess", fn)
		src.Call("connect", n)
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
	failed := js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		close(frames)
		endMicAttempt()
		return nil
	})
	promise.Call("then", setup, failed)

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

func (d *WebDevice) StopMic() {
	d.mu.Lock()
	stop := d.MicStop
	done := d.micDone
	d.MicStop, d.micDone = nil, nil
	d.mu.Unlock()
	if stop != nil {
		close(stop)
	}
	if done != nil {
		<-done
	}
}

func (d *WebDevice) Close() {
	d.StopMic()
	d.StopPlayback()
	d.mu.Lock()
	defer d.mu.Unlock()
	if !d.ctx.IsNull() && !d.ctx.IsUndefined() {
		d.ctx.Call("close")
		d.ctx = js.Value{}
	}
}
