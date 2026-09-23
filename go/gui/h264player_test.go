package gui

// Slice 220 — round video notes play INSIDE the chat bubble through the
// pure-Go h264vid pipeline (slice 219), which is what AyuGram/tdesktop do
// with video messages: the note is a circular, looping player in the
// conversation, not a link to a viewer.
//
// Tests lock the pure logic BEFORE the widgets: the tap state machine,
// the per-msg player cache (lifecycle, single-claim read guard, eviction
// stopping the decode goroutines), the one-shot "play inline when the
// download lands" marker that keeps round notes out of the system player,
// and the power-saving gate for the loop.

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"uniclient/engine"
	"uniclient/h264vid"
)

// parseRoundFixture parses a committed H.264 fixture into a real Video —
// index-only, so it is cheap enough to do inside tests.
func parseRoundFixture(t *testing.T) *h264vid.Video {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("..", "h264vid", "testdata", "round_video.mp4"))
	if err != nil {
		t.Skipf("h264vid fixture unavailable: %v", err)
	}
	v, err := h264vid.Parse(data)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	return v
}

// roundNoteFixture copies a committed H.264 fixture into a temp dir so the
// download-complete path sees a real, playable file.
func roundNoteFixture(t *testing.T) string {
	t.Helper()
	src := filepath.Join("..", "h264vid", "testdata", "round_video.mp4")
	data, err := os.ReadFile(src)
	if err != nil {
		t.Skipf("h264vid fixture unavailable: %v", err)
	}
	dst := filepath.Join(t.TempDir(), "note.mp4")
	if err := os.WriteFile(dst, data, 0o600); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
	return dst
}

func TestNoteTapAction(t *testing.T) {
	parsed := &h264PlayerState{parsed: true}
	playing := &h264PlayerState{parsed: true, playing: true}
	reading := &h264PlayerState{reading: true}
	failed := &h264PlayerState{failed: true}
	// parsed=false, reading=false: no parse started yet → kick one off.
	idle := &h264PlayerState{}

	cases := []struct {
		name       string
		p          *h264PlayerState
		downloaded bool
		want       noteAction
	}{
		{"missing file downloads first", nil, false, noteActionDownload},
		{"no player yet waits for the parse", nil, true, noteActionWait},
		{"parse in flight does not restart", reading, true, noteActionWait},
		{"idle entry waits (caller ensures the parse)", idle, true, noteActionWait},
		{"parsed and stopped plays", parsed, true, noteActionPlay},
		{"playing pauses", playing, true, noteActionPause},
		// §1.10: an undecodable note must fall through to the honest
		// viewer/system path rather than sit dead in the bubble.
		{"undecodable falls back to the viewer", failed, true, noteActionViewer},
		{"undecodable but not downloaded still downloads", failed, false, noteActionDownload},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := noteTapAction(c.p, c.downloaded); got != c.want {
				t.Errorf("noteTapAction(%v, downloaded=%v) = %v, want %v",
					c.p, c.downloaded, got, c.want)
			}
		})
	}
}

func TestH264PlayerCache(t *testing.T) {
	c := &h264PlayerCache{players: make(map[string]*h264Player)}

	p1, ok := c.get("m1")
	if !ok {
		t.Fatal("get returned no entry")
	}
	if n := c.len(); true {
		c.get("m1")
		if c.len() != n {
			t.Error("get created a second entry for the same msgID")
		}
	}
	if p1.parsed || p1.failed || p1.reading || p1.playing {
		t.Error("fresh player flags not zero")
	}
	if _, ok := c.peek("nope"); ok {
		t.Error("peek created an entry (peek must be read-only)")
	}

	// publish marks the video parsed and starts it playing.
	video := parseRoundFixture(t)
	c.publish("m1", "/tmp/a.mp4", video, true)
	t.Cleanup(func() { c.reset("m1") })
	if p, ok := c.get("m1"); !ok || !p.parsed || !p.playing || p.path != "/tmp/a.mp4" || p.video != video {
		t.Errorf("publish left parsed=%v playing=%v path=%q video=%v",
			p.parsed, p.playing, p.path, p.video)
	}

	// play/pause round trip preserves the playhead.
	c.pause("m1")
	if p, ok := c.get("m1"); !ok || p.playing {
		t.Error("pause left playing=true")
	}
	frozen := c.elapsed("m1")
	time.Sleep(15 * time.Millisecond)
	if got := c.elapsed("m1"); got != frozen {
		t.Errorf("elapsed advanced while paused: %v -> %v", frozen, got)
	}
	c.resume("m1")
	if p, ok := c.get("m1"); !ok || !p.playing {
		t.Error("resume left playing=false")
	}
	if c.elapsed("m1") < frozen {
		t.Errorf("elapsed went backwards across resume: %v < %v", c.elapsed("m1"), frozen)
	}

	// failParse pins the failed flag (viewer fallback, no re-parse churn).
	c.failParse("m2")
	if p, ok := c.get("m2"); !ok || !p.failed || p.parsed || p.reading {
		t.Errorf("failParse left failed=%v parsed=%v reading=%v",
			p.failed, p.parsed, p.reading)
	}

	// markReading guards concurrent reads: claim once, release once.
	if !c.markReading("m3") {
		t.Error("first markReading claim rejected")
	}
	if c.markReading("m3") {
		t.Error("second markReading claim accepted while in flight")
	}
	c.endReading("m3")
	if !c.markReading("m3") {
		t.Error("markReading after endReading rejected")
	}

	// reset clears every flag and drops the video.
	c.reset("m1")
	if p, ok := c.get("m1"); !ok || p.parsed || p.playing || p.video != nil || p.path != "" {
		t.Errorf("reset left parsed=%v playing=%v video=%v path=%q",
			p.parsed, p.playing, p.video, p.path)
	}

	// Prune: an oversized cache drops the old entries without panic.
	for i := 0; i < h264PlayerMax+8; i++ {
		if _, ok := c.get("bulk" + itoa(i)); !ok {
			t.Fatal("get after prune returned no entry")
		}
	}
	if _, ok := c.peek("m1"); ok {
		t.Error("oversized cache kept a stale entry")
	}
}

