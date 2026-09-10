package voice

import (
	"bytes"
	"math"
	"sync"
	"testing"
)

// goertzel returns the magnitude of `freq` in the s16 mono sample stream,
// normalized to the stream's peak amplitude.
func goertzel(samples []int16, sampleRate, freq int) float64 {
	if len(samples) == 0 {
		return 0
	}
	k := 2 * math.Pi * float64(freq) / float64(sampleRate)
	coeff := 2 * math.Cos(k)
	var s0, s1, s2 float64
	peak := 1.0
	for _, s := range samples {
		x := float64(s) / 32768
		if a := math.Abs(x); a > peak {
			peak = a
		}
		s0 = x + coeff*s1 - s2
		s2 = s1
		s1 = s0
	}
	power := math.Sqrt(s1*s1 + s2*s2 - coeff*s1*s2)
	return power / float64(len(samples)) / peak
}

// sine generates n frames of `freq` sine as s16le mono bytes.
func sine(freq float64, frames int, amp float64) [][]byte {
	out := make([][]byte, frames)
	for f := range out {
		buf := make([]byte, FrameBytes)
		for i := 0; i < FrameSamples; i++ {
			t := float64(f*FrameSamples+i) / float64(SampleRate)
			v := amp * math.Sin(2*math.Pi*freq*t)
			s := int16(v * 32767)
			buf[2*i] = byte(s)
			buf[2*i+1] = byte(s >> 8)
		}
		out[f] = buf
	}
	return out
}

// encodeAll encodes every PCM frame through the encoder.
func encodeAll(t *testing.T, e *Encoder, frames [][]byte) [][]byte {
	t.Helper()
	pkts := make([][]byte, len(frames))
	for i, f := range frames {
		p, err := e.Encode(f)
		if err != nil {
			t.Fatalf("frame %d: %v", i, err)
		}
		pkts[i] = append([]byte(nil), p...)
	}
	return pkts
}

// decodeAll decodes every packet through the decoder, returning the
// concatenated sample stream.
func decodeAll(t *testing.T, d *Decoder, pkts [][]byte) []int16 {
	t.Helper()
	var out []int16
	for i, p := range pkts {
		s, err := d.Decode(p)
		if err != nil {
			t.Fatalf("packet %d: %v", i, err)
		}
		out = append(out, s...)
	}
	return out
}

func TestEncoderDecoderRoundTrip(t *testing.T) {
	e, err := NewEncoder(32000)
	if err != nil {
		t.Fatal(err)
	}
	d := NewDecoder()

	// 2 seconds of 440 Hz.
	pkts := encodeAll(t, e, sine(440, 100, 0.5))
	if len(pkts) != 100 {
		t.Fatalf("packets = %d", len(pkts))
	}
	got := decodeAll(t, d, pkts)
	if len(got) < SampleRate/2 { // at least ~0.5s decoded
		t.Fatalf("decoded only %d samples", len(got))
	}

	m440 := goertzel(got, SampleRate, 440)
	m880 := goertzel(got, SampleRate, 880)
	m300 := goertzel(got, SampleRate, 300)
	t.Logf("440Hz=%.4f 880Hz=%.4f 300Hz=%.4f samples=%d", m440, m880, m300, len(got))
	if m440 < 0.05 {
		t.Fatalf("fundamental missing: 440Hz magnitude %.4f", m440)
	}
	if m440 < m880*2 || m440 < m300*2 {
		t.Fatalf("signal not dominated by 440Hz: %.4f vs %.4f/%.4f", m440, m880, m300)
	}
}

func TestEncoderFrameSize(t *testing.T) {
	e, err := NewEncoder(24000)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := e.Encode(make([]byte, FrameBytes-2)); err == nil {
		t.Fatal("short frame accepted")
	}
	if _, err := e.Encode(make([]byte, FrameBytes+2)); err == nil {
		t.Fatal("long frame accepted")
	}
}

func TestEncoderSilence(t *testing.T) {
	e, err := NewEncoder(16000)
	if err != nil {
		t.Fatal(err)
	}
	d := NewDecoder()
	pkts := encodeAll(t, e, sine(440, 10, 0))
	if len(pkts) != 10 {
		t.Fatalf("packets = %d", len(pkts))
	}
	for i, p := range pkts {
		if len(p) == 0 {
			t.Fatalf("packet %d empty", i)
		}
		if len(p) > 200 {
			t.Fatalf("silence packet %d suspiciously large: %d bytes", i, len(p))
		}
	}
	got := decodeAll(t, d, pkts)
	for i, s := range got {
		if s > 64 || s < -64 {
			t.Fatalf("decoded silence sample %d = %d (not silent)", i, s)
		}
	}
}

func TestDecoderReuse(t *testing.T) {
	e, err := NewEncoder(24000)
	if err != nil {
		t.Fatal(err)
	}
	d := NewDecoder()
	for round := 0; round < 3; round++ {
		got := decodeAll(t, d, encodeAll(t, e, sine(float64(300+100*round), 25, 0.5)))
		if len(got) == 0 {
			t.Fatalf("round %d: no output", round)
		}
		m := goertzel(got, SampleRate, 300+100*round)
		if m < 0.03 {
			t.Fatalf("round %d: tone %dHz magnitude %.4f", round, 300+100*round, m)
		}
	}
}

