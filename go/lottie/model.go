// Package lottie implements a pure-Go subset renderer for Lottie/Bodymovin
// animations as used by Telegram .tgs animated stickers (gzip-compressed
// JSON, no images, no text). Stage A: the document model + JSON parsing.
// Later stages add keyframe interpolation and a Gio renderer.
package lottie

import (
	"time"
)

// Layer types (Bodymovin "ty").
const (
	LayerPrecomp = 0
	LayerSolid   = 1
	LayerImage   = 2
	LayerNull    = 3
	LayerShape   = 4
	LayerText    = 5
)

// Shape item types ("ty" strings).
const (
	ShapeGroup     = "gr"
	ShapeRect      = "rc"
	ShapeEllipse   = "el"
	ShapePath      = "sh"
	ShapeFill      = "fl"
	ShapeStroke    = "st"
	ShapeTransform = "tr"
	ShapeTrim      = "tm"
	ShapeGradient  = "gf"
)

// Animation is a parsed Bodymovin document.
type Animation struct {
	Name      string
	Version   string
	FrameRate float64
	InPoint   float64
	OutPoint  float64
	Width     float64
	Height    float64
	Layers    []Layer
	Assets    []Asset
}

// Asset is a precomposition ("layers" asset). Image assets are rejected
// by design (.tgs has none).
type Asset struct {
	ID     string
	Layers []Layer
}

// Layer is one animation layer.
type Layer struct {
	Name      string
	Index     int
	Type      int
	Parent    int // parent layer index (0 = none)
	RefID     string
	InPoint   float64
	OutPoint  float64
	StartTime float64
	Transform Transform
	Shapes    []Shape
	// Solid layer fields.
	SolidColor []float64
	SolidW     float64
	SolidH     float64
}

// Transform is a layer or group transform ("ks").
type Transform struct {
	Opacity  Prop // percent 0..100
	Rotation Prop // degrees
	Position Prop // [x, y(, z)]
	Anchor   Prop // [x, y(, z)]
	Scale    Prop // percent per axis
	Skew     Prop
	SkewAxis Prop
}

// Prop is a property: either a static value or keyframes.
type Prop struct {
	Animated  bool
	Value     float64   // static scalar form (single-number props)
	Vec       []float64 // static vector form
	Keyframes []Keyframe
}

// Keyframe is one key: value StartV at time T, interpolating toward EndV
// with the easing Beziers.
type Keyframe struct {
	Time   float64
	StartV []float64
	EndV   []float64
	// Easing control points (per-dimension vectors), CSS-cubic-bezier
	// semantics: Out controls the outgoing tangent, In the incoming.
	EaseOutX, EaseOutY []float64
	EaseInX, EaseInY   []float64
	Hold               bool
	// Spatial tangents for position paths (to/ti).
	SpatialOut []float64
	SpatialIn  []float64
}

// Shape is one item of a shape tree. Items are heterogeneous; only the
// fields the type needs are populated.
type Shape struct {
	Type     string
	Name     string
	Items    []Shape // groups
	Position Prop
	Size     Prop
	Round    Prop // rect corner radius
	// Path: static bezier vertices (Stage A stores animated path values
	// as Vec pairs only when static).
	Path     []BezierSeg
	PathProp Prop // animated path (Vec holds flattened vertices)
	// Fill/stroke.
	Color    Prop // RGBA 0..1
	Opacity  Prop // 0..100
	Width    Prop // stroke width
	LineCap  int
	LineJoin int
	// Gradient.
	GradType int
	Start    Prop
	End      Prop
	Colors   Prop // flattened stops
	// Trim path.
	TrimStart Prop // percent
	TrimEnd   Prop
	TrimOff   Prop
	// Group transform ("tr").
	Transform Transform
	// Hidden flag.
	Hidden bool
}

// BezierSeg is one cubic segment of a path: from V with control points
// C1, C2 to the next vertex.
type BezierSeg struct {
	V  [2]float64
	C1 [2]float64
	C2 [2]float64
}

// Duration returns the animation length in seconds.
func (a *Animation) Duration() time.Duration {
	if a.FrameRate <= 0 {
		return 0
	}
	frames := a.OutPoint - a.InPoint
	if frames <= 0 {
		return 0
	}
	return time.Duration(frames / a.FrameRate * float64(time.Second))
}

// FrameAt converts a time offset to a (clamped) frame number.
func (a *Animation) FrameAt(t time.Duration) float64 {
	if a.FrameRate <= 0 {
		return a.InPoint
	}
	f := a.InPoint + float64(t)/float64(time.Second)*a.FrameRate
	if f < a.InPoint {
		return a.InPoint
	}
	if f > a.OutPoint {
		return a.OutPoint
	}
	return f
}
