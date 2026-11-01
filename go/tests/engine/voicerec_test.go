package tests

import (
	"bytes"
	"io"
	"math"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	. "uniclient/engine"

	"uniclient/audio"
	"uniclient/voice"
)

func recToneFrames(n int) [][]byte {
	frames := make([][]byte, n)
	for f := range frames {
		buf := make([]byte, voice.FrameBytes)
		for i := 0; i < voice.FrameSamples; i++ {
			t := float64(f*voice.FrameSamples+i) / float64(voice.SampleRate)
			s := int16(0.5 * 32767 * math.Sin(2*math.Pi*440*t))
			buf[2*i] = byte(s)
			buf[2*i+1] = byte(s >> 8)
		}
		frames[f] = buf
	}
	return frames
}

func recSilenceFrames(n int) [][]byte {
	frames := make([][]byte, n)
	for i := range frames {
		frames[i] = make([]byte, voice.FrameBytes)
	}
	return frames
}

type micDevice struct {
	mu     sync.Mutex
	frames chan []byte
}

func (d *micDevice) StartMic() (<-chan []byte, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.frames != nil {
		return nil, audio.ErrNoAudio
	}
	d.frames = make(chan []byte, 256)
	return d.frames, nil
}

func (d *micDevice) StopMic() {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.frames != nil {
		close(d.frames)
		d.frames = nil
	}
}

func (d *micDevice) StartPlayback(func([]int16)) error { return audio.ErrNoAudio }
func (d *micDevice) StopPlayback()                     {}
func (d *micDevice) Close()                            { d.StopMic() }

func (d *micDevice) push(frames [][]byte) {
	for _, f := range frames {
		d.frames <- f
	}
}

func startRecording(t *testing.T, e *Engine) *micDevice {
	t.Helper()
	dev := &micDevice{}
	installDevice(t, func() (audio.Device, error) { return dev, nil })
	if err := e.StartVoiceRecording(); err != nil {
		t.Fatalf("StartVoiceRecording: %v", err)
	}
	t.Cleanup(func() { e.CancelVoiceRecording() })
	return dev
}

