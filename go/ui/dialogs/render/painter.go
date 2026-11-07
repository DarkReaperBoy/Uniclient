package render

import (
	"image"
	"image/color"
	"math"
	"strings"
	"unicode"
	"unicode/utf8"

	"gioui.org/f32"
	"gioui.org/font"
	"gioui.org/font/gofont"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/text"
	"gioui.org/unit"
	"gioui.org/widget"
	"golang.org/x/image/math/fixed"

	"uniclient/ui/dialogs"
	"uniclient/ui/material"
	"uniclient/ui/tokens"
)

type RowState uint8

const (
	RowNormal RowState = iota
	RowSelected
	RowActive
)

var presenceGreen = color.NRGBA{R: 0x4d, G: 0xc9, B: 0x20, A: 0xff}

var darkInk = color.NRGBA{R: 0x1d, G: 0x1b, B: 0x20, A: 0xff}

var scrollBarColor = color.NRGBA{R: 0x00, G: 0x00, B: 0x00, A: 0x53}

var (
	fontRegular  = font.Font{Typeface: "Go"}
	fontSemibold = font.Font{Typeface: "Go", Weight: font.Medium}
	fontBold     = font.Font{Typeface: "Go", Weight: font.Bold}
)

type Painter struct {
	Shaper *text.Shaper
}

func NewPainter() *Painter {
	return &Painter{
		Shaper: text.NewShaper(text.WithCollection(gofont.Collection()), text.NoSystemFonts()),
	}
}

type measure struct {
	w, ascent, descent int
}

func (p *Painter) measure(gtx layout.Context, fnt font.Font, size unit.Sp, s string) measure {
	if s == "" {
		return measure{}
	}
	p.Shaper.LayoutString(text.Parameters{
		Font:     fnt,
		PxPerEm:  fixed.I(gtx.Sp(size)),
		MaxWidth: math.MaxInt32,
		Locale:   gtx.Locale,
	}, s)
	var m measure
	first := true
	for g, ok := p.Shaper.NextGlyph(); ok; g, ok = p.Shaper.NextGlyph() {
		if end := (g.X + g.Advance).Ceil(); end > m.w {
			m.w = end
		}
		if first {
			m.ascent = g.Ascent.Ceil()
			m.descent = g.Descent.Ceil()
			first = false
		}
	}
	return m
}

func (p *Painter) metrics(gtx layout.Context, dateM, nameM, counterM measure) dialogs.Metrics {
	pxd := func(px int) int {
		return int(gtx.Metric.PxToDp(px))
	}
	return dialogs.Metrics{
		SemiboldHeight: pxd(nameM.ascent + nameM.descent),
		NormalDescent:  pxd(dateM.descent),
		TextAscent:     pxd(dateM.ascent),
		TextHeight:     pxd(dateM.ascent + dateM.descent),
		UnreadAscent:   pxd(counterM.ascent),
		UnreadHeight:   pxd(counterM.ascent + counterM.descent),
		NameWidth:      pxd(nameM.w),
		DateWidth:      pxd(dateM.w),
		CounterWidth:   pxd(counterM.w),
	}
}

func (p *Painter) PaintRow(gtx layout.Context, e dialogs.Entry, width int, sch material.Scheme, state RowState) {
	narrow := width < tokens.ColumnMinWidthLeft/2
	nameM := p.measure(gtx, fontSemibold, unit.Sp(tokens.FontBase), e.Name)
	dateM := p.measure(gtx, fontRegular, unit.Sp(tokens.FontDialogsDate), e.Date)
	counter := dialogs.CounterText(e, narrow)
	counterM := p.measure(gtx, fontBold, unit.Sp(tokens.FontDialogsUnread), counter)
	l := dialogs.Layout(e, width, p.metrics(gtx, dateM, nameM, counterM))

	bg := rowBackground(sch, state)
	if state != RowNormal {
		fillRRect(gtx, dialogs.Rect{X: 0, Y: 0, W: width, H: l.Height}, 0, bg)
	}

	p.photo(gtx, l, e, sch)
	if e.Online {
		p.onlineBadge(gtx, l.Online, bg)
	}

	if l.Narrow {
		p.badges(gtx, l, counterM, counter, sch)
		return
	}

	p.label(gtx, l.Name, fontSemibold, unit.Sp(tokens.FontBase), e.Name,
		textColor(sch, state, sch.OnSurface, sch.OnPrimaryContainer))
	if l.DateX != 0 {
		dateRect := dialogs.Rect{
			X: l.DateX,
			Y: l.DateBaseline - int(gtx.Metric.PxToDp(dateM.ascent)),
			W: int(gtx.Metric.PxToDp(dateM.w)),
			H: int(gtx.Metric.PxToDp(dateM.ascent + dateM.descent)),
		}
		p.label(gtx, dateRect, fontRegular, unit.Sp(tokens.FontDialogsDate), e.Date,
			textColor(sch, state, sch.OnSurfaceVariant, sch.OnPrimaryContainer))
	}
	p.label(gtx, l.Preview, fontRegular, unit.Sp(tokens.FontBase), e.Preview,
		textColor(sch, state, sch.OnSurfaceVariant, sch.OnPrimaryContainer))
	p.badges(gtx, l, counterM, counter, sch)
}

