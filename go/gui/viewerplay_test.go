package gui

import (
	"testing"
	"time"

	"uniclient/engine"
)

func TestVideoSeekFrac(t *testing.T) {
	cases := []struct {
		name           string
		elapsed, total time.Duration
		want           float64
	}{
		{"start", 0, 10 * time.Second, 0},
		{"half", 5 * time.Second, 10 * time.Second, 0.5},
		{"end", 10 * time.Second, 10 * time.Second, 1},
		{"past end", 25 * time.Second, 10 * time.Second, 1},
		{"negative clock", -time.Second, 10 * time.Second, 0},
		{"no duration", time.Second, 0, 0},
		{"nothing at all", 0, 0, 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := videoSeekFrac(c.elapsed, c.total)
			if got != c.want {
				t.Errorf("videoSeekFrac(%v, %v) = %v, want %v", c.elapsed, c.total, got, c.want)
			}
		})
	}
}

func TestVideoTimes(t *testing.T) {
	cases := []struct {
		elapsed, total time.Duration
		wantEl, wantTo string
	}{
		{0, 42 * time.Second, "0:00", "0:42"},
		{65 * time.Second, 125 * time.Second, "1:05", "2:05"},
		{3661 * time.Second, 7325 * time.Second, "1:01:01", "2:02:05"},
		{-5 * time.Second, -time.Second, "0:00", "0:00"},
	}
	for _, c := range cases {
		el, to := videoTimes(c.elapsed, c.total)
		if el != c.wantEl || to != c.wantTo {
			t.Errorf("videoTimes(%v, %v) = (%q, %q), want (%q, %q)",
				c.elapsed, c.total, el, to, c.wantEl, c.wantTo)
		}
	}
}

func TestViewerCanPlayInApp(t *testing.T) {
	video := engine.SharedMediaItem{MsgID: "1", MediaType: engine.MediaVideo, LocalPath: "/dl/1.mp4"}
	note := engine.SharedMediaItem{MsgID: "2", MediaType: engine.MediaVideoNote, LocalPath: "/dl/2.mp4"}
	photo := engine.SharedMediaItem{MsgID: "3", MediaType: engine.MediaImage, LocalPath: "/dl/3.jpg"}
	notDownloaded := engine.SharedMediaItem{MsgID: "4", MediaType: engine.MediaVideo}
	otherContainer := engine.SharedMediaItem{MsgID: "5", MediaType: engine.MediaVideo, LocalPath: "/dl/5.webm"}
	uppercase := engine.SharedMediaItem{MsgID: "6", MediaType: engine.MediaVideo, LocalPath: "/dl/6.MP4"}

	cases := []struct {
		name string
		it   engine.SharedMediaItem
		want bool
	}{
		{"downloaded video", video, true},
		{"downloaded round note", note, true},
		{"photo is never a video", photo, false},
		{"missing file must download first", notDownloaded, false},
		{"foreign container", otherContainer, false},
		{"extension check is case-insensitive", uppercase, true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := viewerCanPlayInApp(c.it); got != c.want {
				t.Errorf("viewerCanPlayInApp(%+v) = %v, want %v", c.it, got, c.want)
			}
		})
	}
}

func TestPlayerCacheSeekRebasesPlayhead(t *testing.T) {
	video := parseRoundFixture(t)
	c := &h264PlayerCache{players: make(map[string]*h264Player)}
	t.Cleanup(func() { c.reset("v") })

	c.seek("nope", 0.5)
	if got := c.duration("nope"); got != 0 {
		t.Errorf("duration of an unknown message = %v, want 0", got)
	}
	if got := c.elapsed("nope"); got != 0 {
		t.Errorf("elapsed of an unknown message = %v, want 0", got)
	}

	c.publish("v", "/tmp/v.mp4", video, false)
	if got := c.duration("v"); got != video.Total {
		t.Fatalf("duration = %v, want %v", got, video.Total)
	}

	c.seek("v", 0.5)
	want := video.Total / 2
	got := c.elapsed("v")
	if got < want || got-want > 50*time.Millisecond {
		t.Errorf("elapsed after seek while playing = %v, want ~%v", got, want)
	}

	c.pause("v")
	c.seek("v", 0.25)
	want = video.Total / 4
	if got := c.elapsed("v"); got != want {
		t.Errorf("elapsed after seek while paused = %v, want exactly %v", got, want)
	}
	time.Sleep(12 * time.Millisecond)
	if got := c.elapsed("v"); got != want {
		t.Errorf("elapsed advanced while paused: %v, want %v", got, want)
	}

	c.seek("v", 99)
	if got := c.elapsed("v"); got != video.Total {
		t.Errorf("seek(99) = %v, want %v (clamped to the end)", got, video.Total)
	}
	c.seek("v", -1)
	if got := c.elapsed("v"); got != 0 {
		t.Errorf("seek(-1) = %v, want 0 (clamped to the start)", got)
	}

	empty := &h264Player{}
	if got := seekTarget(empty, 0.5); got != 0 {
		t.Errorf("seekTarget without metadata = %v, want 0", got)
	}
}
