package lottie

// parse.go — Stage A JSON decoding of the Bodymovin subset used by .tgs
// animated stickers. Lenient by design (unknown fields are skipped, not
// rejected), strict where the format demands it (the container must be
// gzip; image/text assets are rejected — .tgs never has them).

import (
	"bytes"
	"compress/gzip"
	"encoding/json"
	"fmt"
	"io"
)

// ParseTgs decodes a Telegram .tgs file: gzip → JSON → Animation.
func ParseTgs(data []byte) (*Animation, error) {
	zr, err := gzip.NewReader(bytes.NewReader(data))
	if err != nil {
		return nil, fmt.Errorf("tgs: not gzip: %w", err)
	}
	defer zr.Close()
	raw, err := io.ReadAll(zr)
	if err != nil {
		return nil, fmt.Errorf("tgs: gzip read: %w", err)
	}
	return ParseAnimationJSON(raw)
}

// ParseAnimationJSON decodes a Bodymovin JSON document.
func ParseAnimationJSON(data []byte) (*Animation, error) {
	var doc rawAnimation
	if err := json.Unmarshal(data, &doc); err != nil {
		return nil, fmt.Errorf("lottie: json: %w", err)
	}
	anim := &Animation{
		Name:      doc.Name,
		Version:   doc.Version,
		FrameRate: numOr(doc.FrameRate, 60),
		InPoint:   numOr(doc.InPoint, 0),
		OutPoint:  numOr(doc.OutPoint, 0),
		Width:     numOr(doc.Width, 512),
		Height:    numOr(doc.Height, 512),
	}
	for _, a := range doc.Assets {
		asset := Asset{ID: a.ID}
		for _, l := range a.Layers {
			layer, err := parseLayer(l)
			if err != nil {
				return nil, err
			}
			asset.Layers = append(asset.Layers, layer)
		}
		anim.Assets = append(anim.Assets, asset)
	}
	for _, l := range doc.Layers {
		layer, err := parseLayer(l)
		if err != nil {
			return nil, err
		}
		anim.Layers = append(anim.Layers, layer)
	}
	return anim, nil
}

// raw structs mirror the JSON loosely; json.RawMessage would be heavier
// than letting the decoder skip unknown keys.
type rawAnimation struct {
	Name      string      `json:"nm"`
	Version   string      `json:"v"`
	FrameRate json.Number `json:"fr"`
	InPoint   json.Number `json:"ip"`
	OutPoint  json.Number `json:"op"`
	Width     json.Number `json:"w"`
	Height    json.Number `json:"h"`
	Layers    []rawLayer  `json:"layers"`
	Assets    []rawAsset  `json:"assets"`
}

type rawAsset struct {
	ID     string     `json:"id"`
	Layers []rawLayer `json:"layers"`
}

type rawLayer struct {
	Name      string       `json:"nm"`
	Index     json.Number  `json:"ind"`
	Type      json.Number  `json:"ty"`
	Parent    json.Number  `json:"parent"`
	RefID     string       `json:"refId"`
	InPoint   json.Number  `json:"ip"`
	OutPoint  json.Number  `json:"op"`
	StartTime json.Number  `json:"st"`
	Transform rawTransform `json:"ks"`
	Shapes    []rawShape   `json:"shapes"`
	// solids
	SolidColor []float64   `json:"sc"`
	SolidW     json.Number `json:"sw"`
	SolidH     json.Number `json:"sh"`
}

type rawTransform struct {
	Opacity  json.RawMessage `json:"o"`
	Rotation json.RawMessage `json:"r"`
	Position json.RawMessage `json:"p"`
	Anchor   json.RawMessage `json:"a"`
	Scale    json.RawMessage `json:"s"`
	Skew     json.RawMessage `json:"sk"`
	SkewAxis json.RawMessage `json:"sa"`
}

