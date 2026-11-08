package render

import (
	"image"
	"image/color"
	"math"

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
	"golang.org/x/image/math/fixed"

	"uniclient/ui/history"
	"uniclient/ui/icons"
	"uniclient/ui/material"
	"uniclient/ui/tokens"
)

type InputArea struct{}

type ChatPainter struct {
	Shaper *text.Shaper
	Input  *InputArea
}

var (
	fontRegular  = font.Font{Typeface: "Go"}
	fontSemibold = font.Font{Typeface: "Go", Weight: font.Medium}
)

var inShadow = color.NRGBA{R: 0x74, G: 0x8e, B: 0xa2, A: 0x29}

var outShadow = color.NRGBA{R: 0x3a, G: 0xc3, B: 0x46, A: 0x1d}

var badgeBg = color.NRGBA{R: 0x00, G: 0x00, B: 0x00, A: 0x1e}

var historyScrollBarColor = color.NRGBA{R: 0x51, G: 0x7c, B: 0x41, A: 0x7a}

var historyScrollBarOverColor = color.NRGBA{R: 0x51, G: 0x7c, B: 0x41, A: 0xbc}

func NewChatPainter() *ChatPainter {
	return &ChatPainter{
		Shaper: text.NewShaper(text.WithCollection(gofont.Collection()), text.NoSystemFonts()),
		Input:  &InputArea{},
	}
}

type shapeResult struct {
	lines       int
	ascent      int
	descent     int
	maxEnd      int
	lastLineEnd int
	lineEnds    []int
}

func (p *ChatPainter) shape(gtx layout.Context, fnt font.Font, size unit.Sp, s string, maxWidth int) shapeResult {
	p.Shaper.LayoutString(text.Parameters{
		Font:     fnt,
		PxPerEm:  fixed.I(gtx.Sp(size)),
		MaxWidth: maxWidth,
		Locale:   gtx.Locale,
	}, s)
	var r shapeResult
	prevY := math.MinInt
	first := true
	for g, ok := p.Shaper.NextGlyph(); ok; g, ok = p.Shaper.NextGlyph() {
		if first {
			r.ascent = g.Ascent.Ceil()
			r.descent = g.Descent.Ceil()
			r.lines = 1
			prevY = int(g.Y)
			first = false
		} else if int(g.Y) != prevY {
			r.lineEnds = append(r.lineEnds, r.lastLineEnd)
			r.lines++
			prevY = int(g.Y)
			r.lastLineEnd = 0
		}
		end := (g.X + g.Advance).Ceil()
		if end > r.maxEnd {
			r.maxEnd = end
		}
		if end > r.lastLineEnd {
			r.lastLineEnd = end
		}
	}
	if !first {
		r.lineEnds = append(r.lineEnds, r.lastLineEnd)
	}
	return r
}

func (p *ChatPainter) shapeLineWidths(gtx layout.Context, fnt font.Font, size unit.Sp, s string, maxWidth int) []int {
	if s == "" {
		return nil
	}
	r := p.shape(gtx, fnt, size, s, maxWidth)
	widths := make([]int, len(r.lineEnds))
	for i, e := range r.lineEnds {
		if e < 0 {
			e = 0
		}
		widths[i] = e
	}
	return widths
}

type metric struct {
	gtx     layout.Context
	painter *ChatPainter
	fnt     font.Font
	size    unit.Sp
	str     string
	width   int
	lineH   int
	skipW   int
	skipH   int
}

func (p *ChatPainter) newMetric(gtx layout.Context, fnt font.Font, size unit.Sp, s string, skipW, skipH int) metric {
	if s == "" {
		return metric{}
	}
	natural := p.shape(gtx, fnt, size, s, math.MaxInt32)
	return metric{
		gtx:     gtx,
		painter: p,
		fnt:     fnt,
		size:    size,
		str:     s,
		width:   natural.maxEnd,
		lineH:   natural.ascent + natural.descent,
		skipW:   skipW,
		skipH:   skipH,
	}
}

func (m metric) minHeight() int {
	if m.skipH > m.lineH {
		return m.skipH
	}
	return m.lineH
}

