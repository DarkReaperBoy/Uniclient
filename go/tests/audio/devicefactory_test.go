package tests

import (
	"testing"

	. "uniclient/audio"
)

type factoryDevice struct {
	started int
	closed  int
}

func (d *factoryDevice) StartMic() (<-chan []byte, error) { return nil, ErrNoAudio }
func (d *factoryDevice) StopMic()                         {}
func (d *factoryDevice) StartPlayback(fill func(out []int16)) error {
	d.started++
	return nil
}
func (d *factoryDevice) StopPlayback() {}
func (d *factoryDevice) Close()        { d.closed++ }

func TestDeviceFactoryServesOpen(t *testing.T) {
	dev := &factoryDevice{}
	SetDeviceFactory(func() (Device, error) { return dev, nil })
	defer SetDeviceFactory(nil)

	if !Available() {
		t.Fatal("a registered device factory must make audio available")
	}
	sess, err := Open()
	if err != nil {
		t.Fatalf("Open with factory: %v", err)
	}
	if sess == nil {
		t.Fatal("Open returned a nil session")
	}
	if err := sess.StartPlayback(func([]int16) {}); err != nil {
		t.Fatalf("StartPlayback: %v", err)
	}
	if dev.started != 1 {
		t.Fatalf("StartPlayback did not route to the factory device: %d", dev.started)
	}
	sess.Close()
	if dev.closed != 1 {
		t.Fatalf("Close did not route to the factory device: %d", dev.closed)
	}
}

func TestDeviceFactoryErrorsSurface(t *testing.T) {
	SetDeviceFactory(func() (Device, error) { return nil, ErrNoAudio })
	defer SetDeviceFactory(nil)

	if _, err := Open(); err != ErrNoAudio {
		t.Fatalf("factory error must surface from Open unchanged: %v", err)
	}
}

func TestDeviceFactoryNilRestoresPlatform(t *testing.T) {
	calls := 0
	SetDeviceFactory(func() (Device, error) {
		calls++
		return nil, ErrNoAudio
	})
	SetDeviceFactory(nil)

	sess, _ := Open()
	if calls != 0 {
		t.Fatalf("a nil factory must not be consulted: %d calls", calls)
	}
	if sess != nil {
		sess.Close()
	}
}