func TestMixerTwoSources(t *testing.T) {
	e1, _ := NewEncoder(24000)
	e2, _ := NewEncoder(24000)
	m := NewMixer()

	// A: 440Hz, B: 660Hz.
	pA := encodeAll(t, e1, sine(440, 30, 0.5))
	pB := encodeAll(t, e2, sine(660, 30, 0.5))
	dA, dB := NewDecoder(), NewDecoder()
	for i := range pA {
		sa, err := dA.Decode(pA[i])
		if err != nil {
			t.Fatal(err)
		}
		m.Push("a", sa)
		sb, err := dB.Decode(pB[i])
		if err != nil {
			t.Fatal(err)
		}
		m.Push("b", sb)
	}

	var mixed []int16
	out := make([]int16, FrameSamples)
	for i := 0; i < 30; i++ {
		m.Mix(out)
		mixed = append(mixed, out...)
	}
	if len(mixed) != 30*FrameSamples {
		t.Fatalf("mixed %d samples", len(mixed))
	}
	m440 := goertzel(mixed, SampleRate, 440)
	m660 := goertzel(mixed, SampleRate, 660)
	m300 := goertzel(mixed, SampleRate, 300)
	t.Logf("440=%.4f 660=%.4f 300=%.4f", m440, m660, m300)
	if m440 < 0.02 || m660 < 0.02 {
		t.Fatalf("both sources must survive the mix: 440=%.4f 660=%.4f", m440, m660)
	}
	if m440 < m300*2 {
		t.Fatalf("mix polluted: 440=%.4f 300=%.4f", m440, m300)
	}
}

func TestMixerVolume(t *testing.T) {
	e, _ := NewEncoder(24000)
	m1, m2 := NewMixer(), NewMixer()
	m2.SetVolume("s", 0.25)

	pkts := encodeAll(t, e, sine(440, 20, 0.5))
	d1, d2 := NewDecoder(), NewDecoder()
	for i := range pkts {
		s1, _ := d1.Decode(pkts[i])
		m1.Push("s", s1)
		s2, _ := d2.Decode(pkts[i])
		m2.Push("s", s2)
	}
	full := mixAll(m1, 20)
	quiet := mixAll(m2, 20)
	rms := func(x []int16) float64 {
		var acc float64
		for _, s := range x {
			acc += float64(s) * float64(s)
		}
		return math.Sqrt(acc / float64(len(x)))
	}
	rf, rq := rms(full), rms(quiet)
	t.Logf("rms full=%.1f quiet=%.1f", rf, rq)
	if rq < 100 {
		t.Fatalf("quiet output dead: rms %.1f", rq)
	}
	if rq > rf*0.6 || rq < rf*0.05 {
		t.Fatalf("volume 0.25 out of range: quiet=%.1f full=%.1f", rq, rf)
	}
}

func mixAll(m *Mixer, frames int) []int16 {
	out := make([]int16, FrameSamples)
	var acc []int16
	for i := 0; i < frames; i++ {
		m.Mix(out)
		acc = append(acc, out...)
	}
	return acc
}

func TestMixerRemoveAndUnderrun(t *testing.T) {
	m := NewMixer()
	out := make([]int16, FrameSamples)

	// Empty mixer: silence, no panic.
	m.Mix(out)
	for i, s := range out {
		if s != 0 {
			t.Fatalf("empty mix sample %d = %d", i, s)
		}
	}

	// Push then remove: back to silence.
	e, _ := NewEncoder(24000)
	pkts := encodeAll(t, e, sine(440, 5, 0.5))
	d := NewDecoder()
	s, err := d.Decode(pkts[0])
	if err != nil {
		t.Fatal(err)
	}
	m.Push("x", s)
	m.Push("x", s)
	m.Remove("x")
	m.Mix(out)
	for i, v := range out {
		if v != 0 {
			t.Fatalf("removed source still audible: sample %d = %d", i, v)
		}
	}
	if m.Levels()["x"] != 0 {
		t.Fatalf("level for removed source must be 0")
	}
}

func TestMixerLevelsTrackActivity(t *testing.T) {
	m := NewMixer()
	e, _ := NewEncoder(24000)
	pkts := encodeAll(t, e, sine(440, 10, 0.5))
	d := NewDecoder()
	var prev float64
	for i := range pkts {
		s, _ := d.Decode(pkts[i])
		m.Push("spk", s)
		lvl := m.Levels()["spk"]
		if i >= 1 && lvl <= prev && lvl == 0 {
			t.Fatalf("level stayed at 0 after push %d", i)
		}
		prev = lvl
	}
	if m.Levels()["spk"] == 0 {
		t.Fatal("no level reported for active source")
	}
}

func TestMixerConcurrent(t *testing.T) {
	m := NewMixer()
	e, _ := NewEncoder(24000)
	pkts := encodeAll(t, e, sine(440, 40, 0.5))
	var wg sync.WaitGroup
	for w := 0; w < 4; w++ {
		wg.Add(1)
		go func(w int) {
			defer wg.Done()
			d := NewDecoder()
			id := string(rune('a' + w))
			for i := range pkts {
				s, _ := d.Decode(pkts[i])
				m.Push(id, s)
			}
		}(w)
	}
	wg.Add(1)
	go func() {
		defer wg.Done()
		out := make([]int16, FrameSamples)
		for i := 0; i < 40; i++ {
			m.Mix(out)
		}
	}()
	wg.Wait()
}

func TestPCMBytesConversion(t *testing.T) {
	pcm := sine(100, 2, 0.5)
	samples := PCMBytesToSamples(pcm[0])
	if len(samples) != FrameSamples {
		t.Fatalf("%d samples", len(samples))
	}
	back := SamplesToPCMBytes(samples)
	if !bytes.Equal(back, pcm[0]) {
		t.Fatal("round-trip mismatch")
	}
}
