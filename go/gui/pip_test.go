package gui

import (
	"testing"
	"time"

	"uniclient/engine"
)

func TestPipSizeFitsViewport(t *testing.T) {
	cases := []struct {
		name                 string
		vpW, vpH, vidW, vidH int
		targetW              int
		wantW, wantH         int
	}{
		{"typical desktop", 1200, 800, 1280, 720, 400, 400, 225},
		{"target below the floor rises to 1/6", 1200, 800, 1280, 720, 100, 200, 112},
		{"target above the ceiling drops to 1/3", 1200, 800, 1280, 720, 1000, 400, 225},
		{"small window", 300, 200, 1280, 720, 100, 100, 56},
		{"short viewport caps height", 1200, 200, 720, 1280, 400, 56, 100},
		{"zero-size clip falls back to 16:9", 1200, 800, 0, 0, 320, 320, 180},
		{"negative viewport yields no panel", -1, -1, 1280, 720, 320, 0, 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			w, h := pipSize(c.targetW, c.vpW, c.vpH, c.vidW, c.vidH)
			if w != c.wantW || h != c.wantH {
				t.Errorf("pipSize(%d, %d, %d, %d, %d) = (%d, %d), want (%d, %d)",
					c.targetW, c.vpW, c.vpH, c.vidW, c.vidH, w, h, c.wantW, c.wantH)
			}
			if w > 0 && (w > c.vpW || h > c.vpH) && c.vpW > 0 && c.vpH > 0 {
				t.Errorf("panel %dx%d does not fit viewport %dx%d", w, h, c.vpW, c.vpH)
			}
		})
	}
}

func TestPipClampKeepsPanelOnScreen(t *testing.T) {
	cases := []struct {
		name         string
		x, y, w, h   int
		vpW, vpH     int
		wantX, wantY int
	}{
		{"inside stays put", 100, 200, 200, 100, 800, 600, 100, 200},
		{"top-left overflow", -50, -50, 200, 100, 800, 600, 0, 0},
		{"bottom-right overflow", 700, 550, 200, 100, 800, 600, 600, 500},
		{"far past both edges", 5000, 5000, 200, 100, 800, 600, 600, 500},
		{"panel wider than the viewport pins to 0", -40, 30, 900, 100, 800, 600, 0, 30},
		{"degenerate viewport", 10, 10, 200, 100, 0, 0, 0, 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			x, y := pipClamp(c.x, c.y, c.w, c.h, c.vpW, c.vpH)
			if x != c.wantX || y != c.wantY {
				t.Errorf("pipClamp(%d,%d,%d,%d,%d,%d) = (%d,%d), want (%d,%d)",
					c.x, c.y, c.w, c.h, c.vpW, c.vpH, x, y, c.wantX, c.wantY)
			}
		})
	}
}

func TestPipDragMovesAndSticksToEdges(t *testing.T) {
	originX, originY := 500, 400

	x, y := pipPosAfterDrag(originX, originY, -200, -150, 200, 100, 1200, 800)
	if x != 300 || y != 250 {
		t.Fatalf("modest drag = (%d,%d), want (300,250)", x, y)
	}

	x, y = pipPosAfterDrag(originX, originY, -9999, -9999, 200, 100, 1200, 800)
	if x != 0 || y != 0 {
		t.Errorf("up-left overflow = (%d,%d), want (0,0)", x, y)
	}

	x, y = pipPosAfterDrag(originX, originY, 9999, 9999, 200, 100, 1200, 800)
	if x != 1000 || y != 700 {
		t.Errorf("down-right overflow = (%d,%d), want (1000,700)", x, y)
	}

	x, y = pipPosAfterDrag(900, 700, 0, 0, 400, 300, 800, 600)
	if x != 400 || y != 300 {
		t.Errorf("shrunken viewport = (%d,%d), want (400,300)", x, y)
	}
}

func TestPipLifecycle(t *testing.T) {
	a := &App{}

	if a.pip != nil {
		t.Fatal("pip state must start nil")
	}

	a.startPip("msg1", 1280, 720, 1200, 800)
	if a.pip == nil {
		t.Fatal("startPip left the state nil")
	}
	if a.pip.msgID != "msg1" {
		t.Errorf("msgID = %q, want msg1", a.pip.msgID)
	}
	if a.pip.w <= 0 || a.pip.h <= 0 {
		t.Fatalf("panel size = %dx%d, want a positive box", a.pip.w, a.pip.h)
	}
	wantX, wantY := pipClamp(1200-a.pip.w-16, 800-a.pip.h-16, a.pip.w, a.pip.h, 1200, 800)
	if a.pip.x != wantX || a.pip.y != wantY {
		t.Errorf("initial position = (%d,%d), want (%d,%d)", a.pip.x, a.pip.y, wantX, wantY)
	}
	if x, y := pipClamp(a.pip.x, a.pip.y, a.pip.w, a.pip.h, 1200, 800); x != a.pip.x || y != a.pip.y {
		t.Errorf("initial position (%d,%d) is outside the viewport", a.pip.x, a.pip.y)
	}

	a.pip.x, a.pip.y = 64, 96
	a.startPip("msg2", 640, 360, 1200, 800)
	if a.pip.msgID != "msg2" {
		t.Errorf("msgID after re-open = %q, want msg2", a.pip.msgID)
	}
	if a.pip.x != 64 || a.pip.y != 96 {
		t.Errorf("position jumped to (%d,%d) on a clip switch, want (64,96)", a.pip.x, a.pip.y)
	}

	h264Players.pause("msg2")
	frozen := h264Players.elapsed("msg2")
	time.Sleep(10 * time.Millisecond)
	if got := h264Players.elapsed("msg2"); got != frozen {
		t.Errorf("playhead advanced while paused: %v -> %v", frozen, got)
	}

	a.stopPip()
	if a.pip != nil {
		t.Errorf("stopPip left %+v", a.pip)
	}
	a.stopPip()
	if a.pip != nil {
		t.Error("second stopPip resurrected the state")
	}
}

func TestPipEntryNeedsAVideo(t *testing.T) {
	video := engine.SharedMediaItem{MsgID: "v", MediaType: engine.MediaVideo, LocalPath: "/d/v.mp4"}
	note := engine.SharedMediaItem{MsgID: "n", MediaType: engine.MediaVideoNote, LocalPath: "/d/n.mp4"}
	photo := engine.SharedMediaItem{MsgID: "p", MediaType: engine.MediaImage, LocalPath: "/d/p.jpg"}

	if !pipEligible(video) {
		t.Error("a downloaded video must be PiP-eligible")
	}
	if !pipEligible(note) {
		t.Error("a downloaded round note must be PiP-eligible")
	}
	if pipEligible(photo) {
		t.Error("a photo must not open a video panel")
	}
	if pipEligible(engine.SharedMediaItem{MsgID: "x", MediaType: engine.MediaVideo}) {
		t.Error("an undownloaded video must not open an empty panel")
	}
}
