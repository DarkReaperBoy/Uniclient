package tests

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"testing"
	"time"
	. "uniclient/engine"

	"uniclient/audio"
	"uniclient/voice"
)

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

type pullDevice struct {
	mu   sync.Mutex
	fill func(out []int16)
}

func (d *pullDevice) StartMic() (<-chan []byte, error) { return nil, audio.ErrNoAudio }
func (d *pullDevice) StopMic()                         {}

func (d *pullDevice) StartPlayback(fill func(out []int16)) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.fill = fill
	return nil
}

func (d *pullDevice) StopPlayback() {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.fill = nil
}

func (d *pullDevice) Close() { d.StopPlayback() }

func (d *pullDevice) pull(out []int16) {
	d.mu.Lock()
	fill := d.fill
	d.mu.Unlock()
	if fill != nil {
		fill(out)
	}
}

func installDevice(t *testing.T, f func() (audio.Device, error)) {
	t.Helper()
	audio.SetDeviceFactory(f)
	t.Cleanup(func() { audio.SetDeviceFactory(nil) })
}

func pullPlayer(t *testing.T) *pullDevice {
	t.Helper()
	dev := &pullDevice{}
	installDevice(t, func() (audio.Device, error) { return dev, nil })
	return dev
}

func playLoaded(t *testing.T, e *Engine, path string) *pullDevice {
	t.Helper()
	dev := pullPlayer(t)
	if err := e.PlayMedia("acct", "chat", "m1", path); err != nil {
		t.Fatalf("PlayMedia: %v", err)
	}
	return dev
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

	buf := make([]int16, voice.SampleRate/10)
	p.pull(buf)
	p.pull(buf)
	st = e.MediaState()
	if st.Position < 0.15 || st.Position > 0.25 {
		t.Fatalf("after 200ms of fill: position %.3f", st.Position)
	}

	e.TogglePauseMedia()
	before := e.MediaState().Position
	for i := range buf {
		buf[i] = 12345
	}
	p.pull(buf)
	p.pull(buf)
	if e.MediaState().Position != before {
		t.Fatalf("paused fill advanced: %.3f → %.3f", before, e.MediaState().Position)
	}
	if buf[0] != 0 {
		t.Fatalf("paused fill must emit silence, got %d", buf[0])
	}

	e.TogglePauseMedia()
	p.pull(buf)
	if e.MediaState().Position <= before {
		t.Fatal("resumed fill did not advance")
	}
}

func TestMediaPlayerNoDeviceIsHonest(t *testing.T) {
	path := ffmpegToneOgg(t)
	e := newTestEngineForPlayer(t)
	installDevice(t, func() (audio.Device, error) { return nil, audio.ErrNoAudio })
	if err := e.PlayMedia("a", "c", "m", path); err != nil {
		t.Fatalf("PlayMedia: %v", err)
	}
	st := e.MediaState()
	if st.Playing && !st.HasAudio {
		t.Fatalf("claiming playback without a device: %+v", st)
	}
	if st.Playing {
		t.Fatalf("failed device open must not claim playback: %+v", st)
	}
	if st.Duration < 1.8 || st.Duration > 2.2 {
		t.Fatalf("decode happened regardless of device: %+v", st)
	}
}

func TestMediaPlayerSpeedAndCompletion(t *testing.T) {
	path := ffmpegToneOgg(t)
	e := newTestEngineForPlayer(t)
	p := playLoaded(t, e, path)

	for _, want := range []float64{1.5, 2, 0.5, 1} {
		e.CycleMediaSpeed()
		if got := e.MediaState().Speed; got != want {
			t.Fatalf("speed cycle: got %v want %v", got, want)
		}
	}

	e.CycleMediaSpeed()
	e.CycleMediaSpeed()
	pos0 := e.MediaState().Position
	buf := make([]int16, voice.SampleRate/10)
	p.pull(buf)
	advanced := e.MediaState().Position - pos0
	if advanced < 0.18 || advanced > 0.24 {
		t.Fatalf("2x fill advanced %.3fs, want ~0.2", advanced)
	}

	for i := 0; i < 200; i++ {
		p.pull(buf)
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
	p.pull(buf)
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

func TestMediaPlayerSeek(t *testing.T) {
	path := ffmpegToneOgg(t)
	e := newTestEngineForPlayer(t)

	if err := e.SeekMedia(0.5); err == nil {
		t.Fatal("SeekMedia with nothing loaded must error")
	}

	p := playLoaded(t, e, path)
	dur := e.MediaState().Duration

	if err := e.SeekMedia(0.5); err != nil {
		t.Fatalf("SeekMedia(0.5): %v", err)
	}
	if pos := e.MediaState().Position; pos < dur*0.45 || pos > dur*0.55 {
		t.Fatalf("after seek: position %.3f (dur %.3f)", pos, dur)
	}

	if err := e.SeekMedia(4); err != nil {
		t.Fatalf("SeekMedia(4): %v", err)
	}
	if pos := e.MediaState().Position; pos < dur*0.95 {
		t.Fatalf("over-seek not clamped: %.3f", pos)
	}
	if err := e.SeekMedia(-2); err != nil {
		t.Fatalf("SeekMedia(-2): %v", err)
	}
	if pos := e.MediaState().Position; pos > 0.01 {
		t.Fatalf("negative seek not clamped: %.3f", pos)
	}

	e.TogglePauseMedia()
	e.SeekMedia(0.75)
	st := e.MediaState()
	if !st.Paused {
		t.Fatal("seek while paused dropped the pause")
	}
	if st.Position < dur*0.7 || st.Position > dur*0.8 {
		t.Fatalf("paused seek position %.3f", st.Position)
	}

	e.TogglePauseMedia()
	buf := make([]int16, voice.SampleRate/10)
	for i := 0; i < 200 && e.MediaState().Playing; i++ {
		p.pull(buf)
	}
	st = e.MediaState()
	if st.Playing {
		t.Fatal("drain loop did not complete playback")
	}
	if st.Position < st.Duration-0.05 {
		t.Fatalf("completed position %.3f < duration %.3f", st.Position, st.Duration)
	}

	e.SeekMedia(0.3)
	st = e.MediaState()
	if !st.Playing {
		t.Fatal("seek after completion with a device must resume playback")
	}
	if st.Position < dur*0.25 || st.Position > dur*0.35 {
		t.Fatalf("resume position %.3f (dur %.3f)", st.Position, dur)
	}

	headless := newTestEngineForPlayer(t)
	installDevice(t, func() (audio.Device, error) { return nil, audio.ErrNoAudio })
	if err := headless.PlayMedia("a", "c", "m", path); err != nil {
		t.Fatalf("headless PlayMedia: %v", err)
	}
	if headless.MediaState().Playing {
		t.Fatal("headless play claimed a device")
	}
	if err := headless.SeekMedia(0.3); err != nil {
		t.Fatalf("headless SeekMedia: %v", err)
	}
	if headless.MediaState().Playing {
		t.Fatal("headless seek faked a Playing state (§1.10)")
	}

	e.StopMedia()
	if err := e.SeekMedia(0.5); err == nil {
		t.Fatal("SeekMedia after StopMedia must error")
	}
}