func (m metric) text() history.Text {
	return history.Text{
		MaxWidth:  m.width,
		MinHeight: m.minHeight(),
		HeightFor: m.heightFor,
	}
}

func (m metric) heightFor(width int) (height, realWidth int) {
	if m.str == "" {
		return 0, 0
	}
	r := m.painter.shape(m.gtx, m.fnt, m.size, m.str, width)
	if r.lines == 0 {
		return 0, 0
	}
	lineH := r.ascent + r.descent
	lastH := lineH
	if m.skipH > lastH {
		lastH = m.skipH
	}
	height = (r.lines-1)*lineH + lastH
	if m.skipW > 0 && r.lastLineEnd+m.skipW > width {
		height += lastH
	}
	return height, r.maxEnd
}

func (p *ChatPainter) serviceLineHeight(gtx layout.Context) int {
	r := p.shape(gtx, fontSemibold, unit.Sp(tokens.FontMsgService), "Ag", math.MaxInt32)
	return r.ascent + r.descent
}

func (p *ChatPainter) measureItem(gtx layout.Context, item history.Item, bar history.Bars, viewWidth int) (int, history.HitBox) {
	mode := history.ChatModeFor(viewWidth)
	if item.Kind == history.ItemService {
		svcH := p.serviceLineHeight(gtx)
		dateM := p.newMetric(gtx, fontRegular, unit.Sp(tokens.FontMsgDate), item.TimeText, 0, 0)
		badge := history.ServiceTimeBadgeMetrics(dateM.width, dateM.lineH, svcH)
		skipW, skipH := 0, 0
		if item.TimeText != "" {
			skipW, skipH = badge.SkipWidth, badge.SkipHeight
		}
		m := p.newMetric(gtx, fontSemibold, unit.Sp(tokens.FontMsgService), item.Text, skipW, skipH)
		t := m.text()
		c := history.ServiceCtx{Mode: mode, HasText: item.Text != "", Bars: bar}
		height := history.ServiceHeight(viewWidth, t.MaxWidth, t.MinHeight, t, c)
		return height, history.HitBox{Item: history.ServiceGeometry(viewWidth, height, c)}
	}
	dateM := p.newMetric(gtx, fontRegular, unit.Sp(tokens.FontMsgDate), item.TimeText, 0, 0)
	hasTicks := item.Out || item.Sending
	skipW, skipH := 0, 0
	if item.TimeText != "" {
		skipW = history.SkipBlockWidth(dateM.width)
		skipH = history.SkipBlockHeight(dateM.lineH)
	}
	m := p.newMetric(gtx, fontRegular, unit.Sp(tokens.FontBase), item.Text, skipW, skipH)
	c := history.MessageCtx{
		Mode:        mode,
		Out:         item.Out,
		Attached:    item.AttachedTop,
		Bubble:      true,
		VisibleText: item.Text != "",
		FromName:    item.FromName != "",
		NeedInfo:    item.TimeText != "",
		Bars:        bar,
	}
	nameM := p.newMetric(gtx, fontSemibold, unit.Sp(tokens.FontMsgName), item.FromName, 0, 0)
	nameLine := 0
	if c.FromName {
		nameLine = nameM.lineH
	}
	t := m.text()
	opt, nonText := history.MessageOptimalSize(t, c, nameM.width)
	fonts := history.Fonts{NameHeight: nameLine, DateHeight: dateM.lineH}
	height := history.MessageHeight(viewWidth, opt.Width, opt.Height, nonText,
		dateM.lineH, 0, t, c, fonts)
	contentWidth := history.MessageContentWidth(viewWidth, opt.Width, 0, c)
	_, realW := t.HeightFor(history.BubbleTextWidth(contentWidth))
	g := history.MessageGeometry(viewWidth, height, opt.Width, nonText, realW, 0, c)
	hit := history.HitBox{Item: g}
	if item.TimeText != "" {
		hit.Time = history.TimeRect(g, dateM.width, dateM.lineH, hasTicks)
	}
	return height, hit
}

