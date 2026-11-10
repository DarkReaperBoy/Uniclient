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
	"gioui.org/io/event"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/text"
	"gioui.org/unit"
	"gioui.org/widget"
	xdraw "golang.org/x/image/draw"
	"golang.org/x/image/math/fixed"
	stdraw "image/draw"

	"uniclient/ui/dialogs"
	"uniclient/ui/icons"
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

type InputArea struct{}

type Painter struct {
	Shaper *text.Shaper
	Input  *InputArea
}

func NewPainter() *Painter {
	return &Painter{
		Shaper: text.NewShaper(text.WithCollection(gofont.Collection()), text.NoSystemFonts()),
		Input:  &InputArea{},
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
	m := p.metrics(gtx, dateM, nameM, counterM)
	if e.ChatType != dialogs.ChatPlain {
		m.ChatTypeIconW = dialogs.ChatTypeIcon(e.ChatType).Cell.W
	}
	l := dialogs.Layout(e, width, m)

	bg := rowBackground(sch, state)
	if state != RowNormal {
		fillRRect(gtx, dialogs.Rect{X: 0, Y: 0, W: width, H: l.Height}, 0, bg)
	}

	p.photo(gtx, l, e, sch)
	if e.Online {
		p.onlineBadge(gtx, l.Online, bg)
	}
	if e.TTL {
		p.ttlBadge(gtx, l, e, sch, bg)
	}

	if l.Narrow {
		p.badges(gtx, l, counterM, counter, sch, state)
		return
	}

	if e.ChatType != dialogs.ChatPlain {
		fillGlyph(gtx, l.ChatTypeIcon.X, l.ChatTypeIcon.Y, dialogs.ChatTypeIcon(e.ChatType), iconInk(sch, state))
	}
	p.label(gtx, l.Name, fontSemibold, unit.Sp(tokens.FontBase), e.Name,
		textColor(sch, state, sch.OnSurface, sch.OnPrimaryContainer))
	if e.SendState != dialogs.SendHidden {
		fillGlyph(gtx, l.SendStateIcon.X, l.SendStateIcon.Y, dialogs.SendStateIcon(e.SendState), sendStateInk(sch, state, e.SendState))
	}
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
	p.badges(gtx, l, counterM, counter, sch, state)
}

func (p *Painter) PaintPane(gtx layout.Context, pane dialogs.Pane, sch material.Scheme) {
	totalH := pane.View.Height + tokens.TopBarHeight
	if pane.Width <= 0 || totalH <= 0 {
		return
	}
	defer clip.Rect{Max: image.Pt(
		gtx.Dp(unit.Dp(pane.Width)),
		gtx.Dp(unit.Dp(totalH)),
	)}.Push(gtx.Ops).Pop()
	event.Op(gtx.Ops, p.Input)
	fillRRect(gtx, dialogs.Rect{X: 0, Y: 0, W: pane.Width, H: totalH}, 0, sch.SurfaceContainerLow)
	p.paintHeader(gtx, pane.Header, sch)
	stk := op.Offset(image.Pt(0, gtx.Dp(unit.Dp(tokens.TopBarHeight)))).Push(gtx.Ops)
	listClip := clip.Rect{Max: image.Pt(
		gtx.Dp(unit.Dp(pane.Width)),
		gtx.Dp(unit.Dp(pane.View.Height)),
	)}.Push(gtx.Ops)
	for i := range pane.Rows {
		state := RowNormal
		if pane.First+i == pane.Selected {
			state = RowSelected
		}
		rowStk := op.Offset(image.Pt(0, gtx.Dp(unit.Dp(pane.RowYs[i]-pane.View.Top)))).Push(gtx.Ops)
		p.PaintRow(gtx, pane.Rows[i], pane.Width, sch, state)
		rowStk.Pop()
	}
	if pane.GlobalBar {
		if pane.GlobalBarY+tokens.SearchedBarHeight > pane.View.Top && pane.GlobalBarY < pane.View.Top+pane.View.Height {
			barStk := op.Offset(image.Pt(0, gtx.Dp(unit.Dp(pane.GlobalBarY-pane.View.Top)))).Push(gtx.Ops)
			p.paintSearchedBar(gtx, pane.Width, pane.BarText, sch)
			barStk.Pop()
		}
		for j := range pane.Global {
			state := RowNormal
			if pane.GlobalFirst+j == pane.Selected {
				state = RowSelected
			}
			globalStk := op.Offset(image.Pt(0, gtx.Dp(unit.Dp(pane.GlobalRowYs[j]-pane.View.Top)))).Push(gtx.Ops)
			p.PaintRow(gtx, pane.Global[j], pane.Width, sch, state)
			globalStk.Pop()
		}
	}
	if pane.EmptyText != "" && len(pane.Rows) == 0 && len(pane.Global) == 0 {
		m := p.measure(gtx, fontRegular, unit.Sp(tokens.FontBase), pane.EmptyText)
		if m.w > 0 {
			w := int(gtx.Metric.PxToDp(m.w))
			h := int(gtx.Metric.PxToDp(m.ascent + m.descent))
			p.label(gtx, dialogs.Rect{
				X: (pane.Width - w) / 2,
				Y: (pane.View.Height - h) / 2,
				W: w,
				H: h,
			}, fontRegular, unit.Sp(tokens.FontBase), pane.EmptyText, sch.OnSurfaceVariant)
		}
	}
	p.paintToUpButton(gtx, pane, sch)
	listClip.Pop()
	stk.Pop()
	if pane.Thumb.Hidden {
		return
	}
	fillRRect(gtx, dialogs.Rect{
		X: pane.Width - tokens.ScrollBarWidth + tokens.ScrollBarDeltax,
		Y: tokens.TopBarHeight + pane.Thumb.Y,
		W: tokens.ScrollBarWidth - 2*tokens.ScrollBarDeltax,
		H: pane.Thumb.H,
	}, tokens.ScrollBarRadius, scrollBarColor)
}

func (p *Painter) paintSearchedBar(gtx layout.Context, width int, text string, sch material.Scheme) {
	fillRRect(gtx, dialogs.Rect{X: 0, Y: 0, W: width, H: tokens.SearchedBarHeight}, 0, sch.SurfaceContainer)
	if text == "" {
		return
	}
	barTextHeight := tokens.FontSearchedBar + 4
	p.label(gtx, dialogs.Rect{
		X: tokens.SearchedBarPadX,
		Y: tokens.SearchedBarTextTop,
		W: width - 2*tokens.SearchedBarPadX,
		H: barTextHeight,
	}, fontRegular, unit.Sp(tokens.FontSearchedBar), text, sch.OnSurfaceVariant)
}

func (p *Painter) paintHeader(gtx layout.Context, hd dialogs.HeaderView, sch material.Scheme) {
	if hd.Band.W <= 0 {
		return
	}
	if hd.Field.W <= 0 {
		return
	}
	if hd.Focused {
		fillRRect(gtx, dialogs.Rect{
			X: hd.Field.X - tokens.DialogsFilterBorderActive,
			Y: hd.Field.Y - tokens.DialogsFilterBorderActive,
			W: hd.Field.W + 2*tokens.DialogsFilterBorderActive,
			H: hd.Field.H + 2*tokens.DialogsFilterBorderActive,
		}, tokens.DialogsFilterRadius+tokens.DialogsFilterBorderActive, sch.Primary)
	}
	fillRRect(gtx, hd.Field, tokens.DialogsFilterRadius, sch.SurfaceContainerHighest)
	text := hd.Text
	fg := sch.OnSurface
	if text == "" {
		text = hd.Placeholder
		fg = sch.OnSurfaceVariant
	}
	if text != "" {
		p.paintFieldLine(gtx, hd.Field, fontRegular, unit.Sp(tokens.FontBase), text, fg, 0)
	}
	if hd.Focused && hd.CaretOn {
		prefix := p.measure(gtx, fontRegular, unit.Sp(tokens.FontBase), hd.Text[:hd.Cursor])
		m := p.measure(gtx, fontRegular, unit.Sp(tokens.FontBase), "Ag")
		textH := int(gtx.Metric.PxToDp(m.ascent + m.descent))
		if textH > hd.Field.H-8 {
			textH = hd.Field.H - 8
		}
		fillRRect(gtx, dialogs.Rect{
			X: hd.Field.X + tokens.DialogsFilterTextLeft + int(gtx.Metric.PxToDp(prefix.w)),
			Y: hd.Field.Y + (hd.Field.H-textH)/2,
			W: 2,
			H: textH,
		}, 0, sch.Primary)
	}
}

func (p *Painter) paintFieldLine(gtx layout.Context, field dialogs.Rect, fnt font.Font, size unit.Sp, s string, col color.NRGBA, rightPad int) {
	m := p.measure(gtx, fnt, size, s)
	textH := int(gtx.Metric.PxToDp(m.ascent + m.descent))
	p.label(gtx, dialogs.Rect{
		X: field.X + tokens.DialogsFilterTextLeft,
		Y: field.Y + (field.H-textH)/2,
		W: field.W - tokens.DialogsFilterTextLeft - rightPad,
		H: textH,
	}, fnt, size, s, col)
}

var toUpShadowColor = color.NRGBA{R: 0x00, G: 0x00, B: 0x00, A: 0x28}

func (p *Painter) paintToUpButton(gtx layout.Context, pane dialogs.Pane, sch material.Scheme) {
	if pane.ToUpProgress <= 0 {
		return
	}
	g := dialogs.ToUpGeometry(pane.Width, pane.View.Height, pane.ToUpProgress)
	if g.Y >= pane.View.Height {
		return
	}
	circle := dialogs.Rect{
		X: g.X + tokens.HistoryToDownCircleX,
		Y: g.Y + tokens.HistoryToDownCircleY,
		W: tokens.HistoryToDownCircleSize,
		H: tokens.HistoryToDownCircleSize,
	}
	shadow := circle
	shadow.Y += 2
	fillCircle(gtx, shadow, toUpShadowColor)
	fillCircle(gtx, circle, sch.PrimaryContainer)
	strokeToUpArrow(gtx, g.X, g.Y, sch.OnPrimaryContainer)
}

func strokeToUpArrow(gtx layout.Context, boxLeft, boxTop int, col color.NRGBA) {
	dp := func(v int) float32 {
		return float32(gtx.Dp(unit.Dp(v)))
	}
	w := float32(tokens.HistoryToDownArrowWidth)
	h := float32(tokens.HistoryToDownArrowHeight)
	half := float32(tokens.HistoryToDownArrowStroke) / 2
	cx := dp(boxLeft + tokens.HistoryToDownArrowCenterX)
	cy := dp(boxTop + tokens.DialogsToUpArrowCenterY)
	left := cx - w/2 + half
	bottom := cy + h/2 - half
	var path clip.Path
	path.Begin(gtx.Ops)
	path.MoveTo(f32.Pt(left, bottom))
	path.LineTo(f32.Pt(cx, cy-h/2+half))
	path.LineTo(f32.Pt(left+w-2*half, bottom))
	stroke := clip.Stroke{
		Path:  path.End(),
		Width: float32(gtx.Dp(unit.Dp(tokens.HistoryToDownArrowStroke))),
	}
	defer stroke.Op().Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, col)
}

