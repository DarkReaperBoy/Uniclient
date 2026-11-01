package gui

import (
	"errors"
	"fmt"
	"testing"

	"uniclient/aacaud"
	"uniclient/engine"
)

func TestVideoAudioMine(t *testing.T) {
	playing := engine.PlaybackState{MsgID: "m1", Playing: true}
	paused := engine.PlaybackState{MsgID: "m1", Paused: true}
	other := engine.PlaybackState{MsgID: "music9", Playing: true}
	idle := engine.PlaybackState{}

	cases := []struct {
		name string
		st   engine.PlaybackState
		msg  string
		want bool
	}{
		{"ours playing", playing, "m1", true},
		{"ours paused", paused, "m1", true},
		{"someone else's track", other, "m1", false},
		{"nothing playing", idle, "m1", false},
		{"empty msg id is never ours", playing, "", false},
		{"empty state", idle, "", false},
	}
	for _, c := range cases {
		if got := videoAudioMine(c.st, c.msg); got != c.want {
			t.Errorf("%s: videoAudioMine = %v, want %v", c.name, got, c.want)
		}
	}
}

func TestIsSilentVideoErr(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want bool
	}{
		{"nil", nil, false},
		{"direct ErrNoAudio", aacaud.ErrNoAudio, true},
		{"wrapped ErrNoAudio", fmt.Errorf("mp4: %w", aacaud.ErrNoAudio), true},
		{"wrapped twice", fmt.Errorf("media: %w", fmt.Errorf("mp4: %w", aacaud.ErrNoAudio)), true},
		{"unsupported (HE-AAC)", fmt.Errorf("mp4: %w", aacaud.ErrUnsupported), false},
		{"corrupt", fmt.Errorf("mp4: %w", aacaud.ErrCorrupt), false},
		{"unrelated", errors.New("boom"), false},
	}
	for _, c := range cases {
		if got := isSilentVideoErr(c.err); got != c.want {
			t.Errorf("%s: isSilentVideoErr = %v, want %v", c.name, got, c.want)
		}
	}
}

func TestVideoAudioShouldLoop(t *testing.T) {
	const dur = 1.0
	cases := []struct {
		name  string
		mine  bool
		video bool
		aud   bool
		aPlay bool
		aPaus bool
		pos   float64
		dur   float64
		want  bool
	}{
		{"wrap re-arms", true, true, true, false, false, 1.0, dur, true},
		{"still draining (inside slack)", true, true, true, false, false, dur - 0.02, dur, true},
		{"mid-clip no re-arm", true, true, true, false, false, 0.4, dur, false},
		{"not our track (music playing)", false, true, true, false, false, 1.0, dur, false},
		{"picture stopped too: video ended, stays ended", true, false, true, false, false, 1.0, dur, false},
		{"no device to re-arm", true, true, false, false, false, 1.0, dur, false},
		{"audio still running", true, true, true, true, false, 1.0, dur, false},
		{"audio paused by the user — do not fight it", true, true, true, false, true, 1.0, dur, false},
		{"no duration (state not ready)", true, true, true, false, false, 1.0, 0, false},
		{"zero position with no duration", false, false, false, false, false, 0, 0, false},
	}
	for _, c := range cases {
		got := videoAudioShouldLoop(c.mine, c.video, c.aud, c.aPlay, c.aPaus, c.pos, c.dur)
		if got != c.want {
			t.Errorf("%s: videoAudioShouldLoop = %v, want %v", c.name, got, c.want)
		}
	}
}

func TestMediaVolumeSliderSources(t *testing.T) {
	a := &App{eng: &engine.Engine{}}

	if got := a.mediaVolume(); got != 1 {
		t.Errorf("default volume = %v, want 1 (unity before anything plays)", got)
	}
	for _, c := range []struct{ in, want float64 }{
		{0.4, 0.4},
		{0, 0},
		{0.75, 0.75},
		{9, 1},
		{-2, 0},
	} {
		a.setMediaVolume(c.in)
		if got := a.mediaVolume(); got != c.want {
			t.Errorf("setMediaVolume(%v) → read back %v, want %v", c.in, got, c.want)
		}
	}
}

func TestVideoAudioHelpersTolerateMissingEngine(t *testing.T) {
	a := &App{}
	a.videoAudioPlay("acct", "chat", "m1", "some.mp4")
	a.viewerVideoAudioPlay(engine.SharedMediaItem{MsgID: "m1", LocalPath: "x.mp4"})
	a.videoAudioPause("m1")
	a.videoAudioSeek("m1", 0.5)
	a.videoAudioLoop("m1")
	a.setMediaVolume(0.5)
	a.startVideoAudio("acct", "chat", "m1", "x.mp4")
	if got := a.mediaVolume(); got != 1 {
		t.Errorf("mediaVolume without engine = %v, want 1", got)
	}
	acct, chat := a.viewerIdent()
	if acct != "" || chat != "" {
		t.Errorf("viewerIdent without a viewer = (%q,%q), want empty", acct, chat)
	}
}