func (p *ChatPainter) MeasureItem(gtx layout.Context, item history.Item, viewWidth int) int {
	height, _ := p.measureItem(gtx, item, history.Bars{}, viewWidth)
	return height
}

func (p *ChatPainter) Measure(gtx layout.Context, items []history.Item, viewWidth int) ([]int, []history.HitBox) {
	bars := history.ComposeBars(items)
	heights := make([]int, len(items))
	hits := make([]history.HitBox, len(items))
	top := 0
	for i := range items {
		heights[i], hits[i] = p.measureItem(gtx, items[i], bars[i], viewWidth)
		hits[i].Item.Top += top
		hits[i].Time.Top += top
		top += heights[i]
	}
	return heights, hits
}

func (p *ChatPainter) PaintChatPane(gtx layout.Context, pane history.ChatPane, sch material.Scheme) {
	if pane.Width <= 0 || pane.View.Height <= 0 {
		return
	}
	defer clip.Rect{Max: image.Pt(
		gtx.Dp(unit.Dp(pane.Width)),
		gtx.Dp(unit.Dp(pane.View.Height)),
	)}.Push(gtx.Ops).Pop()
	event.Op(gtx.Ops, p.Input)
	if pane.Count <= 0 {
		return
	}
	mode := history.ChatModeFor(pane.Width)
	for i := range pane.Rows {
		stk := op.Offset(image.Pt(0, gtx.Dp(unit.Dp(pane.Ys[i]-pane.View.Top)))).Push(gtx.Ops)
		var bar history.Bars
		if i < len(pane.Bars) {
			bar = pane.Bars[i]
		}
		if bar.Unread > 0 {
			p.paintUnreadBar(gtx, pane.Rows[i], pane.Width, mode, bar, sch)
		}
		if pane.Rows[i].Kind == history.ItemService {
			p.paintService(gtx, pane.Rows[i], bar, pane.Width, pane.Heights[i], sch)
		} else {
			p.paintMessage(gtx, pane.Rows[i], bar, pane.Width, pane.Heights[i], sch)
		}
		stk.Pop()
	}
	for i := range pane.Rows {
		var bar history.Bars
		if i < len(pane.Bars) {
			bar = pane.Bars[i]
		}
		if bar.Date > 0 && pane.First+i != pane.DateRow {
			p.paintDateBadge(gtx, pane.Rows[i].DateText,
				pane.Ys[i]-pane.View.Top, pane.Width, mode, 1, sch)
		}
	}
	if pane.DateRow >= 0 && pane.DateText != "" {
		alpha := float32(1)
		if !pane.DateInPlace {
			alpha = pane.DateAlpha
		}
		if alpha > 0 {
			p.paintDateBadge(gtx, pane.DateText,
				pane.DateTop-pane.View.Top, pane.Width, mode, alpha, sch)
		}
	}
	p.paintDownButton(gtx, pane, sch)
	p.paintMentionsButton(gtx, pane, sch)
	if pane.Thumb.Hidden {
		return
	}
	col := historyScrollBarColor
	if pane.ThumbDragging {
		col = historyScrollBarOverColor
	}
	fillRRect(gtx, history.Geometry{
		Left:   pane.Width - tokens.HistoryScrollBarWidth + tokens.HistoryScrollBarDeltax,
		Top:    pane.Thumb.Y,
		Width:  tokens.HistoryScrollBarWidth - 2*tokens.HistoryScrollBarDeltax,
		Height: pane.Thumb.H,
	}, tokens.HistoryScrollBarRadius, col)
}

