package lottie

import (
	"bytes"
	"compress/gzip"
	"testing"
	"time"
)

// parseTgs decodes the gzip+JSON container (Stage A).
func TestParseTgs(t *testing.T) {
	// A minimal but real-shaped animation, gzip-wrapped like Telegram does.
	in := `{"v":"5.7.4","fr":60,"ip":0,"op":90,"w":512,"h":512,"layers":[]}`
	b, err := gzipBytes([]byte(in))
	if err != nil {
		t.Fatal(err)
	}
	anim, err := ParseTgs(b)
	if err != nil {
		t.Fatalf("ParseTgs: %v", err)
	}
	if anim.FrameRate != 60 || anim.OutPoint != 90 || anim.Width != 512 || anim.Height != 512 {
		t.Errorf("header decoded wrong: %+v", anim)
	}
	if len(anim.Layers) != 0 {
		t.Errorf("expected no layers, got %d", len(anim.Layers))
	}

	// Non-gzip payload must fail (Telegram tgs is always gzipped).
	if _, err := ParseTgs([]byte(in)); err == nil {
		t.Errorf("plain JSON must be rejected")
	}
	// Garbage must fail cleanly.
	if _, err := ParseTgs([]byte{0x1f, 0x8b, 0xff, 0x00}); err == nil {
		t.Errorf("truncated gzip must be rejected")
	}
}

// parseAnimation decodes the Bodymovin JSON (Stage A): header, layers,
// assets, shape trees, transforms — static and animated properties.
func TestParseAnimation(t *testing.T) {
	src := `{
		"v":"5.7.4","fr":30,"ip":0,"op":60,"w":256,"h":256,"nm":"dot",
		"assets":[{"id":"comp_0","layers":[{"ddd":0,"ind":1,"ty":3,"nm":"null","sr":1,
			"ks":{"o":{"a":0,"k":100},"r":{"a":0,"k":0},"p":{"a":0,"k":[128,128,0]},
			"a":{"a":0,"k":[0,0,0]},"s":{"a":0,"k":[100,100,100]}},"ao":0,"ip":0,"op":60,"st":0,"bm":0}],
		"fr":30,"ip":0,"op":60,"w":256,"h":256}],
		"layers":[
			{"ddd":0,"ind":1,"ty":4,"nm":"dot","sr":1,
			 "ks":{"o":{"a":0,"k":100},
				"r":{"a":1,"k":[{"t":0,"s":[0],"i":{"x":[0.4],"y":[1]},"o":{"x":[0.6],"y":[0]}},{"t":59,"s":[359]}]},
				"p":{"a":1,"k":[{"t":0,"s":[10,128,0],"to":[60,0,0],"ti":[-60,0,0]},{"t":59,"s":[246,128,0]}]},
				"a":{"a":0,"k":[0,0,0]},"s":{"a":0,"k":[100,100,100]}},
			 "ao":0,
			 "shapes":[{"ty":"gr","nm":"g","it":[
				{"ty":"el","p":{"a":0,"k":[0,0]},"s":{"a":0,"k":[80,80]},"nm":"e"},
				{"ty":"fl","c":{"a":0,"k":[1,0.42,0.04,1]},"o":{"a":0,"k":100},"nm":"f"},
				{"ty":"tr","p":{"a":0,"k":[0,0]},"a":{"a":0,"k":[0,0]},"s":{"a":0,"k":[100,100]},
				 "r":{"a":0,"k":0},"o":{"a":0,"k":100},"sk":{"a":0,"k":0},"sa":{"a":0,"k":0}}]}],
			 "ip":0,"op":60,"st":0,"bm":0}
		]
	}`
	anim, err := ParseAnimationJSON([]byte(src))
	if err != nil {
		t.Fatalf("ParseAnimationJSON: %v", err)
	}
	if anim.Name != "dot" || anim.FrameRate != 30 || len(anim.Layers) != 1 {
		t.Fatalf("header: %+v", anim)
	}
	if len(anim.Assets) != 1 || anim.Assets[0].ID != "comp_0" || len(anim.Assets[0].Layers) != 1 {
		t.Fatalf("assets: %+v", anim.Assets)
	}
	l := anim.Layers[0]
	if l.Type != LayerShape || l.Index != 1 || l.Parent != 0 {
		t.Fatalf("layer: %+v", l)
	}
	// Static position vs animated rotation vs animated position.
	if l.Transform.Opacity.Animated || l.Transform.Opacity.Value != 100 {
		t.Errorf("opacity: %+v", l.Transform.Opacity)
	}
	if !l.Transform.Rotation.Animated || len(l.Transform.Rotation.Keyframes) != 2 {
		t.Errorf("rotation: %+v", l.Transform.Rotation)
	}
	if !l.Transform.Position.Animated {
		t.Errorf("position should be animated")
	} else {
		kf := l.Transform.Position.Keyframes
		if len(kf) != 2 || kf[0].StartV == nil || kf[0].EndV == nil {
			t.Fatalf("position kfs: %+v", kf)
		}
		if kf[0].StartV[0] != 10 || kf[0].EndV[0] != 246 {
			t.Errorf("position values: %v → %v", kf[0].StartV, kf[0].EndV)
		}
		// Spatial tangents survive (to/ti).
		if kf[0].SpatialOut == nil || kf[0].SpatialOut[0] != 60 {
			t.Errorf("spatial out tangent lost: %+v", kf[0].SpatialOut)
		}
	}
	// Shape tree: group with ellipse + fill + transform.
	if len(l.Shapes) != 1 || l.Shapes[0].Type != ShapeGroup {
		t.Fatalf("shapes: %+v", l.Shapes)
	}
	g := l.Shapes[0]
	if len(g.Items) != 3 || g.Items[0].Type != ShapeEllipse || g.Items[1].Type != ShapeFill || g.Items[2].Type != ShapeTransform {
		t.Fatalf("group items: %+v", g.Items)
	}
	fl := g.Items[1]
	if fl.Color.Vec == nil || fl.Color.Vec[0] != 1 || fl.Color.Vec[3] != 1 {
		t.Errorf("fill color: %+v", fl.Color)
	}
}

// Duration/Frames sanity (Stage A).
func TestAnimationDuration(t *testing.T) {
	anim := &Animation{InPoint: 0, OutPoint: 90, FrameRate: 30}
	if d := anim.Duration(); d != 3*time.Second {
		t.Errorf("duration = %v, want 3s", d)
	}
	if f := anim.FrameAt(time.Second); f != 30 {
		t.Errorf("frame at 1s = %v, want 30", f)
	}
	// Out of range clamps.
	if f := anim.FrameAt(-1); f != 0 {
		t.Errorf("clamped frame = %v", f)
	}
	if f := anim.FrameAt(99 * time.Second); f != 90 {
		t.Errorf("clamped frame = %v", f)
	}
}

// gzipBytes helper for tests.
func gzipBytes(in []byte) ([]byte, error) {
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	if _, err := zw.Write(in); err != nil {
		return nil, err
	}
	if err := zw.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}
