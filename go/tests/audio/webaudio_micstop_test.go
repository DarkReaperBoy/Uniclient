//go:build js && wasm

package tests

import (
	"testing"
	"time"

	. "uniclient/audio"
)

func TestStopMicBeforeSettleCleansUp(t *testing.T) {
	f := NewJSFakes(t)
	defer f.release()

	dev, err := OpenDevice()
	if err != nil {
		t.Fatalf("OpenDevice: %v", err)
	}
	defer dev.Close()

	if _, err := dev.StartMic(); err != nil {
		t.Fatalf("startMic: %v", err)
	}
	dev.StopMic()

	time.Sleep(200 * time.Millisecond)

	if _, err := dev.StartMic(); err != nil {
		t.Fatalf("stopMic left the attempt armed (a stale attempt fails startMic with 'mic already running'): %v", err)
	}
	dev.StopMic()

	time.Sleep(200 * time.Millisecond)

	if errs := f.ConsoleErrors(); len(errs) > 0 {
		t.Fatalf("console errors across the settled attempts: %v", errs)
	}
}