func (p *ChatPainter) paintService(gtx layout.Context, item history.Item, bar history.Bars, viewWidth, rowHeight int, sch material.Scheme) {
	if rowHeight <= 0 {
		return
	}
	mode := history.ChatModeFor(viewWidth)
	c := history.ServiceCtx{Mode: mode, HasText: item.Text != "", Bars: bar}
	g := history.ServiceGeometry(viewWidth, rowHeight, c)
	trect := history.Geometry{
		Left:   g.Left + tokens.MsgServicePadLeft,
		Top:    g.Top + tokens.MsgServicePadTop,
		Width:  g.Width - tokens.MsgServicePadLeft - tokens.MsgServicePadRight,
		Height: g.Height - tokens.MsgServicePadTop - tokens.MsgServicePadBottom,
	}
	svcH := p.serviceLineHeight(gtx)
	dateM := p.newMetric(gtx, fontRegular, unit.Sp(tokens.FontMsgDate), item.TimeText, 0, 0)
	badge := history.ServiceTimeBadgeMetrics(dateM.width, dateM.lineH, svcH)
	lineWidths := p.shapeLineWidths(gtx, fontSemibold, unit.Sp(tokens.FontMsgService), item.Text, trect.Width)
	add := history.ServiceLastLineWidthAdd(lineWidths, badge.AdditionalWidth)
	normal, inverted, _ := history.ServiceBubbleRadii(svcH)
	parts := history.ServiceComplexBubblePartsFont(g.Left, g.Width,
		history.CountServiceLineWidths(lineWidths, add), svcH)
	dy := g.Top - tokens.MsgServiceMarginTop
	for _, op := range history.ServiceBubbleOps(parts, normal, inverted) {
		op.Geometry.Top += dy
		if op.Kind == history.ServiceOpFlare {
			fillFlare(gtx, op, sch.InverseSurface)
		} else {
			fillCorners(gtx, op, sch.InverseSurface)
		}
	}
	p.label(gtx, trect, fontSemibold, unit.Sp(tokens.FontMsgService), item.Text, sch.InverseOnSurface)
	if item.TimeText == "" || badge.Width <= 0 || len(lineWidths) == 0 {
		return
	}
	x, y, _ := history.ServiceTimeBadgePosition(trect, lineWidths[len(lineWidths)-1],
		badge.AdditionalWidth, svcH, badge.Height, len(lineWidths))
	fillRRect(gtx, history.Geometry{Left: x, Top: y, Width: badge.Width, Height: badge.Height},
		badge.Height/2, badgeBg)
	p.label(gtx, history.Geometry{
		Left:   x + tokens.AyuServiceTimeBadgePadX,
		Top:    y + tokens.AyuServiceTimeBadgePadY,
		Width:  badge.Width - 2*tokens.AyuServiceTimeBadgePadX,
		Height: badge.Height - 2*tokens.AyuServiceTimeBadgePadY,
	}, fontRegular, unit.Sp(tokens.FontMsgDate), item.TimeText, sch.InverseOnSurface)
}

