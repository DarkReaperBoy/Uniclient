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

func TestRubberBandGestureIsPerWindow(t *testing.T) {
	var ra input.Router
	var opsA op.Ops
	a := &App{ui: NewUI(), rowBounds: map[int]image.Rectangle{}, listTop: 100}
	gtxA := layout.Context{Ops: &opsA, Source: ra.Source(), Constraints: layout.Exact(image.Pt(400, 400))}
	fOn := frame{selOn: true, messages: []engine.CachedMessage{{MsgID: "m0"}, {MsgID: "m1"}}}
	a.rubberBandOverlay(gtxA, fOn, image.Pt(400, 400))
	ra.Frame(gtxA.Ops)
	ra.Queue(pointer.Event{Kind: pointer.Press, Source: pointer.Mouse, Buttons: pointer.ButtonPrimary, Position: f32.Pt(50, 40)})
	a.rubberBandOverlay(gtxA, fOn, image.Pt(400, 400))
	if !a.rubberOn {
		t.Fatal("gesture did not start on press")
	}

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
	if b.rubberOn {
		t.Fatal("cross-window bleed: window B adopted window A's selection rectangle (B-47 class, R23)")
	}

	ra.Queue(pointer.Event{Kind: pointer.Move, Source: pointer.Mouse, Buttons: pointer.ButtonPrimary, Position: f32.Pt(120, 180)})
	a.rubberBandOverlay(gtxA, fOn, image.Pt(400, 400))
	if want := (image.Pt(120, 180)).Add(image.Pt(0, a.listTop)); a.rubberCur != want {
		t.Fatalf("drag not tracked: cur = %v, want %v (pane coords)", a.rubberCur, want)
	}

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
	r = rubberSelectRect(cur, start)
	if r.Min != image.Pt(100, 50) || r.Max != image.Pt(200, 150) {
		t.Errorf("up-left = %v", r)
	}
	r = rubberSelectRect(image.Pt(200, 50), image.Pt(100, 150))
	if r.Min != image.Pt(100, 50) || r.Max != image.Pt(200, 150) {
		t.Errorf("mixed = %v", r)
	}
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

	if hits := rubberHits(bounds, image.Rectangle{Min: image.Pt(5, 5), Max: image.Pt(5, 5)}); len(hits) != 0 {
		t.Errorf("tap hits = %v, want none", hits)
	}
	if hits := rubberHits(bounds, image.Rectangle{Min: image.Pt(0, 500), Max: image.Pt(300, 600)}); len(hits) != 0 {
		t.Errorf("offscreen hits = %v, want none", hits)
	}
	if hits := rubberHits(nil, image.Rectangle{Min: image.Pt(0, 0), Max: image.Pt(10, 10)}); len(hits) != 0 {
		t.Errorf("empty bounds hits = %v, want none", hits)
	}
}
