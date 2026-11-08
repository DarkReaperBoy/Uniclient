package history

import "uniclient/ui/tokens"

type ServiceSide uint8

const (
	ServiceSideRounded ServiceSide = iota
	ServiceSidePlain
	ServiceSideInverted
)

type ServiceBubblePart struct {
	Left       int
	Top        int
	Width      int
	Height     int
	TopSide    ServiceSide
	BottomSide ServiceSide
	Shrink     bool
}

type ServiceBands struct {
	TopBand    Geometry
	BottomBand Geometry
	Body       Geometry
}

type ServiceBubbleOpKind uint8

const (
	ServiceOpFill ServiceBubbleOpKind = iota
	ServiceOpFlare
)

type FlareCut uint8

const (
	FlareCutNone FlareCut = iota
	FlareCutTopLeft
	FlareCutTopRight
	FlareCutBottomLeft
	FlareCutBottomRight
)

type ServiceBubbleOp struct {
	Kind     ServiceBubbleOpKind
	Geometry Geometry
	TL       int
	TR       int
	BL       int
	BR       int
	Cut      FlareCut
}

func ServiceBubbleRadii(fontHeight int) (normal, inverted, shrink int) {
	normal = (tokens.MsgServicePadTop + fontHeight + tokens.MsgServicePadBottom) / 2
	inverted = fontHeight - normal
	shrink = (inverted * 2) / 3
	return normal, inverted, shrink
}

func ServiceLastLineWidthAdd(lineWidths []int, badgeAdditionalWidth int) int {
	if len(lineWidths) > 1 {
		back := lineWidths[len(lineWidths)-1]
		if back < 0 {
			back = 0
		}
		before := lineWidths[len(lineWidths)-2]
		if before < 0 {
			before = 0
		}
		if back > badgeAdditionalWidth && back < before {
			return tokens.AyuServiceTimeBadgeLastLineWidthAdd
		}
	}
	return 0
}

func CountServiceLineWidths(widths []int, lastLineWidthAdd int) []int {
	result := append([]int(nil), widths...)
	minDelta := 2 * (tokens.ServiceMsgRadius + tokens.ServiceMsgInvertedRadius -
		tokens.ServiceMsgInvertedShrink)
	for i := 0; i < len(result); i++ {
		width := result[i]
		if width < 0 {
			width = 0
		}
		if i > 0 {
			before := result[i-1]
			if width < before && width+minDelta > before {
				width = before
			}
		}
		if i+1 < len(result) {
			after := result[i+1]
			if width < after && width+minDelta > after {
				width = after
			}
		}
		if width > result[i] {
			result[i] = width
			if i > 0 {
				before := result[i-1]
				if before != width && before < width+minDelta && before+minDelta > width {
					i -= 2
				}
			}
		}
	}
	if lastLineWidthAdd > 0 && len(result) > 1 {
		back := len(result) - 1
		if result[back] > 0 && result[back] < result[back-1] {
			result[back] += lastLineWidthAdd
		}
	}
	return result
}

func ServiceComplexBubbleParts(left, width int, lineWidths []int) []ServiceBubblePart {
	return ServiceComplexBubblePartsFont(left, width, lineWidths, tokens.FontMsgService)
}

