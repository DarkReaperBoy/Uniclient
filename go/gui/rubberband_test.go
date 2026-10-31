package gui

import (
	"image"
	"testing"

	"gioui.org/f32"
	"gioui.org/io/input"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op"

	"uniclient/engine"
)

// Rubber-band selection (slice 84, AyuGram §3): rect math + row hit tests.

// TestRubberBandGestureIsPerWindow pins the R23 fix: the overlay renders in
// BOTH window branches (layoutChatView ← layoutMain/separateChatView), so the
// gesture state must live on the App. Package-level state let another
// window's frame (a) kill an in-flight drag via the selOn early-exit and
// (b) paint this window's selection rectangle on the other viewport.
func TestRubberBandGestureIsPerWindow(t *testing.T) {
	// Window A: chat in selection mode, user starts a rubber-band drag.
	var ra input.Router
	var opsA op.Ops
	a := &App{ui: NewUI(), rowBounds: map[int]image.Rectangle{}, listTop: 100}
	gtxA := layout.Context{Ops: &opsA, Source: ra.Source(), Constraints: layout.Exact(image.Pt(400, 400))}
	fOn := frame{selOn: true, messages: []engine.CachedMessage{{MsgID: "m0"}, {MsgID: "m1"}}}
	a.rubberBandOverlay(gtxA, fOn, image.Pt(400, 400)) // declare handlers
	ra.Frame(gtxA.Ops)
	ra.Queue(pointer.Event{Kind: pointer.Press, Source: pointer.Mouse, Buttons: pointer.ButtonPrimary, Position: f32.Pt(50, 40)}) // pane y=140: inside row 0
	a.rubberBandOverlay(gtxA, fOn, image.Pt(400, 400))                                                                            // deliver Press
	if !a.rubberOn {
		t.Fatal("gesture did not start on press")
	}

	// Window B: another chat, NOT in selection mode, renders a frame (a
	// typing indicator, toast, incoming message — anything). Its overlay's
	// early-exit must not touch window A's in-flight gesture.
	var rb input.Router
	var opsB op.Ops
	b := &App{ui: NewUI(), rowBounds: map[int]image.Rectangle{}}
	gtxB := layout.Context{Ops: &opsB, Source: rb.Source(), Constraints: layout.Exact(image.Pt(400, 400))}
	b.rubberBandOverlay(gtxB, frame{}, image.Pt(400, 400))
	rb.Frame(gtxB.Ops)
	b.rubberBandOverlay(gtxB, frame{}, image.Pt(400, 400))
	if !a.rubberOn {
		t.Fatal("cross-window bleed: window B's frame killed window A's rubber-band drag (B-47 class, R23)")
	}
	// ...and B never picked up A's gesture (the phantom rectangle):
	if b.rubberOn {
		t.Fatal("cross-window bleed: window B adopted window A's selection rectangle (B-47 class, R23)")
	}

	// A's drag continues tracking on A alone.
	// Gio synthesizes Drag delivery from Move events while pressed
	// (pointer.Drag is not a queueable kind).
	ra.Queue(pointer.Event{Kind: pointer.Move, Source: pointer.Mouse, Buttons: pointer.ButtonPrimary, Position: f32.Pt(120, 180)})
	a.rubberBandOverlay(gtxA, fOn, image.Pt(400, 400))
	if want := (image.Pt(120, 180)).Add(image.Pt(0, a.listTop)); a.rubberCur != want {
		t.Fatalf("drag not tracked: cur = %v, want %v (pane coords)", a.rubberCur, want)
	}

	// Release applies the selection on A (rows hit by the drag rect).
	a.rowBounds[0] = image.Rect(0, 100, 400, 160)
	a.rowBounds[1] = image.Rect(0, 160, 400, 220)
	ra.Queue(pointer.Event{Kind: pointer.Release, Source: pointer.Mouse, Buttons: pointer.ButtonPrimary, Position: f32.Pt(120, 180)})
	a.rubberBandOverlay(gtxA, fOn, image.Pt(400, 400))
	if a.rubberOn {
		t.Fatal("gesture did not end on release")
	}
	if !a.sel["m0"] || !a.sel["m1"] {
		t.Fatalf("release did not select hit rows: sel = %v", a.sel)
	}
}

func TestRubberSelectRect(t *testing.T) {
	start, cur := image.Pt(100, 50), image.Pt(200, 150)
	r := rubberSelectRect(start, cur)
	if r.Min != image.Pt(100, 50) || r.Max != image.Pt(200, 150) {
		t.Errorf("down-right = %v", r)
	}
	// Reversed drag (up-left): same normalized rect.
	r = rubberSelectRect(cur, start)
	if r.Min != image.Pt(100, 50) || r.Max != image.Pt(200, 150) {
		t.Errorf("up-left = %v", r)
	}
	// Mixed directions.
	r = rubberSelectRect(image.Pt(200, 50), image.Pt(100, 150))
	if r.Min != image.Pt(100, 50) || r.Max != image.Pt(200, 150) {
		t.Errorf("mixed = %v", r)
	}
	// Zero-area tap rect stays empty.
	r = rubberSelectRect(image.Pt(10, 10), image.Pt(10, 10))
	if r.Dx() != 0 || r.Dy() != 0 {
		t.Errorf("tap rect = %v, want zero area", r)
	}
}

func TestRubberHits(t *testing.T) {
	bounds := map[int]image.Rectangle{
		0: {Min: image.Pt(0, 0), Max: image.Pt(300, 60)},
		1: {Min: image.Pt(0, 60), Max: image.Pt(300, 120)},
		2: {Min: image.Pt(0, 120), Max: image.Pt(300, 180)},
	}
	// Rect covering rows 0-1.
	hits := rubberHits(bounds, image.Rectangle{Min: image.Pt(0, 10), Max: image.Pt(300, 100)})
	if len(hits) != 2 {
		t.Fatalf("hits = %v, want rows 0 and 1", hits)
	}
	seen := map[int]bool{}
	for _, h := range hits {
		seen[h] = true
	}
	if !seen[0] || !seen[1] || seen[2] {
		t.Errorf("hits = %v, want {0,1}", hits)
	}

	// Zero-area tap: nothing.
	if hits := rubberHits(bounds, image.Rectangle{Min: image.Pt(5, 5), Max: image.Pt(5, 5)}); len(hits) != 0 {
		t.Errorf("tap hits = %v, want none", hits)
	}
	// Rect outside: nothing.
	if hits := rubberHits(bounds, image.Rectangle{Min: image.Pt(0, 500), Max: image.Pt(300, 600)}); len(hits) != 0 {
		t.Errorf("offscreen hits = %v, want none", hits)
	}
	// Empty bounds map: nothing.
	if hits := rubberHits(nil, image.Rectangle{Min: image.Pt(0, 0), Max: image.Pt(10, 10)}); len(hits) != 0 {
		t.Errorf("empty bounds hits = %v, want none", hits)
	}
}
