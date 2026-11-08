package history

import "uniclient/ui/tokens"

type ChatMode uint8

const (
	ModeNormal ChatMode = iota
	ModeWide
	ModeNarrow
)

type Bars struct {
	Date   int
	Unread int
	Thread int
}

type ServicePre struct {
	Below  bool
	Height int
}

type AddedMargins struct {
	Top    int
	Bottom int
}

type MessageCtx struct {
	Mode         ChatMode
	Hidden       bool
	Attached     bool
	Out          bool
	RightLayout  bool
	Centered     bool
	FromPhoto    bool
	FromName     bool
	Bubble       bool
	NeedInfo     bool
	VisibleText  bool
	Unlimited    bool
	RightActionW int
	Bars         Bars
	ServicePre   ServicePre
	Added        AddedMargins
}

type ServiceCtx struct {
	Mode             ChatMode
	Hidden           bool
	ServicePreBelow  bool
	ServicePreHeight int
	Bars             Bars
	Added            AddedMargins
	HasText          bool
}

type Text struct {
	MaxWidth  int
	MinHeight int
	HeightFor func(width int) (height, realWidth int)
}

type Fonts struct {
	NameHeight int
	DateHeight int
}

type Size struct {
	Width  int
	Height int
}

type Geometry struct {
	Left   int
	Top    int
	Width  int
	Height int
}

type ServiceTimeBadge struct {
	Width           int
	Height          int
	AdditionalWidth int
	SkipWidth       int
	SkipHeight      int
}

func DateBadgeHeight(serviceFontHeight int) int {
	return tokens.MsgServiceMarginTop + tokens.MsgServicePadTop + serviceFontHeight +
		tokens.MsgServicePadBottom + tokens.MsgServiceMarginBottom
}

func InfoWidth(dateWidth int, hasTicks bool) int {
	if hasTicks {
		return dateWidth + tokens.HistorySendStateSpace
	}
	return dateWidth
}

func SkipBlockWidth(infoWidth int) int {
	return tokens.MsgDateSpace + infoWidth - tokens.MsgDateDeltaX
}

func SkipBlockHeight(dateFontHeight int) int {
	return dateFontHeight - tokens.MsgDateDeltaY
}

func BubbleTextWidth(bubbleWidth int) int {
	floored := bubbleWidth
	if floored < tokens.MsgMinWidth {
		floored = tokens.MsgMinWidth
	}
	return floored - tokens.MsgPaddingLeft - tokens.MsgPaddingRight
}

func TextualMaxWidth(visibleText bool, textMaxWidth int) int {
	w := 0
	if visibleText {
		w = textMaxWidth
	}
	return tokens.MsgPaddingLeft + w + tokens.MsgPaddingRight
}

func ServiceTimeBadgeMetrics(timeTextWidth, timeFontHeight, serviceFontHeight int) ServiceTimeBadge {
	if timeTextWidth <= 0 {
		return ServiceTimeBadge{}
	}
	w := timeTextWidth + 2*tokens.AyuServiceTimeBadgePadX
	h := timeFontHeight + 2*tokens.AyuServiceTimeBadgePadY
	add := tokens.AyuServiceTimeBadgeGap + w + tokens.AyuServiceTimeBadgeTrailingInset - tokens.MsgServicePadRight
	if add < 0 {
		add = 0
	}
	skip := h
	if serviceFontHeight > skip {
		skip = serviceFontHeight
	}
	return ServiceTimeBadge{
		Width:           w,
		Height:          h,
		AdditionalWidth: add,
		SkipWidth:       add,
		SkipHeight:      skip,
	}
}

func BubbleWidthLimit(unlimited bool, monoMaxWidth int) int {
	if unlimited {
		return tokens.UnlimitedBubbleWidth
	}
	limit := tokens.MsgMaxWidth
	if monoMaxWidth > limit {
		limit = monoMaxWidth
	}
	return limit
}

