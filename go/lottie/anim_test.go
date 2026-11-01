package lottie

import (
	"math"
	"testing"
)

func TestPropValueAt(t *testing.T) {
	p := Prop{Value: 42}
	if v := PropValueAt(p, 10); v != 42 {
		t.Errorf("static scalar = %v", v)
	}
	p = Prop{Vec: []float64{1, 2}}
	if v := PropVecAt(p, 10); v[0] != 1 || v[1] != 2 {
		t.Errorf("static vec = %v", v)
	}
	p = Prop{Animated: true, Keyframes: []Keyframe{{Time: 0, StartV: []float64{7}, EndV: []float64{7}}}}
	if v := PropValueAt(p, 30); v != 7 {
		t.Errorf("single kf = %v", v)
	}
	p = Prop{Animated: true, Keyframes: []Keyframe{
		{Time: 0, StartV: []float64{0}, EndV: []float64{10}},
		{Time: 60, StartV: []float64{10}},
	}}
	if v := PropValueAt(p, 30); v != 5 {
		t.Errorf("linear midpoint = %v, want 5", v)
	}
	if v := PropValueAt(p, 0); v != 0 {
		t.Errorf("start = %v", v)
	}
	if v := PropValueAt(p, 60); v != 10 {
		t.Errorf("end = %v", v)
	}
	if v := PropValueAt(p, -5); v != 0 {
		t.Errorf("before start = %v", v)
	}
	if v := PropValueAt(p, 120); v != 10 {
		t.Errorf("after end = %v", v)
	}
	p = Prop{Animated: true, Keyframes: []Keyframe{
		{Time: 0, StartV: []float64{1}, EndV: []float64{1}, Hold: true},
		{Time: 30, StartV: []float64{5}, EndV: []float64{5}, Hold: true},
		{Time: 60, StartV: []float64{9}},
	}}
	for f, want := range map[float64]float64{0: 1, 29: 1, 30: 5, 59: 5, 60: 9, 100: 9} {
		if v := PropValueAt(p, f); v != want {
			t.Errorf("hold at %v = %v, want %v", f, v, want)
		}
	}
}

func TestEasingBezier(t *testing.T) {
	for _, p := range []float64{0, 0.25, 0.5, 0.75, 1} {
		if v := easingBezier(0, 0, 1, 1, p); math.Abs(v-p) > 1e-9 {
			t.Errorf("linear(%v) = %v", p, v)
		}
	}
	ease := easingBezier(0.42, 0, 0.58, 1, 0.5)
	if math.Abs(ease-0.5) > 1e-6 {
		t.Errorf("symmetric ease midpoint = %v, want 0.5", ease)
	}
	if v := easingBezier(0.42, 0, 0.58, 1, 0); v != 0 {
		t.Errorf("ease(0) = %v", v)
	}
	if v := easingBezier(0.42, 0, 0.58, 1, 1); v != 1 {
		t.Errorf("ease(1) = %v", v)
	}
	v := easingBezier(0.3, -0.5, 0.7, 1.5, 0.5)
	if math.Abs(v-0.5) > 0.4 {
		t.Errorf("overshoot midpoint = %v (unexpectedly far)", v)
	}
}

func TestTransformAt(t *testing.T) {
	tr := Transform{
		Opacity:  Prop{Value: 100},
		Rotation: Prop{Value: 90},
		Position: Prop{Vec: []float64{100, 50, 0}},
		Anchor:   Prop{Vec: []float64{10, 10, 0}},
		Scale:    Prop{Vec: []float64{200, 50, 100}},
	}
	m := TransformAt(tr, 0)
	if m.opacity != 1 {
		t.Errorf("opacity = %v", m.opacity)
	}
	if math.Abs(m.tx-105) > 1e-9 || math.Abs(m.ty-30) > 1e-9 {
		t.Errorf("translate = (%v,%v), want (105,30)", m.tx, m.ty)
	}
	if math.Abs(m.a-0) > 1e-9 || math.Abs(m.b-2) > 1e-9 || math.Abs(m.c+0.5) > 1e-9 || math.Abs(m.d-0) > 1e-9 {
		t.Errorf("matrix = [%v %v; %v %v], want [0 2; -0.5 0]", m.a, m.b, m.c, m.d)
	}
	if pt := m.apply(10, 10); math.Abs(pt.X-100) > 1e-9 || math.Abs(pt.Y-50) > 1e-9 {
		t.Errorf("anchor maps to %v, want (100,50)", pt)
	}
}

func TestMatMul(t *testing.T) {
	m := affine{a: 2, b: 1, c: 1, d: 3, tx: 5, ty: 7}
	id := identity()
	got := mulAffine(id, m)
	if got != m {
		t.Errorf("identity ∘ M = %v", got)
	}
	tl := affine{a: 1, d: 1, tx: 10, ty: 0}
	sc := affine{a: 2, d: 2}
	got = mulAffine(tl, sc)
	if got.a != 2 || got.tx != 10 {
		t.Errorf("translate∘scale = %v", got)
	}
	p := mulAffine(tl, sc).apply(1, 1)
	if p.X != 12 || p.Y != 2 {
		t.Errorf("point = %v, want (12,2)", p)
	}
}