func (p *ChatPainter) paintMessage(gtx layout.Context, item history.Item, bar history.Bars, viewWidth, rowHeight int, sch material.Scheme) {
	if rowHeight <= 0 {
		return
	}
	mode := history.ChatModeFor(viewWidth)
	dateM := p.newMetric(gtx, fontRegular, unit.Sp(tokens.FontMsgDate), item.TimeText, 0, 0)
	hasTicks := item.Out || item.Sending
	skipW := 0
	if item.TimeText != "" {
		skipW = history.SkipBlockWidth(history.InfoWidth(dateM.width, hasTicks))
	}
	m := p.newMetric(gtx, fontRegular, unit.Sp(tokens.FontBase), item.Text, skipW, 0)
	c := history.MessageCtx{
		Mode:        mode,
		Out:         item.Out,
		Attached:    item.AttachedTop,
		Bubble:      true,
		VisibleText: item.Text != "",
		FromName:    item.FromName != "",
		NeedInfo:    item.TimeText != "",
		Bars:        bar,
	}
	nameM := p.newMetric(gtx, fontSemibold, unit.Sp(tokens.FontMsgName), item.FromName, 0, 0)
	nameLine := 0
	if c.FromName {
		nameLine = nameM.lineH
	}
	t := m.text()
	opt, nonText := history.MessageOptimalSize(t, c, nameM.width)
	contentWidth := history.MessageContentWidth(viewWidth, opt.Width, 0, c)
	_, realW := t.HeightFor(history.BubbleTextWidth(contentWidth))
	g := history.MessageGeometry(viewWidth, rowHeight, opt.Width, nonText, realW, 0, c)
	rounding := history.MessageRounding(item.AttachedTop, item.AttachedBottom, item.Out, item.SkipTail, false)
	bubbleFill(gtx, g, rounding, bubbleColor(sch, item.Out), shadowColor(item.Out))
	trect := history.Geometry{
		Left:   g.Left + tokens.MsgPaddingLeft,
		Top:    g.Top + tokens.MsgPaddingTop,
		Width:  g.Width - tokens.MsgPaddingLeft - tokens.MsgPaddingRight,
		Height: g.Height - tokens.MsgPaddingTop - tokens.MsgPaddingBottom,
	}
	bodyTop := trect.Top
	if c.FromName {
		p.label(gtx, history.Geometry{
			Left:   trect.Left,
			Top:    trect.Top,
			Width:  trect.Width,
			Height: nameLine,
		}, fontSemibold, unit.Sp(tokens.FontMsgName), item.FromName, fromNameColor(sch, item.Out))
		bodyTop += nameLine
	}
	if c.VisibleText {
		bodyW := trect.Width
		if skipW > 0 && bodyW > skipW {
			bodyW -= skipW
		}
		p.label(gtx, history.Geometry{
			Left:   trect.Left,
			Top:    bodyTop,
			Width:  bodyW,
			Height: trect.Height,
		}, fontRegular, unit.Sp(tokens.FontBase), item.Text, textColor(sch, item.Out))
	}
	if c.NeedInfo {
		tx, ty, ix, iy := history.TimeLabel(g, dateM.width, dateM.lineH, dateM.lineH, hasTicks)
		p.label(gtx, history.Geometry{
			Left:   tx,
			Top:    ty,
			Width:  dateM.width,
			Height: dateM.lineH,
		}, fontRegular, unit.Sp(tokens.FontMsgDate), item.TimeText, timeColor(sch, item.Out))
		if icon, ok := history.SendStateIcon(item.Out, item.Sending, item.Unread); ok {
			fillGlyph(gtx, ix, iy, icon, timeColor(sch, item.Out))
		}
	}
}

func (p *ChatPainter) paintUnreadBar(gtx layout.Context, item history.Item, viewWidth int, mode history.ChatMode, bar history.Bars, sch material.Scheme) {
	m := p.newMetric(gtx, fontSemibold, unit.Sp(tokens.HistoryUnreadBarFontHeight), item.UnreadBar, 0, 0)
	if m.width <= 0 {
		return
	}
	g := history.UnreadBarGeometry(bar.Date+bar.Thread, viewWidth, mode, m.width, m.lineH)
	fillPill(gtx, g.Pill, g.Radius, sch.SurfaceContainerLowest)
	p.label(gtx, g.Text, fontSemibold, unit.Sp(tokens.HistoryUnreadBarFontHeight), item.UnreadBar, sch.Primary)
}

func (p *ChatPainter) paintDateBadge(gtx layout.Context, text string, y, viewWidth int, mode history.ChatMode, alpha float32, sch material.Scheme) {
	m := p.newMetric(gtx, fontSemibold, unit.Sp(tokens.FontMsgService), text, 0, 0)
	if m.width <= 0 {
		return
	}
	g := history.DateBadgeGeometry(y, viewWidth, mode, m.width, m.lineH)
	fillRRect(gtx, g.Bubble, tokens.ServiceMsgRadius, withAlpha(sch.InverseSurface, alpha))
	p.label(gtx, g.Text, fontSemibold, unit.Sp(tokens.FontMsgService), text,
		withAlpha(sch.InverseOnSurface, alpha))
}

func bubbleFill(gtx layout.Context, g history.Geometry, rounding history.BubbleRounding, col, shadow color.NRGBA) {
	if s, ok := history.ShadowStrip(g, rounding, false); ok {
		fillRect(gtx, s, shadow)
	}
	spec := bubblePath(gtx, g, history.BubbleCorners(rounding, false), rounding)
	defer clip.Outline{Path: spec}.Op().Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, col)
}