type rawShape struct {
	Type     string          `json:"ty"`
	Name     string          `json:"nm"`
	Hidden   bool            `json:"hd"`
	Items    []rawShape      `json:"it"`
	Position json.RawMessage `json:"p"`
	Size     json.RawMessage `json:"s"`
	Round    json.RawMessage `json:"r"`
	// path
	Vertices json.RawMessage `json:"ks"`
	// fill/stroke
	Color    json.RawMessage `json:"c"`
	Opacity  json.RawMessage `json:"o"`
	Width    json.RawMessage `json:"w"`
	LineCap  json.Number     `json:"lc"`
	LineJoin json.Number     `json:"lj"`
	// gradient
	GradType json.Number     `json:"t"`
	Start    json.RawMessage `json:"s"`
	End      json.RawMessage `json:"e"`
	Colors   json.RawMessage `json:"g"`
	// trim
	TrimStart json.RawMessage `json:"s"`
	TrimEnd   json.RawMessage `json:"e"`
	TrimOff   json.RawMessage `json:"o"`
	// group transform ("tr") items: anchor
	Anchor json.RawMessage `json:"a"`
}

func numOr(n json.Number, def float64) float64 {
	if n == "" {
		return def
	}
	f, err := n.Float64()
	if err != nil {
		return def
	}
	return f
}

// parseLayer converts one raw layer; image and text layers are rejected
// (.tgs never contains them; better to fail loudly than render wrong).
func parseLayer(l rawLayer) (Layer, error) {
	ty := int(numOr(l.Type, -1))
	switch ty {
	case LayerImage:
		return Layer{}, fmt.Errorf("lottie: image layer rejected (not .tgs)")
	case LayerText:
		return Layer{}, fmt.Errorf("lottie: text layer rejected (not .tgs)")
	}
	layer := Layer{
		Name:       l.Name,
		Index:      int(numOr(l.Index, 0)),
		Type:       ty,
		Parent:     int(numOr(l.Parent, 0)),
		RefID:      l.RefID,
		InPoint:    numOr(l.InPoint, 0),
		OutPoint:   numOr(l.OutPoint, 0),
		StartTime:  numOr(l.StartTime, 0),
		Transform:  parseTransform(l.Transform),
		SolidColor: l.SolidColor,
		SolidW:     numOr(l.SolidW, 0),
		SolidH:     numOr(l.SolidH, 0),
	}
	for _, sh := range l.Shapes {
		layer.Shapes = append(layer.Shapes, parseShape(sh))
	}
	return layer, nil
}

func parseTransform(rt rawTransform) Transform {
	return Transform{
		Opacity:  parsePropRaw(rt.Opacity),
		Rotation: parsePropRaw(rt.Rotation),
		Position: parsePropRaw(rt.Position),
		Anchor:   parsePropRaw(rt.Anchor),
		Scale:    parsePropRaw(rt.Scale),
		Skew:     parsePropRaw(rt.Skew),
		SkewAxis: parsePropRaw(rt.SkewAxis),
	}
}

// parseProp decodes a property object {"a","k"} or bare value.
func parseProp(data []byte) Prop {
	if len(data) == 0 {
		return Prop{}
	}
	var raw rawProp
	if err := json.Unmarshal(data, &raw); err != nil {
		return Prop{}
	}
	return propFromRaw(raw)
}

type rawProp struct {
	A int             `json:"a"`
	K json.RawMessage `json:"k"`
}

func propFromRaw(raw rawProp) Prop {
	if raw.A == 1 {
		// animated: k = keyframe array
		var kfs []rawKeyframe
		if err := json.Unmarshal(raw.K, &kfs); err != nil {
			// Some files use "k" as an expression object — treat as static.
			return Prop{}
		}
		p := Prop{Animated: true, Keyframes: make([]Keyframe, 0, len(kfs))}
		for i, rk := range kfs {
			kf := Keyframe{
				Time: numOr(rk.Time, 0),
				Hold: numOr(rk.Hold, 0) == 1,
			}
			kf.StartV = floatSlice(rk.Start)
			kf.EndV = floatSlice(rk.End)
			kf.SpatialOut = floatSlice(rk.To)
			kf.SpatialIn = floatSlice(rk.Ti)
			if len(rk.EaseIn.X) > 0 {
				kf.EaseInX = floatSlice(rk.EaseIn.X)
				kf.EaseInY = floatSlice(rk.EaseIn.Y)
			}
			if len(rk.EaseOut.X) > 0 {
				kf.EaseOutX = floatSlice(rk.EaseOut.X)
				kf.EaseOutY = floatSlice(rk.EaseOut.Y)
			}
			// EndV may be omitted on the last keyframe — the next key's
			// start (or its own start) completes it.
			if kf.EndV == nil && i+1 < len(kfs) {
				kf.EndV = floatSlice(kfs[i+1].Start)
			}
			p.Keyframes = append(p.Keyframes, kf)
		}
		return p
	}
	// static: k = scalar, vector, or path shape object
	var num json.Number
	if err := json.Unmarshal(raw.K, &num); err == nil {
		f, _ := num.Float64()
		return Prop{Value: f}
	}
	var vec []float64
	if err := json.Unmarshal(raw.K, &vec); err == nil {
		return Prop{Vec: vec}
	}
	// path shape {"a","k","i","o","c"} — keep the vertices in Vec for
	// Stage B (animated path objects: a=1 branch above already handles
	// the keyframe form).
	var shape rawPathProp
	if err := json.Unmarshal(raw.K, &shape); err == nil && shape.K != nil {
		return Prop{Vec: flattenPathVertices(shape.K)}
	}
	return Prop{}
}