func (p *Painter) badges(gtx layout.Context, l dialogs.RowLayout, counterM measure, counter string, sch material.Scheme, state RowState) {
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
		case dialogs.BadgePinned:
			fillGlyph(gtx, b.Cell.X, b.Cell.Y, dialogs.BadgeIcon(b.Kind), secondaryIconInk(sch, state))
		case dialogs.BadgeMention, dialogs.BadgeReaction, dialogs.BadgePoll:
			icon := dialogs.BadgeIcon(b.Kind)
			if l.Narrow {
				bg, ink := narrowBadgeColors(sch, b.Kind)
				fillCircle(gtx, b.Cell, bg)
				fillGlyph(gtx,
					b.Cell.X+(b.Cell.W-icon.Cell.W)/2,
					b.Cell.Y+(b.Cell.H-icon.Cell.H)/2,
					icon, ink)
			} else {
				fillGlyph(gtx, b.Cell.X, b.Cell.Y, icon, accentIconInk(sch, state, b.Kind))
			}
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

func (p *Painter) ttlBadge(gtx layout.Context, l dialogs.RowLayout, e dialogs.Entry, sch material.Scheme, bg color.NRGBA) {
	badge := l.TTL
	back := dialogs.TTLBackdrop(p.ttlSource(e, sch, bg), image.Rect(
		badge.X-l.Photo.X, badge.Y-l.Photo.Y,
		badge.X-l.Photo.X+badge.W, badge.Y-l.Photo.Y+badge.H,
	))

	b := pxRect(gtx, badge)
	aff := f32.Affine2D{}.Scale(f32.Point{}, f32.Point{
		X: float32(b.Dx()) / float32(back.Bounds().Dx()),
		Y: float32(b.Dy()) / float32(back.Bounds().Dy()),
	}).Offset(f32.Pt(float32(b.Min.X), float32(b.Min.Y)))
	stk := op.Affine(aff).Push(gtx.Ops)
	clipC := clip.Ellipse(image.Rect(0, 0, b.Dx(), b.Dy())).Push(gtx.Ops)
	paint.NewImageOp(back).Add(gtx.Ops)
	clipC.Pop()
	stk.Pop()

	inner := dialogs.TTLTimerRect(badge)
	scale := float32(gtx.Dp(unit.Dp(1)))
	fillContour(gtx, icons.TimerSolidArc(
		float32(inner.X), float32(inner.Y), float32(inner.W), float32(inner.H),
	), scale, dialogs.TTLTimerInk)
	for _, d := range icons.TimerDots(
		float32(inner.X), float32(inner.Y), float32(inner.W), float32(inner.H),
	) {
		fillDot(gtx, d.X*scale, d.Y*scale, d.R*scale, dialogs.TTLTimerInk)
	}
	text := dialogs.TimerClamp(dialogs.FormatTTLTiny(e.TTLSec))
	if text != "" {
		m := p.measure(gtx, fontSemibold, unit.Sp(icons.TimerFontSize), text)
		p.label(gtx, dialogs.Rect{
			X: inner.X + (inner.W-int(gtx.Metric.PxToDp(m.w)))/2,
			Y: inner.Y + (inner.H-int(gtx.Metric.PxToDp(m.ascent+m.descent)))/2,
			W: int(gtx.Metric.PxToDp(m.w)),
			H: int(gtx.Metric.PxToDp(m.ascent + m.descent)),
		}, fontSemibold, unit.Sp(icons.TimerFontSize), text, dialogs.TTLTimerInk)
	}
}

func (p *Painter) ttlSource(e dialogs.Entry, sch material.Scheme, bg color.NRGBA) *image.NRGBA {
	size := tokens.DialogsRowPhotoSize
	img := image.NewNRGBA(image.Rect(0, 0, size, size))
	stdraw.Draw(img, img.Bounds(), image.NewUniform(bg), image.Point{}, stdraw.Src)
	if e.Photo != nil {
		scaled := image.NewNRGBA(image.Rect(0, 0, size, size))
		xdraw.BiLinear.Scale(scaled, scaled.Bounds(), e.Photo, e.Photo.Bounds(), xdraw.Src, nil)
		stdraw.DrawMask(img, img.Bounds(), scaled, image.Point{}, circleAlpha(size), image.Point{}, stdraw.Over)
	} else {
		stdraw.DrawMask(img, img.Bounds(), image.NewUniform(userpicColor(e.Name, sch)), image.Point{}, circleAlpha(size), image.Point{}, stdraw.Over)
	}
	return img
}

func circleAlpha(size int) *image.Alpha {
	m := image.NewAlpha(image.Rect(0, 0, size, size))
	r := float64(size) / 2
	for y := 0; y < size; y++ {
		for x := 0; x < size; x++ {
			dx := float64(x) + 0.5 - r
			dy := float64(y) + 0.5 - r
			if dx*dx+dy*dy <= r*r {
				m.SetAlpha(x, y, color.Alpha{A: 255})
			}
		}
	}
	return m
}

func iconInk(sch material.Scheme, state RowState) color.NRGBA {
	if state == RowActive {
		return sch.OnPrimaryContainer
	}
	return sch.OnSurface
}

func secondaryIconInk(sch material.Scheme, state RowState) color.NRGBA {
	if state == RowActive {
		return sch.OnPrimaryContainer
	}
	return sch.OnSurfaceVariant
}

func sendStateInk(sch material.Scheme, state RowState, s dialogs.SendState) color.NRGBA {
	if state == RowActive {
		return sch.OnPrimaryContainer
	}
	if s == dialogs.SendSending {
		return sch.OnSurfaceVariant
	}
	return sch.Primary
}

func accentIconInk(sch material.Scheme, state RowState, kind dialogs.BadgeKind) color.NRGBA {
	if state == RowActive {
		return sch.OnPrimaryContainer
	}
	switch kind {
	case dialogs.BadgeReaction:
		return sch.Error
	case dialogs.BadgePoll:
		return sch.Tertiary
	default:
		return sch.Primary
	}
}

func narrowBadgeColors(sch material.Scheme, kind dialogs.BadgeKind) (bg, ink color.NRGBA) {
	switch kind {
	case dialogs.BadgeReaction:
		return sch.Error, sch.OnError
	case dialogs.BadgePoll:
		return sch.Tertiary, sch.OnTertiary
	default:
		return sch.Primary, sch.OnPrimary
	}
}

func fillGlyph(gtx layout.Context, x, y int, icon icons.Icon, col color.NRGBA) {
	if icon.Cell.W <= 0 || len(icon.Glyph.Paths) == 0 {
		return
	}
	scale := float32(gtx.Dp(unit.Dp(1)))
	gx := float32(gtx.Dp(unit.Dp(x + icon.Cell.X)))
	gy := float32(gtx.Dp(unit.Dp(y + icon.Cell.Y)))
	var path clip.Path
	path.Begin(gtx.Ops)
	for _, contour := range icon.Glyph.Paths {
		if len(contour) < 3 {
			continue
		}
		path.MoveTo(f32.Pt(gx+contour[0].X*scale, gy+contour[0].Y*scale))
		for _, v := range contour[1:] {
			path.LineTo(f32.Pt(gx+v.X*scale, gy+v.Y*scale))
		}
		path.Close()
	}
	defer clip.Outline{Path: path.End()}.Op().Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, col)
}

func fillContour(gtx layout.Context, verts []icons.Vertex, scale float32, col color.NRGBA) {
	if len(verts) < 3 {
		return
	}
	var path clip.Path
	path.Begin(gtx.Ops)
	path.MoveTo(f32.Pt(verts[0].X*scale, verts[0].Y*scale))
	for _, v := range verts[1:] {
		path.LineTo(f32.Pt(v.X*scale, v.Y*scale))
	}
	path.Close()
	defer clip.Outline{Path: path.End()}.Op().Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, col)
}

func fillDot(gtx layout.Context, x, y, r float32, col color.NRGBA) {
	rect := image.Rect(
		int(math.Round(float64(x-r))), int(math.Round(float64(y-r))),
		int(math.Round(float64(x+r))), int(math.Round(float64(y+r))),
	)
	if rect.Empty() {
		return
	}
	defer clip.Ellipse(rect).Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, col)
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
