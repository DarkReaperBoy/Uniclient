//go:build js

package audio

import (
	"syscall/js"
	"testing"
	"time"
)

// installMicFailureFakes gives the wasm test a browser-less environment:
// a stub AudioContext (only the fields the failure path touches — plus close,
// which the test's device cleanup calls) and a mediaDevices whose getUserMedia
// resolves the FAILURE branch via a rejected promise (settles on a
// microtask, after startMic has released the device mutex). Node 24 ships a
// global navigator object — mediaDevices is added to it (the global itself
// is not assignable). Returns a cleanup func.
func installMicFailureFakes(t *testing.T) func() {
	t.Helper()
	var keep []js.Func
	release := func() {
		for _, f := range keep {
			f.Release()
		}
		js.Global().Get("navigator").Delete("mediaDevices")
		js.Global().Delete("AudioContext")
	}

	g := js.Global()
	if !g.Get("Object").Truthy() {
		t.Fatal("no JS object global")
	}

	ctxObj := g.Get("Object").New()
	ctxObj.Set("sampleRate", 48000)
	ctxClose := js.FuncOf(func(this js.Value, args []js.Value) interface{} { return nil })
	ctxObj.Set("close", ctxClose)
	ctxCtor := js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		return ctxObj
	})

	media := g.Get("Object").New()
	gum := js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		// A REAL rejected promise: the executor rejects synchronously but
		// promise semantics settle the handlers on a microtask — after
		// startMic has released the device mutex, exactly like a browser.
		return g.Get("Promise").New(js.FuncOf(func(this js.Value, pargs []js.Value) interface{} {
			pargs[1].Invoke(g.Get("Error").New("denied"))
			return nil
		}))
	})
	media.Set("getUserMedia", gum)

	nav := g.Get("navigator")
	if !nav.Truthy() {
		t.Fatal("node has no navigator global — set one up in the runner prelude")
	}
	nav.Set("mediaDevices", media)

	g.Set("AudioContext", ctxCtor)
	keep = append(keep, ctxCtor, ctxClose, gum)
	return release
}

// TestStartMicFailureCleansUp (risk R2): a rejected getUserMedia must tear
// the whole mic attempt down — the stop channel is disarmed, the frames
// channel closes for the reader, and a fresh startMic works immediately.
// RED against the leak: the failed path left micStop armed (and the old
// cleanup goroutine blocked forever on it), so this read hangs or the
// state check fails.
func TestStartMicFailureCleansUp(t *testing.T) {
	cleanup := installMicFailureFakes(t)
	defer cleanup()

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

	select {
	case _, ok := <-frames:
		if ok {
			t.Fatal("rejected getUserMedia must not deliver frames")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("rejected getUserMedia must close the frames channel")
	}

	web.mu.Lock()
	stopArmed := web.micStop != nil
	web.mu.Unlock()
	if stopArmed {
		t.Fatal("failed mic attempt left the stop channel armed — the cleanup goroutine never runs and the js.Funcs leak (R2)")
	}

	// A fresh attempt must work on the clean state machine.
	frames2, err := web.startMic()
	if err != nil {
		t.Fatalf("second startMic after a failed attempt: %v", err)
	}
	select {
	case _, ok := <-frames2:
		if ok {
			t.Fatal("second attempt must also fail cleanly (fake rejects)")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("second attempt: frames channel never closed")
	}
	web.stopMic()
}
