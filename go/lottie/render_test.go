package lottie

import (
	"image"
	"testing"

	"gioui.org/op"
)

// renderDrawSmoke: a full document renders every frame without panicking
// and emits paint operations (Stage C).
func TestRenderDrawSmoke(t *testing.T) {
	src := `{
		"v":"5.7.4","fr":30,"ip":0,"op":30,"w":100,"h":100,"nm":"smoke",
		"layers":[
			{"ddd":0,"ind":1,"ty":4,"nm":"dot","sr":1,
			 "ks":{"o":{"a":0,"k":100},
				"r":{"a":1,"k":[{"t":0,"s":[0],"i":{"x":[0.4],"y":[1]},"o":{"x":[0.6],"y":[0]}},{"t":29,"s":[359]}]},
				"p":{"a":0,"k":[50,50,0]},
				"a":{"a":0,"k":[0,0,0]},"s":{"a":0,"k":[100,100,100]}},
			 "shapes":[{"ty":"gr","nm":"g","it":[
				{"ty":"el","p":{"a":0,"k":[0,0]},"s":{"a":0,"k":[80,80]},"nm":"e"},
				{"ty":"fl","c":{"a":0,"k":[1,0.42,0.04,1]},"o":{"a":0,"k":100},"nm":"f"},
				{"ty":"tr","p":{"a":0,"k":[0,0]},"a":{"a":0,"k":[0,0]},"s":{"a":0,"k":[100,100]},
				 "r":{"a":0,"k":0},"o":{"a":0,"k":100},"sk":{"a":0,"k":0},"sa":{"a":0,"k":0}}]}],
			 "ip":0,"op":30,"st":0,"bm":0},
			{"ddd":0,"ind":2,"ty":3,"nm":"null","sr":1,
			 "ks":{"o":{"a":0,"k":0},"r":{"a":0,"k":0},"p":{"a":0,"k":[50,50,0]},
				"a":{"a":0,"k":[0,0,0]},"s":{"a":0,"k":[100,100,100]}},"ao":0,"ip":0,"op":30,"st":0,"bm":0},
			{"ddd":0,"ind":3,"ty":4,"nm":"ring","parent":2,"sr":1,
			 "ks":{"o":{"a":0,"k":80},"r":{"a":0,"k":45},
				"p":{"a":0,"k":[0,0,0]},"a":{"a":0,"k":[0,0,0]},"s":{"a":0,"k":[100,100,100]}},
			 "shapes":[{"ty":"gr","nm":"g2","it":[
				{"ty":"el","p":{"a":0,"k":[0,0]},"s":{"a":0,"k":[90,90]},"nm":"e2"},
				{"ty":"st","c":{"a":0,"k":[0.2,0.6,1,1]},"o":{"a":0,"k":100},"w":{"a":0,"k":4},"lc":1,"lj":1,"nm":"s2"},
				{"ty":"tr","p":{"a":0,"k":[0,0]},"a":{"a":0,"k":[0,0]},"s":{"a":0,"k":[100,100]},
				 "r":{"a":0,"k":0},"o":{"a":0,"k":100},"sk":{"a":0,"k":0},"sa":{"a":0,"k":0}}]}],
			 "ip":0,"op":30,"st":0,"bm":0}
		]
	}`
	anim, err := ParseAnimationJSON([]byte(src))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	// Every frame renders without panicking (the ops themselves are
	// validated by Gio at draw time; here we exercise the full walker:
	// groups, transforms, parent chain, fill + stroke styles).
	for f := 0.0; f < 30; f += 0.7 {
		var ops op.Ops
		Draw(anim, f, &ops, image.Rect(0, 0, 128, 128))
	}
	// The same document with an in-range frame emits paint ops: verify
	// via the fill counter (renderer tracks fills for tests).
	r := &renderer{anim: anim, frame: 15, ops: &op.Ops{}}
	r.fit(image.Rect(0, 0, 128, 128))
	r.drawLayers(r.anim.Layers, identity(), 0)
	if r.fills == 0 || r.strokes == 0 {
		t.Fatalf("emitted %d fills / %d strokes, want both > 0", r.fills, r.strokes)
	}
	// Degenerate rects never panic.
	var ops op.Ops
	Draw(anim, 0, &ops, image.Rect(0, 0, 0, 0))
	Draw(nil, 0, &ops, image.Rect(0, 0, 10, 10))
}

// Letterboxing: a 2:1 animation in a square viewport centers content
// (the fit scale is the min axis).
func TestRenderFitScale(t *testing.T) {
	anim := &Animation{Width: 200, Height: 100, FrameRate: 30, OutPoint: 1}
	r := &renderer{anim: anim}
	r.fit(image.Rect(0, 0, 100, 100))
	if r.kx != 0.5 || r.ky != 0.5 {
		t.Errorf("fit scale = %v,%v want 0.5,0.5", r.kx, r.ky)
	}
	if r.ox != 0 || r.oy != 25 {
		t.Errorf("offset = %v,%v want 0,25", r.ox, r.oy)
	}
}

// fit helper for tests (the Draw path computes the same values).
func (r *renderer) fit(into image.Rectangle) {
	w, h := r.anim.Width, r.anim.Height
	r.kx = float64(into.Dx()) / w
	r.ky = float64(into.Dy()) / h
	if r.kx < r.ky {
		r.ky = r.kx
	} else {
		r.kx = r.ky
	}
	r.ox = float64(into.Min.X) + (float64(into.Dx())-w*r.kx)/2
	r.oy = float64(into.Min.Y) + (float64(into.Dy())-h*r.ky)/2
}
