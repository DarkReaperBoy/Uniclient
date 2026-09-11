package lottie

// render.go — Stage C: draws one animation frame into Gio ops. The
// renderer handles the .tgs-relevant subset: shape layers (groups, rect,
// ellipse, bezier paths, fills, strokes), null layers (transform only),
// precomp layers (recursive), solid layers, and parent chains. Masks,
// gradients, trim paths and repeaters render as their untrimmed base
// shape (honest subset — most sticker animations only need this).

import (
	"fmt"
	"image"
	"image/color"

	"gioui.org/f32"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
)

// maxDepth bounds precomp recursion (malformed files must not hang us).
const maxDepth = 8

// renderer carries per-frame evaluation state.
type renderer struct {
	anim  *Animation
	frame float64
	ops   *op.Ops
	// viewport scale: animation units → pixels.
	kx, ky float64
	ox, oy float64
	// fill/stroke counters (test introspection).
	fills, strokes int
}

// Draw renders one frame of anim into ops, mapping the animation's
// w×h viewport onto the given pixel rectangle (letterboxed by aspect).
func Draw(anim *Animation, frame float64, ops *op.Ops, into image.Rectangle) {
	if anim == nil || ops == nil || into.Dx() <= 0 || into.Dy() <= 0 {
		return
	}
	r := &renderer{
		anim:  anim,
		frame: frame,
		ops:   ops,
	}
	w, h := anim.Width, anim.Height
	if w <= 0 || h <= 0 {
		w, h = 512, 512
	}
	// Fit (contain) into the rectangle.
	r.kx = float64(into.Dx()) / w
	r.ky = float64(into.Dy()) / h
	if r.kx < r.ky {
		r.ky = r.kx
	} else {
		r.kx = r.ky
	}
	r.ox = float64(into.Min.X) + (float64(into.Dx())-w*r.kx)/2
	r.oy = float64(into.Min.Y) + (float64(into.Dy())-h*r.ky)/2

	m := identity()
	r.drawLayers(r.anim.Layers, m, 0)
}

// drawLayers paints layers in order (Bodymovin: earlier layers render on
// top), skipping layers outside their in/out span.
func (r *renderer) drawLayers(layers []Layer, parent affine, depth int) {
	if depth > maxDepth {
		return
	}
	// Index map for the parent chain.
	byIndex := make(map[int]int, len(layers))
	for i, l := range layers {
		if l.Index != 0 {
			byIndex[l.Index] = i
		}
	}
	for i := len(layers) - 1; i >= 0; i-- {
		l := layers[i]
		if r.frame < l.InPoint || r.frame >= l.OutPoint {
			continue
		}
		m := TransformAt(l.Transform, r.frame).affine
		// Walk the parent chain.
		pi := l.Parent
		guard := 0
		for pi != 0 && guard < len(layers)+1 {
			piIdx, ok := byIndex[pi]
			if !ok {
				break
			}
			pl := layers[piIdx]
			pm := TransformAt(pl.Transform, r.frame).affine
			m = mulAffine(pm, m)
			pi = pl.Parent
			guard++
		}
		m = mulAffine(parent, m)
		switch l.Type {
		case LayerShape:
			opacity := clamp01(PropValueAt(l.Transform.Opacity, r.frame) / 100)
			r.drawShapes(l.Shapes, m, opacity)
		case LayerSolid:
			r.drawSolid(l, m)
		case LayerNull:
			// transform-only: children already applied via parent chain
		case LayerPrecomp:
			for _, a := range r.anim.Assets {
				if a.ID == l.RefID {
					// Precomp layer opacity applies to the asset render.
					r.drawLayers(a.Layers, m, depth+1)
					break
				}
			}
		}
	}
}

// drawSolid paints a solid layer (sw×sh rect of sc color).
func (r *renderer) drawSolid(l Layer, m affine) {
	if len(l.SolidColor) < 4 || l.SolidW <= 0 || l.SolidH <= 0 {
		return
	}
	p := r.toPx(m)
	spec := r.rectPath(0, 0, l.SolidW, l.SolidH, 0, p)
	col := r.colorOf(l.SolidColor, clamp01(PropValueAt(l.Transform.Opacity, r.frame)/100))
	r.fill(spec, col)
}

