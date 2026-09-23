package gui

// tests-first for slice 229 — row 281's GUI decisions and the streamed
// parse→publish path. What must be pinned: the eligibility filters (a
// wrong yes would open a stream we can never play; a wrong no silently
// reverts the feature), the audio-join guards (sound must never start
// behind a paused picture or on someone else's download), and a real
// end-to-end publish over fixture bytes through the LAZY parser.

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"uniclient/engine"
	"uniclient/h264vid"
)

func TestViewerMayStream(t *testing.T) {
	base := engine.SharedMediaItem{
		MsgID:     "m1",
		MediaType: engine.MediaVideo,
		FileName:  "clip.mp4",
		MimeType:  "video/mp4",
	}
	cases := []struct {
		name string
		mut  func(*engine.SharedMediaItem)
		want bool
	}{
		{"video, not local, .mp4 name", func(*engine.SharedMediaItem) {}, true},
		{"already downloaded → no stream", func(it *engine.SharedMediaItem) { it.LocalPath = "/tmp/x.mp4" }, false},
		{"not a video → no", func(it *engine.SharedMediaItem) { it.MediaType = engine.MediaImage }, false},
		{"odd name but video/mp4 mime → yes", func(it *engine.SharedMediaItem) { it.FileName = "blob" }, true},
		{"odd name, non-mp4 mime → no", func(it *engine.SharedMediaItem) {
			it.FileName = "blob"
			it.MimeType = "video/quicktime"
		}, false},
		{"round note counts as video", func(it *engine.SharedMediaItem) { it.MediaType = engine.MediaVideoNote }, true},
		{"empty everything but type", func(it *engine.SharedMediaItem) {
			it.FileName = ""
			it.MimeType = ""
		}, false},
	}
	for _, c := range cases {
		it := base
		c.mut(&it)
		if got := viewerMayStream(it); got != c.want {
			t.Errorf("%s: viewerMayStream = %v, want %v", c.name, got, c.want)
		}
	}
}

func TestStreamShouldJoinAudio(t *testing.T) {
	path := "/media/a1/full/m1_0.mp4"
	playing := h264PlayerState{parsed: true, playing: true, path: path, video: &h264vid.Video{}}
	paused := h264PlayerState{parsed: true, playing: false, path: path, video: &h264vid.Video{}}
	cases := []struct {
		name      string
		st        h264PlayerState
		have      bool
		localPath string
		want      bool
	}{
		{"active stream player, path matches", playing, true, path, true},
		{"no player at all", h264PlayerState{}, false, path, false},
		{"paused picture → sound must NOT start", paused, true, path, false},
		{"parse not finished yet", h264PlayerState{playing: true, path: path}, true, path, false},
		{"different path (not our stream)", playing, true, "/other/path.mp4", false},
		{"entry exists but no video", h264PlayerState{parsed: true, playing: true, path: path}, true, path, false},
	}
	for _, c := range cases {
		if got := streamShouldJoinAudio(c.st, c.have, c.localPath); got != c.want {
			t.Errorf("%s: streamShouldJoinAudio = %v, want %v", c.name, got, c.want)
		}
	}
}

// TestPublishStreamedClip drives the REAL row-281 path: fixture bytes
// (a fully downloaded file standing in for a stream section) through
// ParseSeek → cache publish, asserting the player is live and keyed by
// the canonical path the completion event will later carry.
func TestPublishStreamedClip(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("..", "h264vid", "testdata", "round_video.mp4"))
	if err != nil {
		t.Skipf("h264vid fixture missing: %v", err)
	}
	const msgID = "stream-publish-smoke"
	const path = "/media/a1/full/stream-publish-smoke_0.mp4"
	t.Cleanup(func() { h264Players.reset(msgID) })

	pl, err := publishStreamedClip(msgID, path, bytes.NewReader(data), int64(len(data)), true)
	if err != nil {
		t.Fatalf("publishStreamedClip: %v", err)
	}
	if pl == nil {
		t.Fatal("no player")
	}
	st, ok := h264Players.peek(msgID)
	if !ok {
		t.Fatal("cache has no entry after publish")
	}
	if !st.parsed || st.failed {
		t.Errorf("state parsed=%v failed=%v, want parsed", st.parsed, st.failed)
	}
	if st.path != path {
		t.Errorf("path = %q, want %q (the completion event's path — mismatch means a re-parse at completion)", st.path, path)
	}
	if st.video == nil || st.video.FrameCount <= 0 {
		t.Fatalf("video = %+v, want a parsed clip", st.video)
	}
	// Cleanup must stop the producer so the -race run does not keep a
	// goroutine writing the flags we just read.
	h264Players.reset(msgID)
}

// TestPublishStreamedClipRejectsBadSource: unusable inputs fail loudly
// (the caller's fallback runs) instead of publishing a broken player.
func TestPublishStreamedClipRejectsBadSource(t *testing.T) {
	data, _ := os.ReadFile(filepath.Join("..", "h264vid", "testdata", "round_video.mp4"))
	if len(data) == 0 {
		t.Skip("no fixture")
	}
	if _, err := publishStreamedClip("", "x.mp4", bytes.NewReader(data), int64(len(data)), false); err == nil {
		t.Error("empty msgID accepted")
	}
	if _, err := publishStreamedClip("m", "", bytes.NewReader(data), int64(len(data)), false); err == nil {
		t.Error("empty path accepted")
	}
	if _, err := publishStreamedClip("m", "x.mp4", bytes.NewReader(data), 0, false); err == nil {
		t.Error("zero size accepted")
	}
	if _, err := publishStreamedClip("m", "x.mp4", nil, 10, false); err == nil {
		t.Error("nil reader accepted")
	}
	if _, err := publishStreamedClip("m", "x.mp4", bytes.NewReader([]byte("definitely not an mp4")), 23, false); err == nil {
		t.Error("garbage bytes accepted — ParseSeek must fail for the fallback to run")
	}
}