func MessageMarginTop(c MessageCtx) int {
	result := 0
	if !c.Hidden {
		if c.Attached {
			result += tokens.MsgMarginTopAttached
		} else {
			result += tokens.MsgMarginTop
		}
	}
	result += c.Bars.Date
	result += c.Bars.Unread
	result += c.Bars.Thread
	if !c.ServicePre.Below {
		result += c.ServicePre.Height
	}
	result += c.Added.Top
	return result
}

func MessageMarginBottom(c MessageCtx) int {
	if c.Hidden {
		return 0
	}
	result := tokens.MsgMarginBottom
	if c.ServicePre.Below {
		result += c.ServicePre.Height
	}
	result += c.Added.Bottom
	return result
}

func ServiceMarginTop(c ServiceCtx) int {
	result := 0
	if !c.Hidden {
		result += tokens.MsgServiceMarginTop
	}
	result += c.Bars.Date
	result += c.Bars.Unread
	result += c.Bars.Thread
	result += c.ServicePreHeight
	result += c.Added.Top
	return result
}

func ServiceMarginBottom(c ServiceCtx) int {
	return tokens.MsgServiceMarginBottom + c.Added.Bottom
}

func MessageOptimalSize(t Text, c MessageCtx, fromNameWidth int) (Size, int) {
	if !c.Bubble {
		return Size{Width: tokens.MsgMinWidth, Height: 0}, 0
	}
	maxWidth := TextualMaxWidth(c.VisibleText, t.MaxWidth)
	minHeight := 0
	if c.VisibleText {
		minHeight = t.MinHeight
	}
	minHeight += tokens.MsgPaddingBottom
	minHeight += tokens.MsgPaddingTop
	nonTextMax := 0
	if c.FromName {
		namew := tokens.MsgPaddingLeft + fromNameWidth + tokens.MsgPaddingRight
		if namew > maxWidth {
			maxWidth = namew
		}
		if namew > nonTextMax {
			nonTextMax = namew
		}
	}
	return Size{Width: maxWidth, Height: minHeight}, nonTextMax
}

func wideSkipFor(mode ChatMode) int {
	if mode == ModeNarrow {
		return tokens.MsgMarginLeft
	}
	return tokens.MsgMarginRight
}

func availableWidthFor(viewWidth int, mode ChatMode, centered bool) int {
	if centered {
		return viewWidth - tokens.MsgMarginLeft - tokens.MsgMarginLeft
	}
	return viewWidth - tokens.MsgMarginLeft - wideSkipFor(mode)
}

func ChatModeFor(chatWidth int) ChatMode {
	if chatWidth >= tokens.AdaptiveChatWideWidth {
		return ModeWide
	}
	return ModeNormal
}

func MessageContentWidth(viewWidth, maxWidth, monoMaxWidth int, c MessageCtx) int {
	contentWidth := availableWidthFor(viewWidth, c.Mode, c.Centered)
	if c.FromPhoto && c.RightActionW > 0 {
		contentWidth -= c.RightActionW + (tokens.MsgPhotoSkip - tokens.HistoryFastShareSize)
	}
	if maxWidth < contentWidth {
		contentWidth = maxWidth
	}
	if limit := BubbleWidthLimit(c.Unlimited, monoMaxWidth); limit < contentWidth {
		contentWidth = limit
	}
	return contentWidth
}

func MessageGeometry(viewWidth, viewHeight, maxWidth, nonTextMaxWidth, realWidth, monoMaxWidth int, c MessageCtx) Geometry {
	available := availableWidthFor(viewWidth, c.Mode, c.Centered)
	left := wideSkipFor(c.Mode)
	if !c.RightLayout {
		left = tokens.MsgMarginLeft
	}
	if c.FromPhoto {
		left += tokens.MsgPhotoSkip
	}
	contentWidth := MessageContentWidth(viewWidth, maxWidth, monoMaxWidth, c)
	if realWidth > 0 {
		shrunk := realWidth + tokens.MsgPaddingLeft + tokens.MsgPaddingRight
		if nonTextMaxWidth > shrunk {
			shrunk = nonTextMaxWidth
		}
		if shrunk < contentWidth {
			contentWidth = shrunk
		}
	}
	if contentWidth < available && c.Mode != ModeWide {
		if c.Out {
			left += available - contentWidth
		} else if c.Centered {
			left += (available - contentWidth) / 2
		}
	} else if contentWidth < available && c.Centered {
		shift := (tokens.MsgMaxWidth + 2*tokens.MsgPhotoSkip - contentWidth) / 2
		if shift > 0 {
			left += shift
		}
	}
	top := MessageMarginTop(c)
	return Geometry{
		Left:   left,
		Top:    top,
		Width:  contentWidth,
		Height: viewHeight - top - MessageMarginBottom(c),
	}
}

