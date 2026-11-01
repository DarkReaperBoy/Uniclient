package lottie

import "math"

func PropValueAt(p Prop, frame float64) float64 {
	if !p.Animated || len(p.Keyframes) == 0 {
		return p.Value
	}
	v := PropVecAt(p, frame)
	if len(v) == 0 {
		return p.Value
	}
	return v[0]
}

func PropVecAt(p Prop, frame float64) []float64 {
	if !p.Animated || len(p.Keyframes) == 0 {
		if p.Vec != nil {
			return p.Vec
		}
		return []float64{p.Value}
	}
	kfs := p.Keyframes
	if frame <= kfs[0].Time {
		return kfs[0].StartV
	}
	last := kfs[len(kfs)-1]
	if frame >= last.Time {
		if last.EndV != nil {
			return last.EndV
		}
		return last.StartV
	}
	for i := 0; i < len(kfs)-1; i++ {
		k, next := kfs[i], kfs[i+1]
		if frame >= k.Time && frame < next.Time {
			if k.Hold {
				return k.StartV
			}
			if k.EndV == nil {
				k.EndV = next.StartV
			}
			span := next.Time - k.Time
			if span <= 0 {
				return k.StartV
			}
			u := (frame - k.Time) / span
			return interpVec(k, u, k.EndV)
		}
	}
	return kfs[len(kfs)-1].StartV
}

func interpVec(k Keyframe, u float64, end []float64) []float64 {
	if k.StartV == nil || end == nil {
		if k.StartV != nil {
			return k.StartV
		}
		return end
	}
	n := len(k.StartV)
	if len(end) < n {
		n = len(end)
	}
	out := make([]float64, n)
	spatial := n >= 2 && k.SpatialOut != nil && k.SpatialIn != nil
	for i := 0; i < n; i++ {
		ox := numAt(k.EaseOutX, i)
		oy := numAt(k.EaseOutY, i)
		ix := numAt(k.EaseInX, i)
		iy := numAt(k.EaseInY, i)
		e := u
		if ox != 0 || oy != 0 || ix != 0 || iy != 0 {
			e = easingBezier(ox, oy, ix, iy, u)
		}
		if spatial && i < 2 {
			out[i] = spatialInterp(k.StartV[i], k.SpatialOut[i], k.SpatialIn[i], end[i], u, e)
			continue
		}
		out[i] = k.StartV[i] + (end[i]-k.StartV[i])*e
	}
	return out
}

func spatialInterp(p0, o, i, p3, u, e float64) float64 {
	c1 := p0 + o/3*1
	c2 := p3 - i/3*1
	t := e
	mt := 1 - t
	return mt*mt*mt*p0 + 3*mt*mt*t*c1 + 3*mt*t*t*c2 + t*t*t*p3
}

func numAt(v []float64, i int) float64 {
	if i < len(v) {
		return v[i]
	}
	if len(v) == 1 {
		return v[0]
	}
	return 0
}

func easingBezier(x1, y1, x2, y2, x float64) float64 {
	if x <= 0 {
		return 0
	}
	if x >= 1 {
		return 1
	}
	t := x
	for iter := 0; iter < 12; iter++ {
		cx := 3*x1*t*(1-t)*(1-t) + 3*x2*t*t*(1-t) + t*t*t - x
		if math.Abs(cx) < 1e-9 {
			break
		}
		d := 3*x1*(1-t)*(1-3*t+3*t*t)/1 + 3*x2*t*(2-3*t) + 3*t*t
		if d == 0 {
			break
		}
		t -= cx / d
		if t < 0 {
			t = 0
		} else if t > 1 {
			t = 1
		}
	}
	return 3*y1*t*(1-t)*(1-t) + 3*y2*t*t*(1-t) + t*t*t
}

type affine struct {
	a, b, c, d, tx, ty float64
}

func identity() affine { return affine{a: 1, d: 1} }

func mulAffine(parent, child affine) affine {
	return affine{
		a:  parent.a*child.a + parent.c*child.b,
		b:  parent.b*child.a + parent.d*child.b,
		c:  parent.a*child.c + parent.c*child.d,
		d:  parent.b*child.c + parent.d*child.d,
		tx: parent.a*child.tx + parent.c*child.ty + parent.tx,
		ty: parent.b*child.tx + parent.d*child.ty + parent.ty,
	}
}

type point struct{ X, Y float64 }

func (m affine) apply(x, y float64) point {
	return point{
		X: m.a*x + m.c*y + m.tx,
		Y: m.b*x + m.d*y + m.ty,
	}
}

type matrix struct {
	affine
	opacity float64
}

func TransformAt(tr Transform, frame float64) matrix {
	opacity := clamp01(PropValueAt(tr.Opacity, frame) / 100)
	pos := PropVecAt(tr.Position, frame)
	anchor := PropVecAt(tr.Anchor, frame)
	scale := PropVecAt(tr.Scale, frame)
	rot := PropValueAt(tr.Rotation, frame) * math.Pi / 180

	sx, sy := vecAt(scale, 0, 100)/100, vecAt(scale, 1, 100)/100
	ax, ay := vecAt(anchor, 0, 0), vecAt(anchor, 1, 0)
	px, py := vecAt(pos, 0, 0), vecAt(pos, 1, 0)

	m := affine{a: math.Cos(rot) * sx, b: math.Sin(rot) * sx, c: -math.Sin(rot) * sy, d: math.Cos(rot) * sy}
	t := m.apply(-ax, -ay)
	m.tx = px + t.X
	m.ty = py + t.Y
	return matrix{affine: m, opacity: opacity}
}

func vecAt(v []float64, i int, def float64) float64 {
	if i < len(v) {
		return v[i]
	}
	return def
}

func clamp01(v float64) float64 {
	if v < 0 {
		return 0
	}
	if v > 1 {
		return 1
	}
	return v
}
