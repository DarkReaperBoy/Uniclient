package tests

import (
	"fmt"
	"sync"
	"testing"

	"uniclient/audio"
	"uniclient/cores"

	. "uniclient/engine"
)

type fakeMicDevice struct {
	mic chan []byte
}

func (d *fakeMicDevice) StartMic() (<-chan []byte, error)  { return d.mic, nil }
func (d *fakeMicDevice) StopMic()                          {}
func (d *fakeMicDevice) StartPlayback(func([]int16)) error { return nil }
func (d *fakeMicDevice) StopPlayback()                     {}
func (d *fakeMicDevice) Close()                            {}

type journeyVoiceCore struct {
	cores.StubCore

	mu          sync.Mutex
	frames      int
	terminators int
}

func (c *journeyVoiceCore) JoinGroupCall(string) (*cores.CallSession, error) {
	return &cores.CallSession{ID: "call1"}, nil
}

func (c *journeyVoiceCore) SendVoiceFrame(opus []byte) error {
	c.mu.Lock()
	c.frames++
	c.mu.Unlock()
	return nil
}

func (c *journeyVoiceCore) SendVoiceTerminator() error {
	c.mu.Lock()
	c.terminators++
	c.mu.Unlock()
	return nil
}

func (c *journeyVoiceCore) OnVoiceFrame(func(string, []byte)) {}

func (c *journeyVoiceCore) SetVoiceMuted(bool) error { return nil }

func (c *journeyVoiceCore) counts() (frames, terminators int) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.frames, c.terminators
}

func newVoiceJourney(t *testing.T) (*dbEngine, *journeyVoiceCore, chan []byte) {
	t.Helper()
	mic := make(chan []byte, 64)
	audio.SetDeviceFactory(func() (audio.Device, error) {
		return &fakeMicDevice{mic: mic}, nil
	})
	t.Cleanup(func() { audio.SetDeviceFactory(nil) })
	e := newTestEngine(t)
	t.Cleanup(func() { _ = e.Shutdown() })
	core := &journeyVoiceCore{}
	if err := e.AttachAccount("a1", "telegram", core); err != nil {
		t.Fatal(err)
	}
	if _, err := e.JoinGroupCall("a1", "c1"); err != nil {
		t.Fatalf("JoinGroupCall: %v", err)
	}
	return e, core, mic
}

func TestVoiceVADDecision(t *testing.T) {
	_, core, mic := newVoiceJourney(t)
	loud := frameWithRMS(0.10)
	quiet := frameWithRMS(0.0005)

	feed := func(frame []byte, wantFrames int) {
		t.Helper()
		mic <- frame
		waitUntil(t, fmt.Sprintf("voice frames == %d", wantFrames), func() bool {
			frames, _ := core.counts()
			return frames >= wantFrames
		})
	}

	feed(loud, 1)
	feed(loud, 2)
	for i := 0; i < VoiceHangoverFrames; i++ {
		feed(quiet, 3+i)
	}

	mic <- quiet
	waitUntil(t, "voice terminator after hangover", func() bool {
		_, terminators := core.counts()
		return terminators >= 1
	})
	if frames, terminators := core.counts(); frames != 2+VoiceHangoverFrames || terminators != 1 {
		t.Fatalf("after silence: frames=%d terminators=%d, want %d/1",
			frames, terminators, 2+VoiceHangoverFrames)
	}

	mic <- quiet
	mic <- quiet
	feed(loud, 3+VoiceHangoverFrames)
	if frames, terminators := core.counts(); frames != 3+VoiceHangoverFrames || terminators != 1 {
		t.Fatalf("after resume: frames=%d terminators=%d, want %d/1 (prolonged silence must stay inert)",
			frames, terminators, 3+VoiceHangoverFrames)
	}
}

func TestVoiceVADColdStart(t *testing.T) {
	_, core, mic := newVoiceJourney(t)
	quiet := frameWithRMS(0.0005)

	for i := 0; i < 10; i++ {
		mic <- quiet
	}
	mic <- frameWithRMS(0.10)
	waitUntil(t, "voice frame after cold-start silence", func() bool {
		frames, _ := core.counts()
		return frames >= 1
	})
	if frames, terminators := core.counts(); frames != 1 || terminators != 0 {
		t.Fatalf("cold start: frames=%d terminators=%d, want 1/0 (cold-start silence must send nothing and arm no terminator)",
			frames, terminators)
	}
}

func frameWithRMS(rms float64) []byte {
	const n = 960
	out := make([]byte, n*2)
	amp := rms * 32768 * 1.414
	for i := 0; i < n; i++ {
		var s int16
		if (i/11)%2 == 0 {
			s = int16(amp)
		} else {
			s = -int16(amp)
		}
		out[2*i] = byte(s)
		out[2*i+1] = byte(s >> 8)
	}
	return out
}
