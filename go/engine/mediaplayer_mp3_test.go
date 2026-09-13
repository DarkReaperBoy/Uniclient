package engine

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

// In-app MP3 playback (slice 185): pure logic — the ID3/sync sniffer,
// stereo mixdown, linear resampling — plus a full decode+play test over
// an ffmpeg-generated fixture (skipped where ffmpeg is unavailable;
// GitHub CI runners ship it).

func TestIsMp3(t *testing.T) {
	dir := t.TempDir()
	cases := []struct {
		name string
		data []byte
		want bool
	}{
		{"id3v2", append([]byte("ID3\x04\x00\x00\x00\x00\x00\x00"), make([]byte, 32)...), true},
		{"frame-sync-fffb", append([]byte{0xFF, 0xFB, 0x90, 0x64}, make([]byte, 32)...), true},
		{"frame-sync-fff3", append([]byte{0xFF, 0xF3, 0x80, 0x00}, make([]byte, 32)...), true},
		{"ogg", append([]byte("OggS\x00\x02"), make([]byte, 32)...), false},
		{"plain-text", []byte("hello world this is not audio at"), false},
		{"short", []byte{0xFF, 0xFB}, false},
		{"almost-sync", append([]byte{0xFF, 0x0B, 0x90, 0x64}, make([]byte, 32)...), false},
	}
	for _, c := range cases {
		p := filepath.Join(dir, c.name+".mp3")
		if err := os.WriteFile(p, c.data, 0o644); err != nil {
			t.Fatal(err)
		}
		if got := IsMp3(p); got != c.want {
			t.Errorf("IsMp3(%s) = %v, want %v", c.name, got, c.want)
		}
	}
	// Missing file → false, no panic.
	if IsMp3(filepath.Join(dir, "nope.mp3")) {
		t.Error("missing file sniffed as mp3")
	}
}

func TestMixdownStereo(t *testing.T) {
	// Stereo pairs average to mono.
	in := []int16{100, 200, -100, -200, 300, 300}
	out := mixdownStereo(in)
	if len(out) != 3 {
		t.Fatalf("len = %d", len(out))
	}
	if out[0] != 150 || out[1] != -150 || out[2] != 300 {
		t.Fatalf("mixed = %v", out)
	}
	// Odd-length input (half frame) drops the dangling sample.
	in2 := []int16{100, 200, 50}
	out2 := mixdownStereo(in2)
	if len(out2) != 1 || out2[0] != 150 {
		t.Fatalf("odd mixed = %v", out2)
	}
}

func TestResampleLinear(t *testing.T) {
	// Identity: same rate copies.
	in := make([]int16, 64)
	for i := range in {
		in[i] = int16(i)
	}
	out := resampleLinear(in, 48000, 48000)
	if len(out) != len(in) {
		t.Fatalf("identity len = %d", len(out))
	}

	// 2x upsample doubles length.
	out2 := resampleLinear(in, 24000, 48000)
	if len(out2) != 2*len(in) {
		t.Fatalf("upsample len = %d, want %d", len(out2), 2*len(in))
	}

	// Downsampling halves.
	out3 := resampleLinear(in, 48000, 24000)
	if len(out3) != len(in)/2 {
		t.Fatalf("downsample len = %d, want %d", len(out3), len(in)/2)
	}

	// Degenerate rates passthrough unchanged.
	out4 := resampleLinear(in, 0, 48000)
	if len(out4) != len(in) {
		t.Fatalf("degenerate len = %d", len(out4))
	}
}

func mp3Fixture(t *testing.T) string {
	t.Helper()
	ff, err := exec.LookPath("ffmpeg")
	if err != nil {
		t.Skip("ffmpeg unavailable — MP3 decode fixture not generated")
	}
	p := filepath.Join(t.TempDir(), "tone.mp3")
	cmd := exec.Command(ff, "-y", "-f", "lavfi", "-i",
		"sine=frequency=440:duration=1",
		"-ar", "44100", "-ac", "2", "-b:a", "128k", p)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Skipf("ffmpeg failed: %v: %s", err, out)
	}
	return p
}

func TestDecodeMp3(t *testing.T) {
	p := mp3Fixture(t)
	if !IsMp3(p) {
		t.Fatal("fixture not sniffed as mp3")
	}
	pcm, err := decodeMp3(p)
	if err != nil {
		t.Fatalf("decodeMp3: %v", err)
	}
	// 1 second of mono 48 kHz ≈ 48000 samples (frame boundaries make
	// it approximate — require the right ballpark).
	if n := len(pcm); n < 40000 || n > 56000 {
		t.Fatalf("sample count = %d", n)
	}
	// A 440 Hz sine has real energy: not all silence.
	maxAmp := int16(0)
	for _, s := range pcm {
		if s > maxAmp {
			maxAmp = s
		}
	}
	if maxAmp < 1000 {
		t.Fatalf("fixture decodes near-silent (max %d)", maxAmp)
	}
}

func TestPlayMediaMp3(t *testing.T) {
	p := mp3Fixture(t)
	e := newTestEngineForPlayer(t)
	if err := e.PlayMedia("acct", "chat", "m1", p); err != nil {
		t.Fatalf("PlayMedia(mp3): %v", err)
	}
	// Simulate the device: playing=true, as a speaker would have set it
	// (headless machines have no backend — HasAudio false is honest).
	p2 := e.player()
	p2.mu.Lock()
	p2.playing = true
	p2.mu.Unlock()
	st := e.MediaState()
	if !st.Playing || st.MsgID != "m1" || st.AccountID != "acct" {
		t.Fatalf("state = %+v", st)
	}
	if st.Duration < 0.8 || st.Duration > 1.2 {
		t.Fatalf("duration = %v", st.Duration)
	}
	// The decode path fed real PCM: pulling 200 ms advances position.
	buf := make([]int16, 4800)
	p2.fill(buf)
	p2.fill(buf)
	if st2 := e.MediaState(); st2.Position < 0.15 || st2.Position > 0.25 {
		t.Fatalf("after 200ms of fill: position %.3f", st2.Position)
	}
	e.StopMedia()

	// Non-audio file stays rejected (honest error).
	txt := filepath.Join(t.TempDir(), "x.txt")
	if err := os.WriteFile(txt, []byte("not audio"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := e.PlayMedia("acct", "chat", "m2", txt); err == nil {
		t.Fatal("plain text accepted as playable")
	}
}

func TestIsInAppPlayable(t *testing.T) {
	dir := t.TempDir()
	mp3 := filepath.Join(dir, "a.mp3")
	if err := os.WriteFile(mp3, append([]byte("ID3\x04\x00"), make([]byte, 32)...), 0o644); err != nil {
		t.Fatal(err)
	}
	if !IsInAppPlayable(mp3) {
		t.Fatal("mp3 not in-app playable")
	}
	txt := filepath.Join(dir, "a.txt")
	if err := os.WriteFile(txt, []byte("nope"), 0o644); err != nil {
		t.Fatal(err)
	}
	if IsInAppPlayable(txt) {
		t.Fatal("text file in-app playable")
	}
}