// drawShapes paints a shape list (layer shapes or nested group items)
// with the accumulated matrix: geometry paints with the first fill /
// stroke that follows it in the same list; groups recurse through their
// "tr" transform.
func (r *renderer) drawShapes(shapes []Shape, m affine, opacity float64) {
	for i := range shapes {
		if shapes[i].Hidden {
			continue
		}
		if shapes[i].Type == ShapeGroup {
			// The group's transform is the "tr" item inside its item
			// list (usually last); apply it, then recurse — the item
			// itself is consumed here.
			mm, op := m, opacity
			for j := range shapes[i].Items {
				if shapes[i].Items[j].Type == ShapeTransform {
					tm := TransformAt(shapes[i].Items[j].Transform, r.frame)
					mm = mulAffine(m, tm.affine)
					op *= tm.opacity
					break
				}
			}
			r.drawShapes(shapes[i].Items, mm, op)
			continue
		}
		if shapes[i].Type == ShapeTransform {
			continue // layer-level transform already applied
		}
		// Geometry + following styles.
		var fill, stroke *Shape
		for j := i + 1; j < len(shapes); j++ {
			if shapes[j].Hidden {
				continue
			}
			switch shapes[j].Type {
			case ShapeFill:
				if fill == nil {
					f := shapes[j]
					fill = &f
				}
			case ShapeStroke:
				if stroke == nil {
					st := shapes[j]
					stroke = &st
				}
			}
		}
		r.drawGeometry(&shapes[i], m, opacity, fill, stroke)
	}
}

// drawGeometry paints one geometry item with its resolved styles.
func (r *renderer) drawGeometry(it *Shape, m affine, opacity float64, fill, stroke *Shape) {
	p := r.toPx(m)
	var spec clip.PathSpec
	switch it.Type {
	case ShapeRect:
		pos := PropVecAt(it.Position, r.frame)
		size := PropVecAt(it.Size, r.frame)
		spec = r.rectPath(vecAt(pos, 0, 0), vecAt(pos, 1, 0),
			vecAt(size, 0, 0), vecAt(size, 1, 0), PropValueAt(it.Round, r.frame), p)
	case ShapeEllipse:
		pos := PropVecAt(it.Position, r.frame)
		size := PropVecAt(it.Size, r.frame)
		spec = r.ellipsePath(vecAt(pos, 0, 0), vecAt(pos, 1, 0),
			vecAt(size, 0, 0), vecAt(size, 1, 0), p)
	case ShapePath:
		spec = r.bezierPath(it, p)
	default:
		return
	}
	if fill != nil {
		c := PropVecAt(fill.Color, r.frame)
		if len(c) >= 4 {
			fo := clamp01(PropValueAt(fill.Opacity, r.frame)/100) * opacity
			r.fill(spec, r.colorOf(c, fo))
		}
	}
	if stroke != nil {
		c := PropVecAt(stroke.Color, r.frame)
		if len(c) >= 4 {
			so := clamp01(PropValueAt(stroke.Opacity, r.frame)/100) * opacity
			w := PropValueAt(stroke.Width, r.frame)
			if w > 0 {
				r.stroke(spec, r.colorOf(c, so), p.scale*w)
			}
		}
	}
}

// toPx precomputes the unit→pixel transform (matrix × viewport fit).
func (r *renderer) toPx(m affine) pxTransform {
	// Compose: scale by k then translate by o, then the layer matrix.
	fit := affine{a: r.kx, d: r.ky, tx: r.ox, ty: r.oy}
	full := mulAffine(fit, m)
	// Average scale magnitude for stroke widths.
	s := (abs64(full.a) + abs64(full.b) + abs64(full.c) + abs64(full.d)) / 4
	if s == 0 {
		s = 1
	}
	return pxTransform{m: full, scale: s}
}

type pxTransform struct {
	m     affine
	scale float64
}

func (p pxTransform) pt(x, y float64) f32.Point {
	q := p.m.apply(x, y)
	return f32.Pt(float32(q.X), float32(q.Y))
}

func abs64(v float64) float64 {
	if v < 0 {
		return -v
	}
	return v
}

