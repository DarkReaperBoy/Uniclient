package lottie

import (
	"time"
)

const (
	LayerPrecomp = 0
	LayerSolid   = 1
	LayerImage   = 2
	LayerNull    = 3
	LayerShape   = 4
	LayerText    = 5
)

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

type Asset struct {
	ID     string
	Layers []Layer
}

type Layer struct {
	Name       string
	Index      int
	Type       int
	Parent     int
	RefID      string
	InPoint    float64
	OutPoint   float64
	StartTime  float64
	Transform  Transform
	Shapes     []Shape
	SolidColor []float64
	SolidW     float64
	SolidH     float64
}

type Transform struct {
	Opacity  Prop
	Rotation Prop
	Position Prop
	Anchor   Prop
	Scale    Prop
	Skew     Prop
	SkewAxis Prop
}

type Prop struct {
	Animated  bool
	Value     float64
	Vec       []float64
	Keyframes []Keyframe
}

type Keyframe struct {
	Time               float64
	StartV             []float64
	EndV               []float64
	EaseOutX, EaseOutY []float64
	EaseInX, EaseInY   []float64
	Hold               bool
	SpatialOut         []float64
	SpatialIn          []float64
}

type Shape struct {
	Type      string
	Name      string
	Items     []Shape
	Position  Prop
	Size      Prop
	Round     Prop
	Path      []BezierSeg
	PathProp  Prop
	Color     Prop
	Opacity   Prop
	Width     Prop
	LineCap   int
	LineJoin  int
	GradType  int
	Start     Prop
	End       Prop
	Colors    Prop
	TrimStart Prop
	TrimEnd   Prop
	TrimOff   Prop
	Transform Transform
	Hidden    bool
}

type BezierSeg struct {
	V  [2]float64
	C1 [2]float64
	C2 [2]float64
}

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