func (p *Painter) PaintPane(gtx layout.Context, pane dialogs.Pane, sch material.Scheme) {
	if pane.Width <= 0 || pane.View.Height <= 0 {
		return
	}
	defer clip.Rect{Max: image.Pt(
		gtx.Dp(unit.Dp(pane.Width)),
		gtx.Dp(unit.Dp(pane.View.Height)),
	)}.Push(gtx.Ops).Pop()
	for i := range pane.Rows {
		state := RowNormal
		if pane.First+i == pane.Selected {
			state = RowSelected
		}
		stk := op.Offset(image.Pt(0, gtx.Dp(unit.Dp(pane.RowYs[i]-pane.View.Top)))).Push(gtx.Ops)
		p.PaintRow(gtx, pane.Rows[i], pane.Width, sch, state)
		stk.Pop()
	}
	if pane.Thumb.Hidden {
		return
	}
	fillRRect(gtx, dialogs.Rect{
		X: pane.Width - tokens.ScrollBarWidth + tokens.ScrollBarDeltax,
		Y: pane.Thumb.Y,
		W: tokens.ScrollBarWidth - 2*tokens.ScrollBarDeltax,
		H: pane.Thumb.H,
	}, tokens.ScrollBarRadius, scrollBarColor)
}

func (p *Painter) badges(gtx layout.Context, l dialogs.RowLayout, counterM measure, counter string, sch material.Scheme) {
	for _, b := range l.Badges {
		switch b.Kind {
		case dialogs.BadgeCounter:
			bg, fg := sch.Primary, sch.OnPrimary
			if b.Muted {
				bg, fg = sch.SurfaceContainerHighest, sch.OnSurfaceVariant
			}
			fillRRect(gtx, b.Cell, tokens.DialogsBadgeRadius, bg)
			cw := int(gtx.Metric.PxToDp(counterM.w))
			p.label(gtx, dialogs.Rect{
				X: b.Cell.X + (b.Cell.W-cw)/2,
				Y: b.TextBaseline - int(gtx.Metric.PxToDp(counterM.ascent)),
				W: cw,
				H: int(gtx.Metric.PxToDp(counterM.ascent + counterM.descent)),
			}, fontBold, unit.Sp(tokens.FontDialogsUnread), counter, fg)
		case dialogs.BadgeMark:
			bg := sch.Primary
			if b.Muted {
				bg = sch.SurfaceContainerHighest
			}
			fillCircle(gtx, b.Dot, bg)
		}
	}
}

func (p *Painter) photo(gtx layout.Context, l dialogs.RowLayout, e dialogs.Entry, sch material.Scheme) {
	b := pxRect(gtx, l.Photo)
	if e.Photo != nil {
		src := e.Photo.Bounds()
		aff := f32.Affine2D{}.Scale(f32.Point{}, f32.Point{
			X: float32(b.Dx()) / float32(src.Dx()),
			Y: float32(b.Dy()) / float32(src.Dy()),
		}).Offset(f32.Pt(float32(b.Min.X), float32(b.Min.Y)))
		defer op.Affine(aff).Push(gtx.Ops).Pop()
		defer clip.Ellipse(image.Rect(0, 0, b.Dx(), b.Dy())).Push(gtx.Ops).Pop()
		paint.NewImageOp(e.Photo).Add(gtx.Ops)
		return
	}
	col := userpicColor(e.Name, sch)
	fillCircle(gtx, l.Photo, col)
	init := initials(e.Name)
	if init == "" {
		return
	}
	size := unit.Sp(tokens.DialogsRowPhotoSize * 13 / 33)
	m := p.measure(gtx, fontSemibold, size, init)
	fg := color.NRGBA{R: 0xff, G: 0xff, B: 0xff, A: 0xff}
	if luma(col) > 128 {
		fg = darkInk
	}
	p.label(gtx, dialogs.Rect{
		X: l.Photo.X + (l.Photo.W-int(gtx.Metric.PxToDp(m.w)))/2,
		Y: l.Photo.Y + (l.Photo.H-int(int(gtx.Metric.PxToDp(m.ascent+m.descent))))/2,
		W: int(gtx.Metric.PxToDp(m.w)),
		H: int(gtx.Metric.PxToDp(m.ascent + m.descent)),
	}, fontSemibold, size, init, fg)
}