func openCornersPath(gtx layout.Context, g history.Geometry, tl, tr, bl, br int) *clip.Path {
	x := float32(gtx.Dp(unit.Dp(g.Left)))
	y := float32(gtx.Dp(unit.Dp(g.Top)))
	w := float32(gtx.Dp(unit.Dp(g.Width)))
	h := float32(gtx.Dp(unit.Dp(g.Height)))
	rtl := float32(gtx.Dp(unit.Dp(tl)))
	rtr := float32(gtx.Dp(unit.Dp(tr)))
	rbl := float32(gtx.Dp(unit.Dp(bl)))
	rbr := float32(gtx.Dp(unit.Dp(br)))
	path := &clip.Path{}
	path.Begin(gtx.Ops)
	path.MoveTo(f32.Pt(x+rtl, y))
	path.LineTo(f32.Pt(x+w-rtr, y))
	arc(path, x+w-rtr, y+rtr, rtr)
	path.LineTo(f32.Pt(x+w, y+h-rbr))
	arc(path, x+w-rbr, y+h-rbr, rbr)
	path.LineTo(f32.Pt(x+rbl, y+h))
	arc(path, x+rbl, y+h-rbl, rbl)
	path.LineTo(f32.Pt(x, y+rtl))
	arc(path, x+rtl, y+rtl, rtl)
	return path
}

func fillCorners(gtx layout.Context, op history.ServiceBubbleOp, col color.NRGBA) {
	path := openCornersPath(gtx, op.Geometry, op.TL, op.TR, op.BL, op.BR)
	path.Close()
	defer clip.Outline{Path: path.End()}.Op().Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, col)
}

func fillFlare(gtx layout.Context, op history.ServiceBubbleOp, col color.NRGBA) {
	x := float32(gtx.Dp(unit.Dp(op.Geometry.Left)))
	y := float32(gtx.Dp(unit.Dp(op.Geometry.Top)))
	w := float32(gtx.Dp(unit.Dp(op.Geometry.Width)))
	h := float32(gtx.Dp(unit.Dp(op.Geometry.Height)))
	var path clip.Path
	path.Begin(gtx.Ops)
	switch op.Cut {
	case history.FlareCutBottomRight:
		path.MoveTo(f32.Pt(x+w, y))
		path.ArcTo(f32.Pt(x+w, y+h), f32.Pt(x+w, y+h), -math.Pi/2)
		path.LineTo(f32.Pt(x, y))
	case history.FlareCutBottomLeft:
		path.MoveTo(f32.Pt(x, y))
		path.ArcTo(f32.Pt(x, y+h), f32.Pt(x, y+h), math.Pi/2)
		path.LineTo(f32.Pt(x+w, y))
	case history.FlareCutTopRight:
		path.MoveTo(f32.Pt(x+w, y+h))
		path.ArcTo(f32.Pt(x+w, y), f32.Pt(x+w, y), math.Pi/2)
		path.LineTo(f32.Pt(x, y+h))
	case history.FlareCutTopLeft:
		path.MoveTo(f32.Pt(x+w, y))
		path.ArcTo(f32.Pt(x, y), f32.Pt(x, y), math.Pi/2)
		path.LineTo(f32.Pt(x+w, y+h))
	default:
		return
	}
	path.Close()
	defer clip.Outline{Path: path.End()}.Op().Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, col)
}

func bubblePath(gtx layout.Context, g history.Geometry, radii [4]int, rounding history.BubbleRounding) clip.PathSpec {
	path := openCornersPath(gtx, g, radii[0], radii[1], radii[2], radii[3])
	path.Close()
	tailW := float32(gtx.Dp(unit.Dp(tokens.MsgTailWidth)))
	tailH := float32(gtx.Dp(unit.Dp(tokens.MsgTailHeight)))
	x := float32(gtx.Dp(unit.Dp(g.Left)))
	y := float32(gtx.Dp(unit.Dp(g.Top)))
	w := float32(gtx.Dp(unit.Dp(g.Width)))
	h := float32(gtx.Dp(unit.Dp(g.Height)))
	leftTail, rightTail := history.BubbleTails(rounding, false)
	if leftTail {
		path.MoveTo(f32.Pt(x, y+h-tailH))
		path.LineTo(f32.Pt(x-tailW, y+h))
		path.LineTo(f32.Pt(x, y+h))
		path.Close()
	}
	if rightTail {
		path.MoveTo(f32.Pt(x+w, y+h-tailH))
		path.LineTo(f32.Pt(x+w+tailW, y+h))
		path.LineTo(f32.Pt(x+w, y+h))
		path.Close()
	}
	return path.End()
}

