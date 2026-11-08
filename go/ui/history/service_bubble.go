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
		richHeight := tokens.FontMsgService
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
			x += tokens.ServiceMsgInvertedShrink
			partWidth -= 2 * tokens.ServiceMsgInvertedShrink
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
