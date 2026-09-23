package engine

// tests-first for slice 224: in-app MP4/AAC audio and media volume — the
// engine half of parity row 276 (play/pause/seek already shipped in slice
// 221; volume is what is left).
//
// The MP4 fixtures are NOT generated here: they are the committed files in
// go/aacaud/testdata, whose SHA-256 digests and ffmpeg reference PCM are
// pinned over there. Reading them through a relative path is the same
// convention go/gui already uses for h264vid's fixtures, and it means a
// fixture regeneration breaks the decode tests that own it rather than
// silently changing what this test asserts.

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"

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

// rewindMediaForTest makes the test the only clock: it rewinds the playhead
// and claims playback without touching the device (same contract as
// detachDevice in mediaplayer_test.go).
func rewindMediaForTest(t *testing.T, p *mediaPlayer) {
	t.Helper()
	p.mu.Lock()
	p.pos = 0
	p.playing = true
	p.paused = false
	p.mu.Unlock()
}

// ── format sniff ─────────────────────────────────────────────────────────

func TestIsMp4(t *testing.T) {
	dir := t.TempDir()
	cases := []struct {
		name string
		data []byte
		want bool
	}{
		// ftyp box: 4-byte size, then "ftyp", then the brand.
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

// A format sniff must not claim a file is playable when it has no sound —
// IsInAppPlayable feeds the tap-to-play decision.
func TestIsInAppPlayableIncludesMp4(t *testing.T) {
	if !IsInAppPlayable(mp4Fixture(t, "note.mp4")) {
		t.Error("IsInAppPlayable(note.mp4) = false, want true")
	}
	// A non-media file must never claim playable: this feeds the tap
	// decision, and a false here means a dead button.
	p := filepath.Join(t.TempDir(), "x.txt")
	if err := os.WriteFile(p, []byte("not media"), 0o644); err != nil {
		t.Fatal(err)
	}
	if IsInAppPlayable(p) {
		t.Error("IsInAppPlayable(text) = true, want false")
	}
}

// ── decode: shapes the player's sink requires ────────────────────────────

// The device callback is mono 48 kHz, so every decode must land there —
// mono passes through, stereo mixes down, and both fixtures are already
// 48 kHz so the length must equal exactly duration × 48000.
func TestDecodeMp4AudioShapes(t *testing.T) {
	cases := []struct {
		file    string
		samples int // int16 count after downmix/resample
	}{
		{"note.mp4", voice.SampleRate},         // 1.0 s mono
		{"talk.mp4", voice.SampleRate * 3 / 2}, // 1.5 s stereo → mono
	}
	for _, c := range cases {
		t.Run(c.file, func(t *testing.T) {
			pcm, err := decodeMp4Audio(mp4Fixture(t, c.file))
			if err != nil {
				t.Fatalf("decodeMp4Audio: %v", err)
			}
			if len(pcm) != c.samples {
				t.Errorf("len = %d, want %d (duration × 48000)", len(pcm), c.samples)
			}
			// Real content, not a decoded-to-silence file.
			loud := 0
			for _, s := range pcm {
				if s > 1000 || s < -1000 {
					loud++
				}
			}
			if loud < 1000 {
				t.Errorf("only %d samples above ±1000 — decode produced near-silence", loud)
			}
			// Durations must be usable by the seek bar.
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

// A video with no audio track must fail loudly, not play silence: the GUI
// decides between inline playback and the system player on this error.
func TestDecodeMp4AudioRejectsVideoOnly(t *testing.T) {
	_, err := decodeMp4Audio(mp4Fixture(t, "silent.mp4"))
	if err == nil {
		t.Fatal("decodeMp4Audio(video-only) succeeded, want error")
	}
	if !errors.Is(err, aacaud.ErrNoAudio) {
		t.Errorf("err = %v, want wrapped aacaud.ErrNoAudio", err)
	}
}

// ── playback through the engine ──────────────────────────────────────────

func TestPlayMediaMp4(t *testing.T) {
	e := newTestEngineForPlayer(t)
	if err := e.PlayMedia("acct", "chat", "m1", mp4Fixture(t, "note.mp4")); err != nil {
		t.Fatalf("PlayMedia(mp4): %v", err)
	}
	p := e.player()
	detachDevice(t, p)
	st := e.MediaState()
	if !st.Playing || st.MsgID != "m1" || st.AccountID != "acct" {
		t.Fatalf("state = %+v", st)
	}
	if st.Duration < 0.95 || st.Duration > 1.05 {
		t.Fatalf("duration = %v, want ~1.0s", st.Duration)
	}
	// The decode path fed real PCM: pulling 200 ms advances the playhead.
	buf := make([]int16, 4800)
	p.fill(buf)
	p.fill(buf)
	if got := e.MediaState().Position; got < 0.15 || got > 0.25 {
		t.Fatalf("after 200ms of fill: position %.3f", got)
	}
	e.StopMedia()
}

// ── volume (row 276's remaining control) ─────────────────────────────────

func TestMediaVolumeScalesPlayback(t *testing.T) {
	e := newTestEngineForPlayer(t)
	if err := e.PlayMedia("acct", "chat", "m1", mp4Fixture(t, "note.mp4")); err != nil {
		t.Fatalf("PlayMedia: %v", err)
	}
	p := e.player()
	detachDevice(t, p)
	buf := make([]int16, 960) // 20 ms

	// Reference pull at unity gain.
	e.SetMediaVolume(1)
	rewindMediaForTest(t, p)
	p.fill(buf)
	full := append([]int16(nil), buf...)

	// Half volume must halve every sample, not merely "sound quieter".
	e.SetMediaVolume(0.5)
	if got := e.MediaState().Volume; got != 0.5 {
		t.Fatalf("Volume in state = %v, want 0.5", got)
	}
	rewindMediaForTest(t, p)
	for i := range buf {
		buf[i] = 0
	}
	p.fill(buf)
	for i := range buf {
		if want := full[i] / 2; buf[i] != want {
			t.Fatalf("half-volume sample[%d] = %d, want %d (unity was %d)",
				i, buf[i], want, full[i])
		}
	}

	// Mute is total silence — a slider that dips to zero must not leak.
	e.SetMediaVolume(0)
	rewindMediaForTest(t, p)
	for i := range buf {
		buf[i] = 12345
	}
	p.fill(buf)
	for i, s := range buf {
		if s != 0 {
			t.Fatalf("muted sample[%d] = %d, want 0", i, s)
		}
	}

	// THE regression this suite exists for: gain is applied to the OUTPUT,
	// never to the stored buffer. If fill scaled p.pcm in place, every
	// subsequent pull would get quieter — and the next track would start
	// at whatever volume the last one ended on.
	p.mu.Lock()
	stored := append([]int16(nil), p.pcm[:4800]...)
	p.mu.Unlock()
	e.SetMediaVolume(0.1)
	rewindMediaForTest(t, p)
	p.fill(buf)
	p.mu.Lock()
	after := append([]int16(nil), p.pcm[:4800]...)
	p.mu.Unlock()
	for i := range stored {
		if stored[i] != after[i] {
			t.Fatalf("fill mutated stored PCM at %d: %d → %d",
				i, stored[i], after[i])
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
	// A fresh player starts at unity — never silently muted.
	if got := (&Engine{}).player().gain; got != 1 {
		t.Errorf("default gain = %v, want 1", got)
	}
}

// Volume survives a track switch: stopLocked must not reset it, because a
// user who lowered the volume on one video expects the next to be quiet too.
func TestMediaVolumeSurvivesTrackSwitch(t *testing.T) {
	e := newTestEngineForPlayer(t) // nil config: runtime value is the only state
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

// ── persistence (a slider that forgets itself every launch is a fake) ────

func TestConfigMediaVolumeRoundTrip(t *testing.T) {
	cfg := utils.DefaultConfig()
	if got := cfg.MediaVolumeValue(); got != 1 {
		t.Errorf("default MediaVolume = %v, want 1 (nil = unset)", got)
	}
	// Explicit mute must survive: 0 stored is a deliberate choice, not
	// "unset", or a muted user comes back to a loud app after every restart.
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
	// Out-of-range values written by hand into the config file are clamped.
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
	e := &Engine{vault: v, config: &cfg}
	defer v.Close()

	want := 0.3
	if err := e.UpdateConfigFromBridge(&ConfigChanges{MediaVolume: &want}); err != nil {
		t.Fatalf("UpdateConfigFromBridge: %v", err)
	}
	if got := e.config.MediaVolumeValue(); got != 0.3 {
		t.Errorf("config MediaVolume = %v, want 0.3", got)
	}
	// A nil change must leave it alone (the documented nil = unchanged).
	if err := e.UpdateConfigFromBridge(&ConfigChanges{}); err != nil {
		t.Fatalf("UpdateConfigFromBridge(empty): %v", err)
	}
	if got := e.config.MediaVolumeValue(); got != 0.3 {
		t.Errorf("empty changes altered volume: %v", got)
	}
}