func ServiceComplexBubblePartsFont(left, width int, lineWidths []int, fontHeight int) []ServiceBubblePart {
	_, _, shrinkBy := ServiceBubbleRadii(fontHeight)
	parts := make([]ServiceBubblePart, 0, len(lineWidths))
	y := tokens.MsgServiceMarginTop
	previousRichWidth := 0
	previousShrink := false
	topSide := ServiceSideRounded
	for i, lineWidth := range lineWidths {
		bottomSide := ServiceSideRounded
		if i+1 < len(lineWidths) {
			next := lineWidths[i+1]
			switch {
			case next > lineWidth:
				bottomSide = ServiceSideInverted
			case next < lineWidth:
				bottomSide = ServiceSideRounded
			default:
				bottomSide = ServiceSidePlain
			}
		}
		richWidth := lineWidth + tokens.MsgServicePadLeft + tokens.MsgServicePadRight
		richHeight := fontHeight
		if topSide == ServiceSideRounded {
			richHeight += tokens.MsgServicePadTop
		} else if topSide == ServiceSideInverted {
			richHeight -= tokens.MsgServicePadBottom
		}
		if bottomSide == ServiceSideRounded {
			richHeight += tokens.MsgServicePadBottom
		} else if bottomSide == ServiceSideInverted {
			richHeight -= tokens.MsgServicePadTop
		}
		forceShrink := previousShrink && richWidth == previousRichWidth
		x := left + (width-richWidth)/2
		partWidth := richWidth
		shrink := forceShrink || topSide == ServiceSideInverted || bottomSide == ServiceSideInverted
		if shrink {
			x += shrinkBy
			partWidth -= 2 * shrinkBy
		}
		parts = append(parts, ServiceBubblePart{
			Left:       x,
			Top:        y,
			Width:      partWidth,
			Height:     richHeight,
			TopSide:    topSide,
			BottomSide: bottomSide,
			Shrink:     shrink,
		})
		y += richHeight
		previousShrink = shrink
		previousRichWidth = richWidth
		switch {
		case bottomSide == ServiceSideInverted:
			topSide = ServiceSideRounded
		case bottomSide == ServiceSideRounded:
			topSide = ServiceSideInverted
		default:
			topSide = ServiceSidePlain
		}
	}
	return parts
}

func ServiceBubbleOps(parts []ServiceBubblePart, normalRadius, invertedRadius int) []ServiceBubbleOp {
	ops := make([]ServiceBubbleOp, 0, 3*len(parts))
	for _, part := range parts {
		op := ServiceBubbleOp{Kind: ServiceOpFill, Geometry: Geometry{
			Left:   part.Left,
			Top:    part.Top,
			Width:  part.Width,
			Height: part.Height,
		}}
		if part.TopSide == ServiceSideRounded {
			op.TL = normalRadius
			op.TR = normalRadius
		}
		if part.BottomSide == ServiceSideRounded {
			op.BL = normalRadius
			op.BR = normalRadius
		}
		ops = append(ops, op)
		if part.TopSide == ServiceSideInverted {
			ops = append(ops,
				ServiceBubbleOp{Kind: ServiceOpFlare, Geometry: Geometry{
					Left:   part.Left - invertedRadius,
					Top:    part.Top,
					Width:  invertedRadius,
					Height: invertedRadius,
				}, Cut: FlareCutBottomRight},
				ServiceBubbleOp{Kind: ServiceOpFlare, Geometry: Geometry{
					Left:   part.Left + part.Width,
					Top:    part.Top,
					Width:  invertedRadius,
					Height: invertedRadius,
				}, Cut: FlareCutBottomLeft})
		}
		if part.BottomSide == ServiceSideInverted {
			ops = append(ops,
				ServiceBubbleOp{Kind: ServiceOpFlare, Geometry: Geometry{
					Left:   part.Left - invertedRadius,
					Top:    part.Top + part.Height - invertedRadius,
					Width:  invertedRadius,
					Height: invertedRadius,
				}, Cut: FlareCutTopRight},
				ServiceBubbleOp{Kind: ServiceOpFlare, Geometry: Geometry{
					Left:   part.Left + part.Width,
					Top:    part.Top + part.Height - invertedRadius,
					Width:  invertedRadius,
					Height: invertedRadius,
				}, Cut: FlareCutTopLeft})
		}
	}
	return ops
}

func (p ServiceBubblePart) Bands() ServiceBands {
	var bands ServiceBands
	topSkip := 0
	if p.TopSide == ServiceSideRounded {
		topSkip = tokens.ServiceMsgRadius
		bands.TopBand = Geometry{
			Left:   p.Left,
			Top:    p.Top,
			Width:  p.Width,
			Height: tokens.ServiceMsgRadius,
		}
	}
	bottomSkip := 0
	if p.BottomSide == ServiceSideRounded {
		bottomSkip = tokens.ServiceMsgRadius
		bands.BottomBand = Geometry{
			Left:   p.Left,
			Top:    p.Top + p.Height - tokens.ServiceMsgRadius,
			Width:  p.Width,
			Height: tokens.ServiceMsgRadius,
		}
	}
	bands.Body = Geometry{
		Left:   p.Left,
		Top:    p.Top + topSkip,
		Width:  p.Width,
		Height: p.Height - topSkip - bottomSkip,
	}
	return bands
}
