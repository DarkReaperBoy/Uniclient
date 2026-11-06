//go:build js && wasm

package tests

import (
	"testing"
	"time"
	. "uniclient/audio"
)

func TestStartMicFailureCleansUp(t *testing.T) {
	f := NewJSFakes(t)
	f.reject()
	defer f.release()

	dev, err := OpenDevice()
	if err != nil {
		t.Fatalf("OpenDevice: %v", err)
	}
	defer dev.Close()

	frames, err := dev.StartMic()
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

	frames2, err := dev.StartMic()
	if err != nil {
		t.Fatalf("failed attempt leaked its stop channel (R2: the cleanup goroutine never runs and the js.Funcs leak — a stale armed attempt fails startMic with 'mic already running'): %v", err)
	}
	select {
	case _, ok := <-frames2:
		if ok {
			t.Fatal("second attempt must also fail cleanly (fake rejects)")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("second attempt: frames channel never closed")
	}
	dev.StopMic()
}
