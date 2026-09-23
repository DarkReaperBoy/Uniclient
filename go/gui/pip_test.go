package gui

// Slice 222 — picture-in-picture (parity row 279, the matrix's ONLY
// MISSING row): keep watching a video while you keep using the app.
//
// Scope, stated up front and honestly: Gio exposes no always-on-top
// window option on our platforms — the only such flag lives in Gio's
// macOS backend, which §1.2 bans — and Gio allows extra native windows
// only on linux and windows, never on Android (see
// separateWindowSupported). An OS window would therefore either sit
// BEHIND the main window (useless) or not exist at all on Android.
//
// So PiP is a draggable floating panel inside the app window: it stays
// visible over every surface, works on both first-class platforms
// including Android, and reports its deviation from an OS-level window
// rather than pretending to be one (§1.10).

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
		// Width target is clamped between a sixth and a third of the
		// window, then the height follows the clip's aspect ratio.
		{"typical desktop", 1200, 800, 1280, 720, 400, 400, 225},
		{"target below the floor rises to 1/6", 1200, 800, 1280, 720, 100, 200, 112},
		{"target above the ceiling drops to 1/3", 1200, 800, 1280, 720, 1000, 400, 225},
		{"small window", 300, 200, 1280, 720, 100, 100, 56},
		// A short viewport caps the HEIGHT, shrinking width with it —
		// otherwise the panel would overflow the window it floats in.
		{"short viewport caps height", 1200, 200, 720, 1280, 400, 56, 100},
		// Degenerate clip metadata falls back to 16:9 instead of
		// dividing by zero or producing a zero-height panel.
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
			// Invariant the renderer relies on: a panel always fits.
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

// TestPipDragMovesAndSticksToEdges: dragging applies the pointer delta
// to the panel origin and then clamps — the panel must never be dragged
// somewhere it cannot be reached again.
func TestPipDragMovesAndSticksToEdges(t *testing.T) {
	originX, originY := 500, 400

	// A modest drag lands where the delta says.
	x, y := pipPosAfterDrag(originX, originY, -200, -150, 200, 100, 1200, 800)
	if x != 300 || y != 250 {
		t.Fatalf("modest drag = (%d,%d), want (300,250)", x, y)
	}

	// Dragging far up-left sticks at the origin rather than escaping.
	x, y = pipPosAfterDrag(originX, originY, -9999, -9999, 200, 100, 1200, 800)
	if x != 0 || y != 0 {
		t.Errorf("up-left overflow = (%d,%d), want (0,0)", x, y)
	}

	// Dragging far down-right sticks at the far corner.
	x, y = pipPosAfterDrag(originX, originY, 9999, 9999, 200, 100, 1200, 800)
	if x != 1000 || y != 700 {
		t.Errorf("down-right overflow = (%d,%d), want (1000,700)", x, y)
	}

	// A viewport that shrank under the panel still clamps it inside.
	x, y = pipPosAfterDrag(900, 700, 0, 0, 400, 300, 800, 600)
	if x != 400 || y != 300 {
		t.Errorf("shrunken viewport = (%d,%d), want (400,300)", x, y)
	}
}

// TestPipLifecycle: opening adopts the clip and parks the panel in the
// bottom-right corner (the least intrusive spot), a second open switches
// clips without teleporting it, and closing clears it completely so no
// player is left rendering behind an invisible panel.
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
	// Parked bottom-right with a margin, and provably inside the window.
	wantX, wantY := pipClamp(1200-a.pip.w-16, 800-a.pip.h-16, a.pip.w, a.pip.h, 1200, 800)
	if a.pip.x != wantX || a.pip.y != wantY {
		t.Errorf("initial position = (%d,%d), want (%d,%d)", a.pip.x, a.pip.y, wantX, wantY)
	}
	if x, y := pipClamp(a.pip.x, a.pip.y, a.pip.w, a.pip.h, 1200, 800); x != a.pip.x || y != a.pip.y {
		t.Errorf("initial position (%d,%d) is outside the viewport", a.pip.x, a.pip.y)
	}

	// Move it, then switch clips: the position must survive (a viewer
	// navigating to the next video must not yank the panel around).
	a.pip.x, a.pip.y = 64, 96
	a.startPip("msg2", 640, 360, 1200, 800)
	if a.pip.msgID != "msg2" {
		t.Errorf("msgID after re-open = %q, want msg2", a.pip.msgID)
	}
	if a.pip.x != 64 || a.pip.y != 96 {
		t.Errorf("position jumped to (%d,%d) on a clip switch, want (64,96)", a.pip.x, a.pip.y)
	}

	// A frozen playhead must not advance while the panel exists but the
	// clip is paused (the panel re-arms from the cache, not its own clock).
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
	a.stopPip() // idempotent
	if a.pip != nil {
		t.Error("second stopPip resurrected the state")
	}
}

// TestPipEntryNeedsAVideo: the entry point refuses non-video items, so a
// photo can never open an empty floating panel.
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
