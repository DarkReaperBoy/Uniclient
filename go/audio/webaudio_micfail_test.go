//go:build js && wasm

package audio

import (
	"testing"
	"time"
)

func TestStartMicFailureCleansUp(t *testing.T) {
	f := newJSFakes(t)
	f.reject()
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