// TestPlayInlineOnDone: marking a round-note download makes completion
// play the file IN-CHAT instead of handing it to the system player
// (the slice-86 handoff must stay reserved for everything else).
func TestPlayInlineOnDone(t *testing.T) {
	path := roundNoteFixture(t)

	a := &App{}
	var opened []string
	openExternalAsync = func(target string, done func(error)) {
		opened = append(opened, target)
		if done != nil {
			done(nil)
		}
	}
	t.Cleanup(func() {
		openExternalAsync = func(string, func(error)) {}
		h264Players.reset("42")
	})

	a.setPlayOnDone("acct", "chat", "42", 0)
	a.onDownloadComplete(engine.DownloadCompleteEvent{
		AccountID: "acct", ChatID: "chat", MsgID: "42", Seq: 0, LocalPath: path,
	})
	if len(opened) != 0 {
		t.Fatalf("round note handed to the system player: %v", opened)
	}
	// One-shot: a redelivery must not restart playback.
	a.onDownloadComplete(engine.DownloadCompleteEvent{
		AccountID: "acct", ChatID: "chat", MsgID: "42", Seq: 0, LocalPath: path,
	})
	if a.consumePlayOnDone("acct", "chat", "42", 0) {
		t.Error("playOnDone mark survived a completion (not one-shot)")
	}

	// The async parse publishes a playing player; wait for it.
	deadline := time.Now().Add(10 * time.Second)
	for {
		p, have := h264Players.peek("42")
		if have && p.parsed && p.playing && p.player != nil && p.video != nil {
			break
		}
		if have && p.failed {
			t.Fatalf("round note failed to parse a known-good fixture")
		}
		if time.Now().After(deadline) {
			t.Fatalf("player never started playing (have=%v state: %+v)", have, p)
		}
		time.Sleep(10 * time.Millisecond)
	}

	// A second tap on a playing note pauses it, and the tap action now
	// says Pause rather than Play.
	p, _ := h264Players.peek("42")
	if act := noteTapAction(&p, true); act != noteActionPause {
		t.Fatalf("tap while playing = %v, want %v", act, noteActionPause)
	}
	h264Players.pause("42")
	p, _ = h264Players.peek("42")
	if act := noteTapAction(&p, true); act != noteActionPlay {
		t.Errorf("tap while paused = %v, want %v", act, noteActionPlay)
	}
}

// TestVideoNotePowerGate: the inline loop obeys the power-saving gate the
// stickers/emoji animations already use — force-all holds the frame.
func TestVideoNotePowerGate(t *testing.T) {
	if powerSavingBlocks(0, false, psClassVideo) {
		t.Error("video blocked with no flags and no force-all")
	}
	if !powerSavingBlocks(0, true, psClassVideo) {
		t.Error("force-all did not block the video loop")
	}
	if !powerSavingBlocks(psFlagGifsChat, false, psClassVideo) {
		t.Error("in-chat autoplaying-media flag did not block the loop")
	}
	if powerSavingBlocks(psFlagGifsPanel, false, psClassVideo) {
		t.Error("panel flag blocked the in-chat loop (panel bits are panel-scoped)")
	}
}
