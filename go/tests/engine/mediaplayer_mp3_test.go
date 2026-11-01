package tests

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	. "uniclient/engine"
)

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
	if IsMp3(filepath.Join(dir, "nope.mp3")) {
		t.Error("missing file sniffed as mp3")
	}
}

func TestMixdownStereo(t *testing.T) {
	in := []int16{100, 200, -100, -200, 300, 300}
	out := MixdownStereo(in)
	if len(out) != 3 {
		t.Fatalf("len = %d", len(out))
	}
	if out[0] != 150 || out[1] != -150 || out[2] != 300 {
		t.Fatalf("mixed = %v", out)
	}
	in2 := []int16{100, 200, 50}
	out2 := MixdownStereo(in2)
	if len(out2) != 1 || out2[0] != 150 {
		t.Fatalf("odd mixed = %v", out2)
	}
}

func TestResampleLinear(t *testing.T) {
	in := make([]int16, 64)
	for i := range in {
		in[i] = int16(i)
	}
	out := ResampleLinear(in, 48000, 48000)
	if len(out) != len(in) {
		t.Fatalf("identity len = %d", len(out))
	}

	out2 := ResampleLinear(in, 24000, 48000)
	if len(out2) != 2*len(in) {
		t.Fatalf("upsample len = %d, want %d", len(out2), 2*len(in))
	}

	out3 := ResampleLinear(in, 48000, 24000)
	if len(out3) != len(in)/2 {
		t.Fatalf("downsample len = %d, want %d", len(out3), len(in)/2)
	}

	out4 := ResampleLinear(in, 0, 48000)
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
	pcm, err := DecodeMp3(p)
	if err != nil {
		t.Fatalf("decodeMp3: %v", err)
	}
	if n := len(pcm); n < 40000 || n > 56000 {
		t.Fatalf("sample count = %d", n)
	}
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
	p2 := e.Player()
	detachDevice(t, p2)
	st := e.MediaState()
	if !st.Playing || st.MsgID != "m1" || st.AccountID != "acct" {
		t.Fatalf("state = %+v", st)
	}
	if st.Duration < 0.8 || st.Duration > 1.2 {
		t.Fatalf("duration = %v", st.Duration)
	}
	buf := make([]int16, 4800)
	p2.ForTestFill(buf)
	p2.ForTestFill(buf)
	if st2 := e.MediaState(); st2.Position < 0.15 || st2.Position > 0.25 {
		t.Fatalf("after 200ms of fill: position %.3f", st2.Position)
	}
	e.StopMedia()

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