func arc(p *clip.Path, cx, cy, r float32) {
	if r <= 0 {
		return
	}
	p.ArcTo(f32.Pt(cx, cy), f32.Pt(cx, cy), math.Pi/2)
}

func bubbleColor(sch material.Scheme, out bool) color.NRGBA {
	if out {
		return sch.Primary
	}
	return sch.SurfaceContainerHigh
}

func shadowColor(out bool) color.NRGBA {
	if out {
		return outShadow
	}
	return inShadow
}

func textColor(sch material.Scheme, out bool) color.NRGBA {
	if out {
		return sch.OnPrimary
	}
	return sch.OnSurface
}

func fromNameColor(sch material.Scheme, out bool) color.NRGBA {
	if out {
		return sch.OnPrimary
	}
	return sch.Primary
}

func timeColor(sch material.Scheme, out bool) color.NRGBA {
	if out {
		return sch.OnPrimary
	}
	return sch.OnSurfaceVariant
}

func fillGlyph(gtx layout.Context, x, y int, icon icons.Icon, col color.NRGBA) {
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

func withAlpha(c color.NRGBA, a float32) color.NRGBA {
	if a >= 1 {
		return c
	}
	if a <= 0 {
		return color.NRGBA{A: 0}
	}
	c.A = uint8(float32(c.A) * a)
	return c
}

var downShadowColor = color.NRGBA{R: 0x00, G: 0x00, B: 0x00, A: 0x28}

func (p *ChatPainter) paintDownButton(gtx layout.Context, pane history.ChatPane, sch material.Scheme) {
	if pane.DownProgress <= 0 {
		return
	}
	g := history.DownButtonGeometry(pane.Width, pane.View.Height, pane.DownProgress)
	if g.Top >= pane.View.Height {
		return
	}
	circle := history.Geometry{
		Left:   g.Left + tokens.HistoryToDownCircleX,
		Top:    g.Top + tokens.HistoryToDownCircleY,
		Width:  tokens.HistoryToDownCircleSize,
		Height: tokens.HistoryToDownCircleSize,
	}
	shadow := circle
	shadow.Top += 2
	fillEllipse(gtx, shadow, downShadowColor)
	fillEllipse(gtx, circle, sch.PrimaryContainer)
	strokeDownArrow(gtx, g.Left, g.Top, sch.OnPrimaryContainer)
}

func (p *ChatPainter) paintMentionsButton(gtx layout.Context, pane history.ChatPane, sch material.Scheme) {
	if pane.MentionsProgress <= 0 {
		return
	}
	g := history.MentionsButtonGeometry(pane.Width, pane.View.Height,
		pane.MentionsProgress, pane.DownProgress)
	if g.Left >= pane.Width {
		return
	}
	circle := history.Geometry{
		Left:   g.Left + tokens.HistoryToDownCircleX,
		Top:    g.Top + tokens.HistoryToDownCircleY,
		Width:  tokens.HistoryToDownCircleSize,
		Height: tokens.HistoryToDownCircleSize,
	}
	shadow := circle
	shadow.Top += 2
	fillEllipse(gtx, shadow, downShadowColor)
	fillEllipse(gtx, circle, sch.PrimaryContainer)
	fillGlyph(gtx, g.Left, g.Top, icons.HistoryMention, sch.OnPrimaryContainer)
}

func fillEllipse(gtx layout.Context, r history.Geometry, col color.NRGBA) {
	rect := image.Rect(
		gtx.Dp(unit.Dp(r.Left)),
		gtx.Dp(unit.Dp(r.Top)),
		gtx.Dp(unit.Dp(r.Left+r.Width)),
		gtx.Dp(unit.Dp(r.Top+r.Height)),
	)
	defer clip.Ellipse(rect).Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, col)
}