type rawKeyframe struct {
	Time    json.Number     `json:"t"`
	Start   json.RawMessage `json:"s"`
	End     json.RawMessage `json:"e"`
	Hold    json.Number     `json:"h"`
	EaseIn  rawEase         `json:"i"`
	EaseOut rawEase         `json:"o"`
	To      json.RawMessage `json:"to"`
	Ti      json.RawMessage `json:"ti"`
}

type rawEase struct {
	X json.RawMessage `json:"x"`
	Y json.RawMessage `json:"y"`
}

type rawPathProp struct {
	A int             `json:"a"`
	K json.RawMessage `json:"k"`
	I json.RawMessage `json:"i"`
	O json.RawMessage `json:"o"`
	C bool            `json:"c"`
}

// flattenPathVertices pulls [x,y] pairs out of the [[v],[v]...] form for
// the Vec slot (Stage B reconstructs full segments).
func flattenPathVertices(raw json.RawMessage) []float64 {
	var verts [][]float64
	if err := json.Unmarshal(raw, &verts); err != nil {
		return nil
	}
	out := make([]float64, 0, len(verts)*2)
	for _, v := range verts {
		if len(v) >= 2 {
			out = append(out, v[0], v[1])
		}
	}
	return out
}

func parsePropRaw(data json.RawMessage) Prop {
	return parseProp(data)
}

func floatSlice(raw json.RawMessage) []float64 {
	if len(raw) == 0 {
		return nil
	}
	var out []float64
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil
	}
	return out
}

// parseShape converts one raw shape item recursively.
func parseShape(rs rawShape) Shape {
	sh := Shape{Type: rs.Type, Name: rs.Name, Hidden: rs.Hidden}
	switch rs.Type {
	case ShapeGroup:
		for _, it := range rs.Items {
			sh.Items = append(sh.Items, parseShape(it))
		}
	case ShapeRect:
		sh.Position = parsePropRaw(rs.Position)
		sh.Size = parsePropRaw(rs.Size)
		sh.Round = parsePropRaw(rs.Round)
	case ShapeEllipse:
		sh.Position = parsePropRaw(rs.Position)
		sh.Size = parsePropRaw(rs.Size)
	case ShapePath:
		sh.PathProp = parsePropRaw(rs.Vertices)
	case ShapeFill, ShapeStroke:
		sh.Color = parsePropRaw(rs.Color)
		sh.Opacity = parsePropRaw(rs.Opacity)
		if rs.Type == ShapeStroke {
			sh.Width = parsePropRaw(rs.Width)
			sh.LineCap = int(numOr(rs.LineCap, 1))
			sh.LineJoin = int(numOr(rs.LineJoin, 1))
		}
	case ShapeGradient:
		sh.GradType = int(numOr(rs.GradType, 1))
		sh.Start = parsePropRaw(rs.Start)
		sh.End = parsePropRaw(rs.End)
		sh.Colors = parsePropRaw(rs.Colors)
	case ShapeTrim:
		sh.TrimStart = parsePropRaw(rs.TrimStart)
		sh.TrimEnd = parsePropRaw(rs.TrimEnd)
		sh.TrimOff = parsePropRaw(rs.TrimOff)
	case ShapeTransform:
		// "tr" items carry p/a/s (shared JSON keys with size/round on
		// geometry items — same key, different meaning) plus r for
		// rotation and o for opacity.
		sh.Transform = parseTransform(rawTransform{
			Opacity:  rs.Opacity,
			Rotation: rs.Round,
			Position: rs.Position,
			Anchor:   rs.Anchor,
			Scale:    rs.Size,
		})
	}
	return sh
}
