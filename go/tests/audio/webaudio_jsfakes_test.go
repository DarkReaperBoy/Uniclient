//go:build js && wasm

package tests

import (
	"math"
	"syscall/js"
	"testing"
)

type jsFakes struct {
	t         *testing.T
	keepFuncs []js.Func

	ctxCtor  js.Func
	gum      js.Func
	gumMode  string
	lastNode js.Value
}

func NewJSFakes(t *testing.T) *jsFakes {
	t.Helper()
	f := &jsFakes{t: t, gumMode: "resolve"}
	g := js.Global()
	if !g.Get("Object").Truthy() {
		t.Fatal("no JS object global")
	}

	ctxObj := g.Get("Object").New()
	ctxObj.Set("sampleRate", 48000)
	ctxClose := js.FuncOf(func(this js.Value, args []js.Value) interface{} { return nil })
	ctxObj.Set("close", ctxClose)
	ctxObj.Set("state", "running")
	ctxObj.Set("destination", g.Get("Object").New())
	createMediaStreamSource := js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		src := g.Get("Object").New()
		src.Set("connect", js.FuncOf(func(this js.Value, args []js.Value) interface{} { return nil }))
		return src
	})
	createScriptProcessor := js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		node := g.Get("Object").New()
		node.Set("connect", js.FuncOf(func(this js.Value, args []js.Value) interface{} { return nil }))
		node.Set("disconnect", js.FuncOf(func(this js.Value, args []js.Value) interface{} { return nil }))
		f.lastNode = node
		return node
	})
	createGain := js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		gn := g.Get("Object").New()
		gn.Set("gain", g.Get("Object").New())
		gn.Set("connect", js.FuncOf(func(this js.Value, args []js.Value) interface{} { return nil }))
		return gn
	})
	ctxObj.Set("createMediaStreamSource", createMediaStreamSource)
	ctxObj.Set("createScriptProcessor", createScriptProcessor)
	ctxObj.Set("createGain", createGain)
	ctxCtor := js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		return ctxObj
	})

	media := g.Get("Object").New()
	gum := js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		return g.Get("Promise").New(js.FuncOf(func(this js.Value, pargs []js.Value) interface{} {
			if f.gumMode == "reject" {
				pargs[1].Invoke(g.Get("Error").New("denied"))
			} else {
				stream := g.Get("Object").New()
				stream.Set("getTracks", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
					return g.Get("Array").New()
				}))
				pargs[0].Invoke(stream)
			}
			return nil
		}))
	})
	media.Set("getUserMedia", gum)

	nav := g.Get("navigator")
	if !nav.Truthy() {
		t.Fatal("node has no navigator global — add one in the runner prelude")
	}
	nav.Set("mediaDevices", media)
	g.Set("AudioContext", ctxCtor)

	f.ctxCtor = ctxCtor
	f.gum = gum
	f.keepFuncs = append(f.keepFuncs, ctxCtor, ctxClose, createMediaStreamSource, createScriptProcessor, createGain, gum)
	return f
}

func (f *jsFakes) release() {
	for _, fn := range f.keepFuncs {
		fn.Release()
	}
	js.Global().Get("navigator").Delete("mediaDevices")
	js.Global().Delete("AudioContext")
}

func (f *jsFakes) reject() { f.gumMode = "reject" }

func (f *jsFakes) PumpAudioBuffer(samples []float64, rate float64) {
	f.t.Helper()
	handler := f.lastNode.Get("onaudioprocess")
	if !handler.Truthy() {
		f.t.Fatal("capture node has no onaudioprocess handler wired")
	}
	g := js.Global()
	arr := g.Get("Array").New()
	for i, v := range samples {
		arr.SetIndex(i, v)
	}
	buf := g.Get("Object").New()
	buf.Set("getChannelData", js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		return arr
	}))
	buf.Set("sampleRate", rate)
	buf.Set("length", len(samples))
	ev := g.Get("Object").New()
	ev.Set("inputBuffer", buf)
	handler.Invoke(ev)
}

func SineChunk(n int, rate, freq float64, phase int) []float64 {
	out := make([]float64, n)
	for i := 0; i < n; i++ {
		out[i] = 0.5 * math.Sin(2*math.Pi*freq*(float64(phase)/rate))
		phase++
	}
	return out
}