// rectPath: rounded rectangle centered at (cx,cy) with size (w,h).
func (r *renderer) rectPath(cx, cy, w, h, rad float64, p pxTransform) clip.PathSpec {
	if w <= 0 || h <= 0 {
		return clip.PathSpec{}
	}
	var path clip.Path
	path.Begin(r.ops)
	x0, y0 := cx-w/2, cy-h/2
	x1, y1 := cx+w/2, cy+h/2
	if rad > w/2 {
		rad = w / 2
	}
	if rad > h/2 {
		rad = h / 2
	}
	path.Move(p.pt(x0, y0))
	if rad <= 0 {
		path.Line(p.pt(w, 0))
		path.Line(p.pt(0, h))
		path.Line(p.pt(-w, 0))
		path.Line(p.pt(0, -h))
	} else {
		// Rounded corners via cubics.
		path.Line(p.pt(x0+w-rad, y0))
		corner := func(cx0, cy0, ex, ey, mx, my float64) {
			path.Cube(p.pt(cx0, cy0), p.pt(ex, ey), p.pt(mx, my))
		}
		corner(x1, y0, x1, y0+rad, x1, y0+rad) // top-right
		path.Line(p.pt(x1, y1-rad))
		corner(x1, y1, x1-rad, y1, x1-rad, y1) // bottom-right
		path.Line(p.pt(x0+rad, y1))
		corner(x0, y1, x0, y1-rad, x0, y1-rad) // bottom-left
		path.Line(p.pt(x0, y0+rad))
		corner(x0, y0, x0+rad, y0, x0+rad, y0) // top-left
	}
	path.Close()
	return path.End()
}

// ellipsePath: ellipse centered at (cx,cy), diameter (w,h), via four
// cubic segments (k = 0.5523).
func (r *renderer) ellipsePath(cx, cy, w, h float64, p pxTransform) clip.PathSpec {
	if w <= 0 || h <= 0 {
		return clip.PathSpec{}
	}
	const k = 0.5522847498
	rx, ry := w/2, h/2
	var path clip.Path
	path.Begin(r.ops)
	path.Move(p.pt(cx, cy-ry))
	path.Cube(p.pt(cx+k*rx, cy-ry), p.pt(cx+rx, cy-k*ry), p.pt(cx+rx, cy))
	path.Cube(p.pt(cx+rx, cy+k*ry), p.pt(cx+k*rx, cy+ry), p.pt(cx, cy+ry))
	path.Cube(p.pt(cx-k*rx, cy+ry), p.pt(cx-rx, cy+k*ry), p.pt(cx-rx, cy))
	path.Cube(p.pt(cx-rx, cy-k*ry), p.pt(cx-k*rx, cy-ry), p.pt(cx, cy-ry))
	path.Close()
	return path.End()
}

// bezierPath: a "sh" path property (static vertex form stored in Vec as
// flattened [x,y] pairs — every other value is a vertex).
func (r *renderer) bezierPath(it *Shape, p pxTransform) clip.PathSpec {
	v := it.PathProp.Vec
	if it.PathProp.Animated || len(v) < 4 {
		return clip.PathSpec{}
	}
	var path clip.Path
	path.Begin(r.ops)
	path.Move(p.pt(v[0], v[1]))
	for i := 3; i+1 < len(v); i += 2 {
		path.Line(p.pt(v[i], v[i+1]))
	}
	path.Close()
	return path.End()
}

func (r *renderer) fill(spec clip.PathSpec, col color.NRGBA) {
	if spec == (clip.PathSpec{}) {
		return
	}
	r.fills++
	paint.FillShape(r.ops, col, clip.Outline{Path: spec}.Op())
}

func (r *renderer) stroke(spec clip.PathSpec, col color.NRGBA, width float64) {
	if spec == (clip.PathSpec{}) || width <= 0 {
		return
	}
	r.strokes++
	paint.FillShape(r.ops, col, clip.Stroke{Path: spec, Width: float32(width)}.Op())
}

func (r *renderer) colorOf(c []float64, opacity float64) color.NRGBA {
	if len(c) < 4 {
		return color.NRGBA{}
	}
	a := clamp01(c[3]) * clamp01(opacity)
	return color.NRGBA{
		R: uint8(clamp01(c[0]) * 255),
		G: uint8(clamp01(c[1]) * 255),
		B: uint8(clamp01(c[2]) * 255),
		A: uint8(a * 255),
	}
}

// String aids debugging.
func (a *Animation) String() string {
	return fmt.Sprintf("lottie(%q %vx%v@%v %v layers, %v assets)", a.Name, a.Width, a.Height, a.FrameRate, len(a.Layers), len(a.Assets))
}
