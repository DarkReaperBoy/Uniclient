package history

import "uniclient/ui/tokens"

type CornerKind uint8

const (
	CornerNone CornerKind = iota
	CornerSmall
	CornerLarge
	CornerTail
)

type TailSide uint8

const (
	TailLeft TailSide = iota
	TailRight
)

type BubbleRounding struct {
	TopLeft     CornerKind
	TopRight    CornerKind
	BottomLeft  CornerKind
	BottomRight CornerKind
}

func MessageRounding(attachedTop, attachedBottom, rightLayout, skipTail, keyboard bool) BubbleRounding {
	r := BubbleRounding{
		TopLeft:     cornerOf(attachedTop, rightLayout, false),
		TopRight:    cornerOf(attachedTop, rightLayout, true),
		BottomLeft:  cornerOf(attachedBottom, rightLayout, false),
		BottomRight: cornerOf(attachedBottom, rightLayout, true),
	}
	if !skipTail {
		if !rightLayout {
			r.BottomLeft = cornerTail(attachedBottom)
		} else {
			r.BottomRight = cornerTail(attachedBottom)
		}
	}
	if keyboard {
		r.BottomLeft = CornerSmall
		r.BottomRight = CornerSmall
	}
	return r
}

func cornerOf(attached, right, rightSide bool) CornerKind {
	if attached && right == rightSide {
		return CornerSmall
	}
	return CornerLarge
}

func cornerTail(attached bool) CornerKind {
	if attached {
		return CornerSmall
	}
	return CornerTail
}

func CornerRadius(k CornerKind) int {
	switch k {
	case CornerLarge:
		return tokens.BubbleRadiusLarge
	case CornerSmall:
		return tokens.BubbleRadiusSmall
	}
	return 0
}

func effectiveCorner(k CornerKind, removeTail bool) CornerKind {
	if k == CornerTail && removeTail {
		return CornerLarge
	}
	return k
}

func BubbleCorners(r BubbleRounding, removeTail bool) [4]int {
	return [4]int{
		CornerRadius(effectiveCorner(r.TopLeft, removeTail)),
		CornerRadius(effectiveCorner(r.TopRight, removeTail)),
		CornerRadius(effectiveCorner(r.BottomLeft, removeTail)),
		CornerRadius(effectiveCorner(r.BottomRight, removeTail)),
	}
}

func BubbleTails(r BubbleRounding, removeTail bool) (left, right bool) {
	if removeTail {
		return false, false
	}
	return r.BottomLeft == CornerTail, r.BottomRight == CornerTail
}

func TailRect(side TailSide, g Geometry) Geometry {
	bottom := g.Top + g.Height
	switch side {
	case TailRight:
		return Geometry{
			Left:   g.Left + g.Width,
			Top:    bottom - tokens.MsgTailHeight,
			Width:  tokens.MsgTailWidth,
			Height: tokens.MsgTailHeight,
		}
	default:
		return Geometry{
			Left:   g.Left - tokens.MsgTailWidth,
			Top:    bottom - tokens.MsgTailHeight,
			Width:  tokens.MsgTailWidth,
			Height: tokens.MsgTailHeight,
		}
	}
}

func ShadowStrip(g Geometry, r BubbleRounding, removeTail bool) (Geometry, bool) {
	bottomLeft := effectiveCorner(r.BottomLeft, removeTail)
	bottomRight := effectiveCorner(r.BottomRight, removeTail)
	leftTail, rightTail := BubbleTails(r, removeTail)
	leftTailW, rightTailW := 0, 0
	if leftTail {
		leftTailW = tokens.MsgTailWidth
	}
	if rightTail {
		rightTailW = tokens.MsgTailWidth
	}
	shLeft := g.Left + CornerRadius(bottomLeft) - leftTailW
	shWidth := g.Left + g.Width - CornerRadius(bottomRight) + rightTailW - shLeft
	if shWidth <= 0 {
		return Geometry{}, false
	}
	return Geometry{
		Left:   shLeft,
		Top:    g.Top + g.Height,
		Width:  shWidth,
		Height: tokens.MsgShadow,
	}, true
}

func ServicePillRadius(serviceFontHeight int) int {
	return (tokens.MsgServicePadTop + serviceFontHeight + tokens.MsgServicePadBottom) / 2
}

func ServicePill(g Geometry, lineWidth, fontHeight int) Geometry {
	w := lineWidth + tokens.MsgServicePadLeft + tokens.MsgServicePadRight
	return Geometry{
		Left:   g.Left + (g.Width-w)/2,
		Top:    g.Top,
		Width:  w,
		Height: fontHeight + tokens.MsgServicePadTop + tokens.MsgServicePadBottom,
	}
}

func ServiceTimeBadgePosition(trect Geometry, lastLineWidth, additionalWidth, fontHeight, badgeHeight, lines int) (x, y, gap int) {
	lastTextWidth := lastLineWidth - additionalWidth
	if lastTextWidth < 0 {
		lastTextWidth = 0
	}
	if lastTextWidth > 0 {
		gap = tokens.AyuServiceTimeBadgeGap
	}
	x = trect.Left + (trect.Width-lastLineWidth)/2 + lastTextWidth + gap
	y = trect.Top + (lines-1)*fontHeight + (fontHeight-badgeHeight)/2
	return x, y, gap
}

func TimeLabel(g Geometry, infoWidth, infoHeight, dateFontHeight int, sendState bool) (textX, textY, iconX, iconY int) {
	infoRight := g.Left + g.Width - (tokens.MsgPaddingRight - tokens.MsgDateDeltaX)
	infoBottom := g.Top + g.Height - (tokens.MsgPaddingBottom - tokens.MsgDateDeltaY)
	textX = infoRight - infoWidth
	if sendState {
		textX -= tokens.HistorySendStateSpace
		iconX = infoRight + tokens.HistorySendStateDX
		iconY = infoBottom - infoHeight + dateFontHeight + tokens.HistorySendStateDY
	}
	textY = infoBottom - infoHeight
	return textX, textY, iconX, iconY
}
