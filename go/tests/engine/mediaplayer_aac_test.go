package tests

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
	. "uniclient/engine"

	"uniclient/aacaud"
	"uniclient/utils"
	"uniclient/voice"
)

func mp4Fixture(t *testing.T, name string) string {
	t.Helper()
	p := filepath.Join("..", "aacaud", "testdata", name)
	if _, err := os.Stat(p); err != nil {
		t.Skipf("aacaud testdata missing: %v", err)
	}
	return p
}

func TestIsMp4(t *testing.T) {
	dir := t.TempDir()
	cases := []struct {
		name string
		data []byte
		want bool
	}{
		{"mp4", append([]byte{0x00, 0x00, 0x00, 0x20}, []byte("ftypisom")...), true},
		{"mp4-dash", append([]byte{0x00, 0x00, 0x00, 0x1C}, []byte("ftypdash")...), true},
		{"ogg", []byte("OggS\x00\x02"), false},
		{"mp3-id3", []byte("ID3\x04\x00"), false},
		{"webm", []byte{0x1A, 0x45, 0xDF, 0xA3, 0x01, 0x02}, false},
		{"plain-text", []byte("hello world this is not a video file"), false},
		{"short", []byte{0x00, 0x00}, false},
		{"empty", nil, false},
	}
	for _, c := range cases {
		p := filepath.Join(dir, c.name+".mp4")
		if err := os.WriteFile(p, c.data, 0o644); err != nil {
			t.Fatal(err)
		}
		if got := IsMp4(p); got != c.want {
			t.Errorf("%s: IsMp4 = %v, want %v", c.name, got, c.want)
		}
	}
	if IsMp4(filepath.Join(dir, "does-not-exist.mp4")) {
		t.Error("IsMp4(nonexistent) = true, want false")
	}
}

func TestIsInAppPlayableIncludesMp4(t *testing.T) {
	if !IsInAppPlayable(mp4Fixture(t, "note.mp4")) {
		t.Error("IsInAppPlayable(note.mp4) = false, want true")
	}
	p := filepath.Join(t.TempDir(), "x.txt")
	if err := os.WriteFile(p, []byte("not media"), 0o644); err != nil {
		t.Fatal(err)
	}
	if IsInAppPlayable(p) {
		t.Error("IsInAppPlayable(text) = true, want false")
	}
}

func TestDecodeMp4AudioShapes(t *testing.T) {
	cases := []struct {
		file    string
		samples int
	}{
		{"note.mp4", voice.SampleRate},
		{"talk.mp4", voice.SampleRate * 3 / 2},
	}
	for _, c := range cases {
		t.Run(c.file, func(t *testing.T) {
			pcm, err := DecodeMp4Audio(mp4Fixture(t, c.file))
			if err != nil {
				t.Fatalf("decodeMp4Audio: %v", err)
			}
			if len(pcm) != c.samples {
				t.Errorf("len = %d, want %d (duration × 48000)", len(pcm), c.samples)
			}
			loud := 0
			for _, s := range pcm {
				if s > 1000 || s < -1000 {
					loud++
				}
			}
			if loud < 1000 {
				t.Errorf("only %d samples above ±1000 — decode produced near-silence", loud)
			}
			d := float64(len(pcm)) / float64(voice.SampleRate)
			want := 1.0
			if c.file == "talk.mp4" {
				want = 1.5
			}
			if d < want-0.05 || d > want+0.05 {
				t.Errorf("duration = %.3fs, want ~%.2fs", d, want)
			}
		})
	}
}

func TestDecodeMp4AudioRejectsVideoOnly(t *testing.T) {
	_, err := DecodeMp4Audio(mp4Fixture(t, "silent.mp4"))
	if err == nil {
		t.Fatal("decodeMp4Audio(video-only) succeeded, want error")
	}
	if !errors.Is(err, aacaud.ErrNoAudio) {
		t.Errorf("err = %v, want wrapped aacaud.ErrNoAudio", err)
	}
}

func TestPlayMediaMp4(t *testing.T) {
	e := newTestEngineForPlayer(t)
	dev := pullPlayer(t)
	if err := e.PlayMedia("acct", "chat", "m1", mp4Fixture(t, "note.mp4")); err != nil {
		t.Fatalf("PlayMedia(mp4): %v", err)
	}
	st := e.MediaState()
	if !st.Playing || st.MsgID != "m1" || st.AccountID != "acct" {
		t.Fatalf("state = %+v", st)
	}
	if st.Duration < 0.95 || st.Duration > 1.05 {
		t.Fatalf("duration = %v, want ~1.0s", st.Duration)
	}
	buf := make([]int16, 4800)
	dev.pull(buf)
	dev.pull(buf)
	if got := e.MediaState().Position; got < 0.15 || got > 0.25 {
		t.Fatalf("after 200ms of fill: position %.3f", got)
	}
	e.StopMedia()
}

