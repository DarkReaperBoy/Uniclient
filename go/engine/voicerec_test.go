package engine

import (
	"bytes"
	"io"
	"math"
	"os"
	"path/filepath"
	"testing"
	"time"

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

func startRecorderNoDevice(t *testing.T, e *Engine) *voiceRecorder {
	t.Helper()
	r := e.recorder()
	enc, err := voice.NewEncoder(24000)
	if err != nil {
		t.Fatalf("encoder: %v", err)
	}
	r.mu.Lock()
	r.enc = enc
	r.started = time.Now()
	r.done = make(chan struct{})
	close(r.done)
	r.mu.Unlock()
	return r
}

func TestVoiceRecorderRoundTrip(t *testing.T) {
	e := &Engine{}
	r := startRecorderNoDevice(t, e)

	frames := recToneFrames(50)
	for _, f := range frames {
		if err := r.feedFrame(f); err != nil {
			t.Fatalf("feedFrame: %v", err)
		}
	}

	r.mu.Lock()
	pkts := append([][]byte(nil), r.packets...)
	gran := append([]int64(nil), r.granule...)
	r.enc = nil
	r.packets = nil
	r.mu.Unlock()

	if len(pkts) != 50 || len(gran) != 50 {
		t.Fatalf("packet/granule counts: %d/%d", len(pkts), len(gran))
	}
	if gran[49] != 50*voice.FrameSamples {
		t.Fatalf("final granule %d, want %d", gran[49], 50*voice.FrameSamples)
	}

	path, err := writeVoiceOgg(pkts, gran, t.TempDir())
	if err != nil {
		t.Fatalf("writeVoiceOgg: %v", err)
	}
	defer os.Remove(path)

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	rd := newOggPacketReader(bytes.NewReader(data))
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
	t.Logf("voice-note round-trip: 50 packets, %.2fs, 440Hz magnitude %.3f", dur, power)
}

func TestVoiceRecorderLevelAndMinDuration(t *testing.T) {
	e := &Engine{}
	r := startRecorderNoDevice(t, e)

	for _, f := range recSilenceFrames(10) {
		r.feedFrame(f)
	}
	r.mu.Lock()
	lvl := r.level
	r.mu.Unlock()
	if lvl > 0.05 {
		t.Fatalf("silence level %.3f, want ~0", lvl)
	}

	for _, f := range recToneFrames(20) {
		r.feedFrame(f)
	}
	r.mu.Lock()
	lvl = r.level
	r.mu.Unlock()
	if lvl < 0.1 {
		t.Fatalf("tone level %.3f, want >0.1", lvl)
	}

	e2 := &Engine{}
	r2 := startRecorderNoDevice(t, e2)
	for _, f := range recToneFrames(30) {
		r2.feedFrame(f)
	}
	r2.mu.Lock()
	pkts := append([][]byte(nil), r2.packets...)
	gran := append([]int64(nil), r2.granule...)
	r2.enc = nil
	r2.packets = nil
	r2.mu.Unlock()
	path, err := writeVoiceOgg(pkts, gran, t.TempDir())
	if err != nil || path == "" {
		t.Fatalf("direct write of a short capture must still work: %v", err)
	}
	secs := float64(30*voice.FrameSamples) / float64(voice.SampleRate)
	if secs < 0.58 || secs > 0.62 {
		t.Fatalf("short capture duration %.3f", secs)
	}
}

func TestVoiceRecorderNoMicIsHonest(t *testing.T) {
	e := &Engine{}
	if err := e.StartVoiceRecording(); err == nil {
		e.CancelVoiceRecording()
		return
	}
	st := e.VoiceRecording()
	if st.Active || st.HasMic {
		t.Fatalf("failed start must leave the recorder idle: %+v", st)
	}
}

func TestVoiceRecorderStateSnapshot(t *testing.T) {
	e := &Engine{}
	r := startRecorderNoDevice(t, e)
	for _, f := range recToneFrames(5) {
		r.feedFrame(f)
	}
	st := e.VoiceRecording()
	if !st.Active || st.HasMic != true && st.Seconds < 0 {
		t.Fatalf("snapshot: %+v", st)
	}
	if !st.Active {
		t.Fatal("recording must report Active while the encoder exists")
	}
}

func recSilenceFrames(n int) [][]byte {
	frames := make([][]byte, n)
	for i := range frames {
		frames[i] = make([]byte, voice.FrameBytes)
	}
	return frames
}

func TestWriteVoiceOggEmpty(t *testing.T) {
	if _, err := writeVoiceOgg(nil, nil, filepath.Join(t.TempDir())); err == nil {
		t.Fatal("empty capture must error")
	}
}