func (p *Painter) onlineBadge(gtx layout.Context, r dialogs.Rect, bg color.NRGBA) {
	b := pxRect(gtx, r)
	stroke := clip.Stroke{
		Path:  clip.Ellipse(b).Path(gtx.Ops),
		Width: float32(gtx.Dp(unit.Dp(tokens.DialogsOnlineBadgeStroke))),
	}
	defer stroke.Op().Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, bg)
	fillCircle(gtx, r, presenceGreen)
}

func (p *Painter) label(gtx layout.Context, r dialogs.Rect, fnt font.Font, size unit.Sp, s string, col color.NRGBA) {
	if s == "" || r.W <= 0 || r.H <= 0 {
		return
	}
	macro := op.Record(gtx.Ops)
	paint.ColorOp{Color: col}.Add(gtx.Ops)
	mat := macro.Stop()
	defer op.Offset(image.Pt(gtx.Dp(unit.Dp(r.X)), gtx.Dp(unit.Dp(r.Y)))).Push(gtx.Ops).Pop()
	gtx.Constraints = layout.Constraints{
		Max: image.Pt(gtx.Dp(unit.Dp(r.W)), gtx.Dp(unit.Dp(r.H))),
	}
	widget.Label{MaxLines: 1, Truncator: "…"}.Layout(gtx, p.Shaper, fnt, size, s, mat)
}

func rowBackground(sch material.Scheme, state RowState) color.NRGBA {
	switch state {
	case RowSelected:
		return sch.SurfaceContainerHigh
	case RowActive:
		return sch.PrimaryContainer
	default:
		return sch.Surface
	}
}

func textColor(sch material.Scheme, state RowState, normal, active color.NRGBA) color.NRGBA {
	if state == RowActive {
		return active
	}
	return normal
}

func pxRect(gtx layout.Context, r dialogs.Rect) image.Rectangle {
	return image.Rect(
		gtx.Dp(unit.Dp(r.X)),
		gtx.Dp(unit.Dp(r.Y)),
		gtx.Dp(unit.Dp(r.X+r.W)),
		gtx.Dp(unit.Dp(r.Y+r.H)),
	)
}

func fillRRect(gtx layout.Context, r dialogs.Rect, radius int, col color.NRGBA) {
	defer clip.UniformRRect(pxRect(gtx, r), gtx.Dp(unit.Dp(radius))).Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, col)
}

func fillCircle(gtx layout.Context, r dialogs.Rect, col color.NRGBA) {
	defer clip.Ellipse(pxRect(gtx, r)).Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, col)
}

func luma(c color.NRGBA) int {
	return (299*int(c.R) + 587*int(c.G) + 114*int(c.B)) / 1000
}

func userpicColor(name string, sch material.Scheme) color.NRGBA {
	set := []color.NRGBA{sch.Primary, sch.Secondary, sch.Tertiary, sch.Error}
	h := uint32(2166136261)
	for i := 0; i < len(name); i++ {
		h ^= uint32(name[i])
		h *= 16777619
	}
	return set[h%uint32(len(set))]
}

func initials(name string) string {
	fields := strings.Fields(name)
	if len(fields) == 0 {
		return ""
	}
	out := make([]rune, 0, 2)
	for _, f := range fields {
		r, sz := utf8.DecodeRuneInString(f)
		if sz > 0 && unicode.IsLetter(r) {
			out = append(out, unicode.ToUpper(r))
			if len(out) == 2 {
				break
			}
		}
	}
	return string(out)
}
