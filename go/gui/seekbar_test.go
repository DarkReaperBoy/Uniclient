package gui

// Seek bar + music row subtitle (slice 185): pure logic — the pointer
// fraction mapping (clamping, degenerate widths) and the audio bubble's
// performer/duration/size subtitle composition.

import (
	"image"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"gioui.org/f32"
	"gioui.org/io/input"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/unit"

	"uniclient/engine"
)

func TestSeekFraction(t *testing.T) {
	cases := []struct {
		name       string
		px         float32
		width      int
		cur        float64
		want       float64
		wantCurPas bool
	}{
		{"mid", 50, 200, 0.0, 0.25, false},
		{"full", 200, 200, 0.0, 1.0, false},
		{"zero", 0, 200, 0.8, 0.0, false},
		{"over-clamps", 300, 200, 0.0, 1.0, false},
		{"negative-clamps", -20, 200, 0.5, 0.0, false},
		{"degenerate-width-passes-cur", 50, 0, 0.42, 0.42, true},
		{"degenerate-negative-width", 50, -1, 0.42, 0.42, true},
	}
	for _, c := range cases {
		got := seekFraction(c.px, c.width, c.cur)
		if c.wantCurPas && got != c.cur {
			t.Errorf("%s: degenerate width must pass current through, got %v", c.name, got)
		}
		if !c.wantCurPas && got != c.want {
			t.Errorf("%s: seekFraction(%v, %d, %v) = %v, want %v", c.name, c.px, c.width, c.cur, got, c.want)
		}
	}
}

func TestAudioSubLine(t *testing.T) {
	// Static (not playing): duration + size.
	s := audioSubLine("", 192, false, 0, 0, 4100000)
	if !strings.Contains(s, "3:12") {
		t.Errorf("static line missing duration: %q", s)
	}
	if !strings.Contains(s, "MB") {
		t.Errorf("static line missing size: %q", s)
	}
	if strings.Contains(s, "·  ·") {
		t.Errorf("double separator: %q", s)
	}

	// Playing: live elapsed/total replaces the static duration.
	s = audioSubLine("Rush", 192, true, 30, 192, 4100000)
	if !strings.HasPrefix(s, "Rush · ") {
		t.Errorf("performer must lead: %q", s)
	}
	if !strings.Contains(s, "0:30") || !strings.Contains(s, "3:12") {
		t.Errorf("live elapsed/total missing: %q", s)
	}

	// No size, no performer: just the duration.
	s = audioSubLine("", 65, false, 0, 0, 0)
	if s != "1:05" && s != "1:05 " {
		t.Errorf("bare line = %q", s)
	}

	// Zero duration honest empty.
	if got := audioSubLine("", 0, false, 0, 0, 0); got != "" && got != "0:00" {
		t.Errorf("zero-duration line = %q", got)
	}
}

// TestVoiceWaveformSeekWiring (slice 186): a press on the waveform strip
// while this message owns the player seeks the engine player to the
// pointer's fraction — and only when the message is the active playback
// (a finished/foreign waveform registers no input).
func TestVoiceWaveformSeekWiring(t *testing.T) {
	// A real 1 s Opus tone through the public PlayMedia (headless: no
	// device, but the PCM+duration load — everything seeking needs).
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg unavailable — decode fixture not generated")
	}
	path := filepath.Join(t.TempDir(), "tone.ogg")
	cmd := exec.Command("ffmpeg", "-loglevel", "error", "-y",
		"-f", "lavfi", "-i", "sine=frequency=440:duration=1",
		"-ar", "48000", "-ac", "1", "-c:a", "libopus", "-b:a", "32k", path)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Skipf("ffmpeg encode failed: %v (%s)", err, out)
	}
	e := &engine.Engine{}
	t.Cleanup(e.StopMedia)
	if err := e.PlayMedia("acct", "chat", "m1", path); err != nil {
		t.Fatalf("PlayMedia: %v", err)
	}
	if st := e.MediaState(); st.Duration < 0.8 || st.Duration > 1.2 {
		t.Fatalf("fixture duration = %v", st.Duration)
	}

	a := &App{ui: NewUI(), eng: e}
	a.wid.init()

	m := &engine.CachedMessage{AccountID: "acct", ChatID: "chat", MsgID: "m1", MediaType: engine.MediaVoice}

	var (
		r   input.Router
		ops op.Ops
	)
	gtx := layout.Context{
		Ops:         &ops,
		Source:      r.Source(),
		Constraints: layout.Exact(image.Pt(400, 100)),
		Metric:      unit.Metric{PxPerDp: 1, PxPerSp: 1},
	}
	render := func(seekable bool) {
		a.voiceWaveform(gtx, m, 0, 1, true, seekable)
	}

	// Frame 1 declares the handler.
	render(true)
	r.Frame(gtx.Ops)
	// Press at half the 150 px strip → seek to 0.5.
	r.Queue(
		pointer.Event{Kind: pointer.Press, Source: pointer.Mouse, Buttons: pointer.ButtonPrimary, Position: f32.Pt(75, 13)},
		pointer.Event{Kind: pointer.Release, Source: pointer.Mouse, Buttons: pointer.ButtonPrimary, Position: f32.Pt(75, 13)},
	)
	ops.Reset()
	render(true) // drains the press
	if pos := e.MediaState().Position; pos < 0.45 || pos > 0.55 {
		t.Fatalf("waveform press did not seek: position %.3f", pos)
	}

	// Non-active message: the strip never registers input — the press
	// would not move the player.
	r.Frame(gtx.Ops)
	r.Queue(
		pointer.Event{Kind: pointer.Press, Source: pointer.Mouse, Buttons: pointer.ButtonPrimary, Position: f32.Pt(120, 13)},
		pointer.Event{Kind: pointer.Release, Source: pointer.Mouse, Buttons: pointer.ButtonPrimary, Position: f32.Pt(120, 13)},
	)
	ops.Reset()
	render(false) // not seekable — no handler declared
	if pos := e.MediaState().Position; pos < 0.45 || pos > 0.55 {
		t.Fatalf("non-seekable waveform moved the player: %.3f", pos)
	}
	e.StopMedia()
}