func MessageHeight(viewWidth, maxWidth, minHeight, nonTextMaxWidth, bottomInfoHeight, monoMaxWidth int, t Text, c MessageCtx, f Fonts) int {
	contentWidth := MessageContentWidth(viewWidth, maxWidth, monoMaxWidth, c)
	if c.Bubble && c.VisibleText && t.HeightFor != nil {
		_, real := t.HeightFor(BubbleTextWidth(contentWidth))
		if real > 0 {
			shrunk := real + tokens.MsgPaddingLeft + tokens.MsgPaddingRight
			if nonTextMaxWidth > shrunk {
				shrunk = nonTextMaxWidth
			}
			if shrunk < contentWidth {
				contentWidth = shrunk
			}
		}
	}
	textWidth := BubbleTextWidth(contentWidth)
	height := minHeight
	if c.Bubble {
		if contentWidth != maxWidth {
			height = 0
			if c.VisibleText && t.HeightFor != nil {
				h, _ := t.HeightFor(textWidth)
				height += h
			}
			height += tokens.MsgPaddingBottom
			height += tokens.MsgPaddingTop
		}
		if c.FromName {
			height += f.NameHeight
		}
		if c.NeedInfo {
			height += bottomInfoHeight - f.DateHeight
		}
	} else {
		height = 0
	}
	height += MessageMarginTop(c) + MessageMarginBottom(c)
	return height
}

func ServiceOptimalSize(t Text) Size {
	return Size{
		Width:  t.MaxWidth + tokens.MsgServicePadLeft + tokens.MsgServicePadRight,
		Height: t.MinHeight,
	}
}

func serviceWideLimit() int {
	return tokens.MsgMaxWidth + 2*tokens.MsgPhotoSkip + 2*tokens.MsgMarginLeft
}

func ServiceGeometry(viewWidth, viewHeight int, c ServiceCtx) Geometry {
	w := viewWidth
	if c.Mode == ModeWide {
		if limit := serviceWideLimit(); limit < w {
			w = limit
		}
	}
	top := ServiceMarginTop(c)
	return Geometry{
		Left:   tokens.MsgServiceMarginLeft,
		Top:    top,
		Width:  w - tokens.MsgServiceMarginLeft - tokens.MsgServiceMarginRight,
		Height: viewHeight - top - tokens.MsgServiceMarginBottom,
	}
}

func ServiceHeight(viewWidth, maxWidth, minHeight int, t Text, c ServiceCtx) int {
	height := ServiceMarginTop(c)
	if c.Hidden {
		return height
	}
	contentWidth := viewWidth
	if c.Mode == ModeWide {
		if limit := serviceWideLimit(); limit < contentWidth {
			contentWidth = limit
		}
	}
	contentWidth -= 2 * tokens.MsgServiceMarginLeft
	if floor := tokens.MsgServicePadLeft + tokens.MsgServicePadRight + 1; contentWidth < floor {
		contentWidth = floor
	}
	nwidth := contentWidth - tokens.MsgServicePadLeft - tokens.MsgServicePadRight
	if nwidth < 0 {
		nwidth = 0
	}
	if c.HasText {
		if contentWidth >= maxWidth {
			height += minHeight
		} else if t.HeightFor != nil {
			h, _ := t.HeightFor(nwidth)
			height += h
		}
		height += tokens.MsgServicePadTop + tokens.MsgServicePadBottom
		height += ServiceMarginBottom(c)
	} else {
		height -= tokens.MsgServiceMarginTop
	}
	return height
}
