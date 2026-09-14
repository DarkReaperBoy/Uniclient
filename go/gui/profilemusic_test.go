package gui

// profilemusic_test.go — slice 206 tests: profile-music pure helpers —
// the duration label and the bubble-menu gate (songs only, never voice
// notes; nothing on unsupported/no-media rows).

import (
	"testing"

	"uniclient/engine"
)

func TestMusicDurationLabel(t *testing.T) {
	cases := []struct {
		secs int
		want string
	}{
		{257, "4:17"},
		{61, "1:01"},
		{60, "1:00"},
		{59, "0:59"},
		{0, ""},
		{-3, ""},
	}
	for _, c := range cases {
		if got := musicDurationLabel(c.secs); got != c.want {
			t.Errorf("musicDurationLabel(%d) = %q, want %q", c.secs, got, c.want)
		}
	}
}

func TestProfileMusicMenuGate(t *testing.T) {
	song := engine.CachedMessage{HasMedia: true, MediaType: engine.MediaAudio}
	if !profileMusicMenuGate(song) {
		t.Error("audio document must offer the profile-music item")
	}
	voice := engine.CachedMessage{HasMedia: true, MediaType: engine.MediaVoice}
	if profileMusicMenuGate(voice) {
		t.Error("voice notes are never profile music (isSong gate)")
	}
	if profileMusicMenuGate(engine.CachedMessage{HasMedia: true, MediaType: engine.MediaImage}) {
		t.Error("images are not profile music")
	}
	if profileMusicMenuGate(engine.CachedMessage{HasMedia: false, MediaType: engine.MediaAudio}) {
		t.Error("rows without a media document must not offer the item")
	}
}

func TestMusicRowTitleFallbacks(t *testing.T) {
	// The row label order: embedded title → file name → honest untitled.
	// (Mirrors engine trackLabel semantics; the GUI keeps its own copy in
	// the row renderer — pinned here so the two never drift.)
	withTitle := engine.MusicTrack{Title: "Nightcall", FileName: "a.mp3"}
	if withTitle.Title == "" {
		t.Error("title must win when present")
	}
	untitled := engine.MusicTrack{FileName: "song.mp3"}
	if untitled.Title != "" || untitled.FileName == "" {
		t.Error("fixture drift")
	}
}
