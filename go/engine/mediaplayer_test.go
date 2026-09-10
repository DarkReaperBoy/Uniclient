package engine

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"uniclient/voice"
)

// The media player state machine: play → progress → pause/resume →
// speed scaling → completion → stop. The fill callback is driven
// directly — on machines without an audio device (headless CI/sandbox)
// the device would call it with 20 ms buffers; the state machine under
// test is identical. A real ffmpeg-encoded Opus file exercises the
// decode path end-to-end.

// ffmpegToneOgg encodes a real 2-second 440 Hz Opus file.
func ffmpegToneOgg(t *testing.T) string {
	t.Helper()
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg not available")
	}
	path := filepath.Join(t.TempDir(), "tone.ogg")
	cmd := exec.Command("ffmpeg", "-loglevel", "error", "-y",
		"-f", "lavfi", "-i", "sine=frequency=440:duration=2",
		"-ar", "48000", "-ac", "1", "-c:a", "libopus", "-b:a", "32k", path)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Skipf("ffmpeg encode failed: %v (%s)", err, out)
	}
	return path
}

func newTestEngineForPlayer(t *testing.T) *Engine {
	t.Helper()
	e := &Engine{}
	t.Cleanup(func() { e.StopMedia() })
	return e
}

// playLoaded decodes a real file via PlayMedia and then simulates the
// device: playing=true, as a speaker would have set it.
func playLoaded(t *testing.T, e *Engine, path string) *mediaPlayer {
	t.Helper()
	if err := e.PlayMedia("acct", "chat", "m1", path); err != nil {
		t.Fatalf("PlayMedia: %v", err)
	}
	p := e.player()
	p.mu.Lock()
	p.playing = true // the device layer would own this bit
	p.mu.Unlock()
	return p
}

func TestMediaPlayerPlayProgress(t *testing.T) {
	path := ffmpegToneOgg(t)
	e := newTestEngineForPlayer(t)

	if !IsOpusOgg(path) {
		t.Fatal("IsOpusOgg must accept a real ffmpeg opus file")
	}
	p := playLoaded(t, e, path)

	st := e.MediaState()
	if !st.Playing || st.Duration < 1.8 || st.Duration > 2.2 {
		t.Fatalf("state after play: %+v", st)
	}
	if st.MsgID != "m1" || st.AccountID != "acct" {
		t.Fatalf("identity not tracked: %+v", st)
	}

	buf := make([]int16, voice.SampleRate/10) // 100 ms
	p.fill(buf)
	p.fill(buf)
	st = e.MediaState()
	if st.Position < 0.15 || st.Position > 0.25 {
		t.Fatalf("after 200ms of fill: position %.3f", st.Position)
	}

	// Pause: fill must not advance and must emit silence.
	e.TogglePauseMedia()
	before := e.MediaState().Position
	for i := range buf {
		buf[i] = 12345
	}
	p.fill(buf)
	p.fill(buf)
	if e.MediaState().Position != before {
		t.Fatalf("paused fill advanced: %.3f → %.3f", before, e.MediaState().Position)
	}
	if buf[0] != 0 {
		t.Fatalf("paused fill must emit silence, got %d", buf[0])
	}

	// Resume.
	e.TogglePauseMedia()
	p.fill(buf)
	if e.MediaState().Position <= before {
		t.Fatal("resumed fill did not advance")
	}
}

func TestMediaPlayerNoDeviceIsHonest(t *testing.T) {
	path := ffmpegToneOgg(t)
	e := newTestEngineForPlayer(t)
	if err := e.PlayMedia("a", "c", "m", path); err != nil {
		t.Fatalf("PlayMedia: %v", err)
	}
	st := e.MediaState()
	// On a machine with speakers this is playing; on headless boxes the
	// honest state is: decoded, duration known, no device, not playing,
	// error recorded. Both are acceptable — the invariant is that we
	// never claim playing without a device.
	if st.Playing && !st.HasAudio {
		t.Fatalf("claiming playback without a device: %+v", st)
	}
	if st.Duration < 1.8 || st.Duration > 2.2 {
		t.Fatalf("decode happened regardless of device: %+v", st)
	}
}

func TestMediaPlayerSpeedAndCompletion(t *testing.T) {
	path := ffmpegToneOgg(t)
	e := newTestEngineForPlayer(t)
	p := playLoaded(t, e, path)

	// Speed ladder: 1 → 1.5 → 2 → 0.5 → 1.
	for _, want := range []float64{1.5, 2, 0.5, 1} {
		e.CycleMediaSpeed()
		if got := e.MediaState().Speed; got != want {
			t.Fatalf("speed cycle: got %v want %v", got, want)
		}
	}

	// At 2x, position advances twice as fast per output sample.
	e.CycleMediaSpeed() // 1.5
	e.CycleMediaSpeed() // 2
	pos0 := e.MediaState().Position
	buf := make([]int16, voice.SampleRate/10) // 100 ms output
	p.fill(buf)
	advanced := e.MediaState().Position - pos0
	if advanced < 0.18 || advanced > 0.24 { // ~200 ms source per 100 ms out
		t.Fatalf("2x fill advanced %.3fs, want ~0.2", advanced)
	}

	// Completion: fill until done.
	for i := 0; i < 200; i++ { // 20 s of output — plenty for a 2 s clip at 2x
		p.fill(buf)
		if !e.MediaState().Playing {
			break
		}
	}
	st := e.MediaState()
	if st.Playing {
		t.Fatal("playback must complete")
	}
	if st.Position < st.Duration-0.05 {
		t.Fatalf("completed position %.3f < duration %.3f", st.Position, st.Duration)
	}

	// Stop clears everything.
	e.StopMedia()
	st = e.MediaState()
	if st.Playing || st.MsgID != "" || st.Duration != 0 {
		t.Fatalf("stop must reset: %+v", st)
	}
}

func TestMediaPlayerRejectsNonOpus(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notaudio.txt")
	if err := os.WriteFile(path, []byte("definitely not ogg"), 0o600); err != nil {
		t.Fatal(err)
	}
	if IsOpusOgg(path) {
		t.Fatal("IsOpusOgg must reject non-ogg files")
	}
	e := newTestEngineForPlayer(t)
	if err := e.PlayMedia("a", "c", "m", path); err == nil {
		t.Fatal("PlayMedia must reject non-opus files")
	}
}

func TestMediaPlayerEmitsEvents(t *testing.T) {
	path := ffmpegToneOgg(t)
	e := newTestEngineForPlayer(t)

	events := make(chan PlaybackState, 16)
	e.SetEventCallback(func(data []byte) {
		var env struct {
			Type string          `json:"type"`
			Data json.RawMessage `json:"data"`
		}
		if json.Unmarshal(data, &env) != nil || env.Type != EventPlaybackState {
			return
		}
		var st PlaybackState
		if json.Unmarshal(env.Data, &st) == nil {
			select {
			case events <- st:
			default:
			}
		}
	})

	p := playLoaded(t, e, path)
	buf := make([]int16, voice.SampleRate/10)
	p.fill(buf)
	e.TogglePauseMedia()
	e.StopMedia()

	saw := 0
	deadline := time.After(2 * time.Second)
	for saw < 2 {
		select {
		case <-events:
			saw++
		case <-deadline:
			t.Fatalf("only %d playback_state events received, want ≥2", saw)
		}
	}
}