func strokeDownArrow(gtx layout.Context, boxLeft, boxTop int, col color.NRGBA) {
	dp := func(v int) float32 {
		return float32(gtx.Dp(unit.Dp(v)))
	}
	w := float32(tokens.HistoryToDownArrowWidth)
	h := float32(tokens.HistoryToDownArrowHeight)
	half := float32(tokens.HistoryToDownArrowStroke) / 2
	cx := dp(boxLeft + tokens.HistoryToDownArrowCenterX)
	cy := dp(boxTop + tokens.HistoryToDownArrowCenterY)
	left := cx - w/2 + half
	top := cy - h/2 + half
	var path clip.Path
	path.Begin(gtx.Ops)
	path.MoveTo(f32.Pt(left, top))
	path.LineTo(f32.Pt(cx, cy+h/2-half))
	path.LineTo(f32.Pt(left+w-2*half, top))
	stroke := clip.Stroke{
		Path:  path.End(),
		Width: float32(gtx.Dp(unit.Dp(tokens.HistoryToDownArrowStroke))),
	}
	defer stroke.Op().Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, col)
}

func fillRRect(gtx layout.Context, r history.Geometry, radius int, col color.NRGBA) {
	rect := image.Rect(
		gtx.Dp(unit.Dp(r.Left)),
		gtx.Dp(unit.Dp(r.Top)),
		gtx.Dp(unit.Dp(r.Left+r.Width)),
		gtx.Dp(unit.Dp(r.Top+r.Height)),
	)
	defer clip.UniformRRect(rect, gtx.Dp(unit.Dp(radius))).Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, col)
}

func fillPill(gtx layout.Context, r history.Geometry, radius float32, col color.NRGBA) {
	x := float32(gtx.Dp(unit.Dp(r.Left)))
	y := float32(gtx.Dp(unit.Dp(r.Top)))
	w := float32(gtx.Dp(unit.Dp(r.Width)))
	h := float32(gtx.Dp(unit.Dp(r.Height)))
	if radius > h/2 {
		radius = h / 2
	}
	if radius > w/2 {
		radius = w / 2
	}
	var path clip.Path
	path.Begin(gtx.Ops)
	path.MoveTo(f32.Pt(x+radius, y))
	path.LineTo(f32.Pt(x+w-radius, y))
	arc(&path, x+w-radius, y+radius, radius)
	path.LineTo(f32.Pt(x+w, y+h-radius))
	arc(&path, x+w-radius, y+h-radius, radius)
	path.LineTo(f32.Pt(x+radius, y+h))
	arc(&path, x+radius, y+h-radius, radius)
	path.LineTo(f32.Pt(x, y+radius))
	arc(&path, x+radius, y+radius, radius)
	path.Close()
	defer clip.Outline{Path: path.End()}.Op().Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, col)
}

func fillRect(gtx layout.Context, r history.Geometry, col color.NRGBA) {
	defer clip.Rect{Min: image.Pt(
		gtx.Dp(unit.Dp(r.Left)),
		gtx.Dp(unit.Dp(r.Top)),
	), Max: image.Pt(
		gtx.Dp(unit.Dp(r.Left+r.Width)),
		gtx.Dp(unit.Dp(r.Top+r.Height)),
	)}.Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, col)
}

func (p *ChatPainter) label(gtx layout.Context, r history.Geometry, fnt font.Font, size unit.Sp, s string, col color.NRGBA) {
	if s == "" || r.Width <= 0 || r.Height <= 0 {
		return
	}
	macro := op.Record(gtx.Ops)
	paint.ColorOp{Color: col}.Add(gtx.Ops)
	mat := macro.Stop()
	defer op.Offset(image.Pt(gtx.Dp(unit.Dp(r.Left)), gtx.Dp(unit.Dp(r.Top)))).Push(gtx.Ops).Pop()
	gtx.Constraints = layout.Constraints{
		Max: image.Pt(gtx.Dp(unit.Dp(r.Width)), gtx.Dp(unit.Dp(r.Height))),
	}
	widget.Label{}.Layout(gtx, p.Shaper, fnt, size, s, mat)
}
