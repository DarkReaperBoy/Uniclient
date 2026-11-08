package icons

import "math"

type Vertex struct {
	X float32
	Y float32
}

type Glyph struct {
	W     int
	H     int
	Paths [][]Vertex
}

func (g Glyph) Bounds() (minX, minY, maxX, maxY float32) {
	if len(g.Paths) == 0 || len(g.Paths[0]) == 0 {
		return 0, 0, 0, 0
	}
	first := g.Paths[0][0]
	minX, minY = first.X, first.Y
	maxX, maxY = minX, minY
	for _, p := range g.Paths {
		for _, v := range p {
			if v.X < minX {
				minX = v.X
			}
			if v.Y < minY {
				minY = v.Y
			}
			if v.X > maxX {
				maxX = v.X
			}
			if v.Y > maxY {
				maxY = v.Y
			}
		}
	}
	return minX, minY, maxX, maxY
}

type Cell struct {
	W int
	H int
	X int
	Y int
}

type Icon struct {
	Glyph Glyph
	Cell  Cell
}

const (
	TimerPen      = 1.5
	TimerFontSize = 9
	TimerMaxChars = 2
	timerDotPitch = 3
	arcSteps      = 24
	capSteps      = 8
)

type Dot struct {
	X float32
	Y float32
	R float32
}

func TimerSolidArc(x, y, w, h float32) []Vertex {
	cx := x + w/2
	cy := y + h/2
	ro := w/2 + TimerPen/2
	ri := w/2 - TimerPen/2
	rm := w / 2
	pts := make([]Vertex, 0, 2*arcSteps+2*capSteps+2)
	for i := 0; i <= arcSteps; i++ {
		a := math.Pi * float64(i) / float64(arcSteps)
		pts = append(pts, Vertex{X: cx - ro*float32(math.Sin(a)), Y: cy - ro*float32(math.Cos(a))})
	}
	for i := capSteps; i >= -capSteps; i-- {
		b := math.Pi * float64(i) / float64(2*capSteps)
		pts = append(pts, Vertex{
			X: cx + TimerPen/2*float32(math.Sin(b)),
			Y: cy + rm + TimerPen/2*float32(math.Cos(b)),
		})
	}
	for i := arcSteps; i >= 0; i-- {
		a := math.Pi * float64(i) / float64(arcSteps)
		pts = append(pts, Vertex{X: cx - ri*float32(math.Sin(a)), Y: cy - ri*float32(math.Cos(a))})
	}
	for i := capSteps; i >= -capSteps; i-- {
		b := math.Pi * float64(i) / float64(2*capSteps)
		pts = append(pts, Vertex{
			X: cx - TimerPen/2*float32(math.Sin(b)),
			Y: cy - rm - TimerPen/2*float32(math.Cos(b)),
		})
	}
	return pts
}

func TimerDots(x, y, w, h float32) []Dot {
	cx := x + w/2
	cy := y + h/2
	r := w / 2
	if r <= 0 {
		return nil
	}
	var dots []Dot
	span := int(math.Floor(float64(math.Pi*float64(r)/2) / timerDotPitch))
	for k := -span; k <= span; k++ {
		theta := float64(k) * timerDotPitch / float64(r)
		dots = append(dots, Dot{
			X: cx + r*float32(math.Cos(theta)),
			Y: cy - r*float32(math.Sin(theta)),
			R: TimerPen / 2,
		})
	}
	return dots
}