func TestMediaVolumeScalesPlayback(t *testing.T) {
	e := newTestEngineForPlayer(t)
	dev := pullPlayer(t)
	if err := e.PlayMedia("acct", "chat", "m1", mp4Fixture(t, "note.mp4")); err != nil {
		t.Fatalf("PlayMedia: %v", err)
	}
	buf := make([]int16, 960)

	e.SetMediaVolume(1)
	e.SeekMedia(0)
	dev.pull(buf)
	full := append([]int16(nil), buf...)

	e.SetMediaVolume(0.5)
	if got := e.MediaState().Volume; got != 0.5 {
		t.Fatalf("Volume in state = %v, want 0.5", got)
	}
	e.SeekMedia(0)
	for i := range buf {
		buf[i] = 0
	}
	dev.pull(buf)
	for i := range buf {
		if want := full[i] / 2; buf[i] != want {
			t.Fatalf("half-volume sample[%d] = %d, want %d (unity was %d)",
				i, buf[i], want, full[i])
		}
	}

	e.SetMediaVolume(0)
	e.SeekMedia(0)
	for i := range buf {
		buf[i] = 12345
	}
	dev.pull(buf)
	for i, s := range buf {
		if s != 0 {
			t.Fatalf("muted sample[%d] = %d, want 0", i, s)
		}
	}

	e.SetMediaVolume(0.1)
	e.SeekMedia(0)
	dev.pull(buf)
	e.SetMediaVolume(1)
	e.SeekMedia(0)
	dev.pull(buf)
	for i := range buf {
		if buf[i] != full[i] {
			t.Fatalf("gain pulls mutated the stored signal at %d: %d → %d",
				i, full[i], buf[i])
		}
	}
	e.StopMedia()
}

func TestMediaVolumeClamps(t *testing.T) {
	e := newTestEngineForPlayer(t)
	for _, c := range []struct{ in, want float64 }{
		{-3, 0}, {0, 0}, {0.5, 0.5}, {1, 1}, {7, 1},
	} {
		e.SetMediaVolume(c.in)
		if got := e.MediaState().Volume; got != c.want {
			t.Errorf("SetMediaVolume(%v) → %v, want %v", c.in, got, c.want)
		}
	}
	if got := (&Engine{}).MediaState().Volume; got != 1 {
		t.Errorf("default gain = %v, want 1", got)
	}
}

func TestMediaVolumeSurvivesTrackSwitch(t *testing.T) {
	e := newTestEngineForPlayer(t)
	if err := e.PlayMedia("a", "c", "m1", mp4Fixture(t, "note.mp4")); err != nil {
		t.Fatalf("PlayMedia: %v", err)
	}
	e.SetMediaVolume(0.25)
	e.StopMedia()
	if err := e.PlayMedia("a", "c", "m2", mp4Fixture(t, "talk.mp4")); err != nil {
		t.Fatalf("PlayMedia(2): %v", err)
	}
	if got := e.MediaState().Volume; got != 0.25 {
		t.Errorf("volume after track switch = %v, want 0.25", got)
	}
	e.StopMedia()
}

func TestConfigMediaVolumeRoundTrip(t *testing.T) {
	cfg := utils.DefaultConfig()
	if got := cfg.MediaVolumeValue(); got != 1 {
		t.Errorf("default MediaVolume = %v, want 1 (nil = unset)", got)
	}
	for _, v := range []float64{0, 0.4, 1} {
		v := v
		cfg.MediaVolume = &v
		raw, err := json.Marshal(cfg)
		if err != nil {
			t.Fatal(err)
		}
		var got utils.AppConfig
		if err := json.Unmarshal(raw, &got); err != nil {
			t.Fatal(err)
		}
		if g := got.MediaVolumeValue(); g != v {
			t.Errorf("round-trip %v → %v", v, g)
		}
	}
	hi, lo := 9.0, -2.0
	cfg.MediaVolume = &hi
	if got := cfg.MediaVolumeValue(); got != 1 {
		t.Errorf("MediaVolume(9) = %v, want clamped to 1", got)
	}
	cfg.MediaVolume = &lo
	if got := cfg.MediaVolumeValue(); got != 0 {
		t.Errorf("MediaVolume(-2) = %v, want clamped to 0", got)
	}
}

func TestConfigChangesMediaVolumeApplies(t *testing.T) {
	v, err := utils.CreateVault(filepath.Join(t.TempDir(), "vault.db"), "test")
	if err != nil {
		t.Fatalf("CreateVault: %v", err)
	}
	cfg := utils.DefaultConfig()
	e := New(nil, v, &cfg)
	defer v.Close()

	want := 0.3
	if err := e.UpdateConfigFromBridge(&ConfigChanges{MediaVolume: &want}); err != nil {
		t.Fatalf("UpdateConfigFromBridge: %v", err)
	}
	if got := e.ForTestConfig().MediaVolumeValue(); got != 0.3 {
		t.Errorf("config MediaVolume = %v, want 0.3", got)
	}
	if err := e.UpdateConfigFromBridge(&ConfigChanges{}); err != nil {
		t.Fatalf("UpdateConfigFromBridge(empty): %v", err)
	}
	if got := e.ForTestConfig().MediaVolumeValue(); got != 0.3 {
		t.Errorf("empty changes altered volume: %v", got)
	}
}