func levelReachesAbove(t *testing.T, e *Engine, min float64) float64 {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for {
		lvl := e.VoiceRecording().Level
		if lvl >= min {
			return lvl
		}
		if time.Now().After(deadline) {
			t.Fatalf("level %.3f never rose above %v", lvl, min)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func levelReachesBelow(t *testing.T, e *Engine, max float64) float64 {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for {
		lvl := e.VoiceRecording().Level
		if lvl <= max {
			return lvl
		}
		if time.Now().After(deadline) {
			t.Fatalf("level %.3f never dropped below %v", lvl, max)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func levelStaysBelow(t *testing.T, e *Engine, max float64, window time.Duration) {
	t.Helper()
	deadline := time.Now().Add(window)
	for time.Now().Before(deadline) {
		if lvl := e.VoiceRecording().Level; lvl > max {
			t.Fatalf("level %.3f exceeded %v on silence", lvl, max)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func TestVoiceRecorderRoundTrip(t *testing.T) {
	e := &Engine{}
	dev := startRecording(t, e)

	dev.push(recToneFrames(50))

	path, seconds, err := e.StopVoiceRecording()
	if err != nil {
		t.Fatalf("StopVoiceRecording: %v", err)
	}
	if path == "" {
		t.Fatalf("no voice note written (seconds %.2f)", seconds)
	}
	defer os.Remove(path)
	if seconds < 0.9 || seconds > 1.1 {
		t.Fatalf("recorded %.2fs, want ~1s", seconds)
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	rd := NewOggPacketReader(bytes.NewReader(data))
	dec := voice.NewDecoder()
	var pcm []int16
	for i := 0; ; i++ {
		pkt, err := rd.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatalf("packet %d: %v (our own container failed CRC/parse!)", i, err)
		}
		switch {
		case i == 0:
			if !bytes.HasPrefix(pkt, []byte("OpusHead")) || pkt[9] != 1 {
				t.Fatalf("bad OpusHead: %x", pkt[:12])
			}
		case i == 1:
			if !bytes.HasPrefix(pkt, []byte("OpusTags")) {
				t.Fatalf("bad OpusTags: %x", pkt[:8])
			}
		default:
			out, err := dec.Decode(pkt)
			if err != nil {
				t.Fatalf("decode packet %d: %v", i, err)
			}
			pcm = append(pcm, out...)
		}
	}
	if len(pcm) == 0 {
		t.Fatal("no audio decoded")
	}
	dur := float64(len(pcm)) / float64(voice.SampleRate)
	if dur < 0.9 || dur > 1.1 {
		t.Fatalf("decoded duration %.2fs, want ~1s", dur)
	}

	var s0, s1, s2 float64
	k := 2 * math.Pi * 440 / float64(voice.SampleRate)
	coeff := 2 * math.Cos(k)
	for _, s := range pcm {
		x := float64(s) / 32768
		s0 = x + coeff*s1 - s2
		s2 = s1
		s1 = s0
	}
	power := math.Sqrt(s1*s1+s2*s2-coeff*s1*s2) / float64(len(pcm))
	if power < 0.05 {
		t.Fatalf("440 Hz magnitude %.4f — tone did not survive the round-trip", power)
	}
	t.Logf("voice-note round-trip: 50 frames, %.2fs, 440Hz magnitude %.3f", dur, power)
}

func TestVoiceRecorderLevelAndMinDuration(t *testing.T) {
	e := &Engine{}
	dev := startRecording(t, e)

	dev.push(recSilenceFrames(10))
	levelStaysBelow(t, e, 0.05, 100*time.Millisecond)

	dev.push(recToneFrames(20))
	if lvl := levelReachesAbove(t, e, 0.1); lvl < 0.1 {
		t.Fatalf("tone level %.3f, want >0.1", lvl)
	}

	dev.push(recSilenceFrames(10))
	if lvl := levelReachesBelow(t, e, 0.05); lvl > 0.05 {
		t.Fatalf("level after silence %.3f, want ≤0.05", lvl)
	}

	e2 := &Engine{}
	dev2 := startRecording(t, e2)
	dev2.push(recToneFrames(30))
	path, seconds, err := e2.StopVoiceRecording()
	if err != nil {
		t.Fatalf("StopVoiceRecording(short): %v", err)
	}
	if path != "" {
		os.Remove(path)
		t.Fatalf("sub-minimum capture must be dropped, got %s", path)
	}
	if seconds < 0.58 || seconds > 0.62 {
		t.Fatalf("short capture duration %.3f", seconds)
	}
}

func TestVoiceRecorderNoMicIsHonest(t *testing.T) {
	e := &Engine{}
	installDevice(t, func() (audio.Device, error) { return nil, audio.ErrNoAudio })
	if err := e.StartVoiceRecording(); err == nil {
		t.Fatal("failed mic must error out of StartVoiceRecording")
	}
	st := e.VoiceRecording()
	if st.Active || st.HasMic {
		t.Fatalf("failed start must leave the recorder idle: %+v", st)
	}
}

func TestVoiceRecorderStateSnapshot(t *testing.T) {
	e := &Engine{}
	dev := startRecording(t, e)
	dev.push(recToneFrames(5))
	levelReachesAbove(t, e, 0.05)

	st := e.VoiceRecording()
	if !st.Active || !st.HasMic {
		t.Fatalf("snapshot: %+v", st)
	}
	if st.Seconds < 0 {
		t.Fatalf("snapshot seconds %.3f", st.Seconds)
	}

	e.CancelVoiceRecording()
	st = e.VoiceRecording()
	if st.Active || st.HasMic {
		t.Fatalf("cancel must idle the recorder: %+v", st)
	}
}

func TestWriteVoiceOggEmpty(t *testing.T) {
	if _, err := WriteVoiceOgg(nil, nil, filepath.Join(t.TempDir())); err == nil {
		t.Fatal("empty capture must error")
	}
}
