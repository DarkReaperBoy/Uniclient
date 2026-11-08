package history

import "uniclient/ui/tokens"

func UnreadBarHeight() int {
	return tokens.HistoryUnreadBarHeight + tokens.HistoryUnreadBarMargin
}

func UnreadBarMarginTop() int {
	return tokens.LineWidth + tokens.HistoryUnreadBarMargin
}

func UnreadBarWidth(textWidth int) int {
	return textWidth + 2*tokens.UnreadPillPadding
}

type UnreadBarPaint struct {
	Pill   Geometry
	Radius float32
	Text   Geometry
}

func UnreadBarGeometry(y, viewWidth int, mode ChatMode, textWidth, fontHeight int) UnreadBarPaint {
	w := viewWidth
	if mode == ModeWide {
		if limit := serviceWideLimit(); limit < w {
			w = limit
		}
	}
	pillW := UnreadBarWidth(textWidth)
	pillH := UnreadBarHeight() - UnreadBarMarginTop()
	pill := Geometry{
		Left:   (w - pillW) / 2,
		Top:    y + UnreadBarMarginTop(),
		Width:  pillW,
		Height: pillH,
	}
	return UnreadBarPaint{
		Pill:   pill,
		Radius: float32(pillH) / 2,
		Text: Geometry{
			Left:   (w - textWidth) / 2,
			Top:    pill.Top + (pillH-fontHeight)/2,
			Width:  textWidth,
			Height: fontHeight,
		},
	}
}

type DateBadgePaint struct {
	Bubble Geometry
	Text   Geometry
}

func DateBadgeGeometry(y, viewWidth int, mode ChatMode, textWidth, fontHeight int) DateBadgePaint {
	left := tokens.MsgServiceMarginLeft
	maxw := viewWidth
	if mode == ModeWide {
		if limit := serviceWideLimit(); limit < maxw {
			maxw = limit
		}
	}
	w := maxw - tokens.MsgServiceMarginLeft - tokens.MsgServiceMarginLeft
	left += (w - textWidth - tokens.MsgServicePadLeft - tokens.MsgServicePadRight) / 2
	bubble := Geometry{
		Left:   left,
		Top:    y + tokens.MsgServiceMarginTop,
		Width:  textWidth + tokens.MsgServicePadLeft + tokens.MsgServicePadLeft,
		Height: tokens.MsgServicePadTop + tokens.FontMsgService + tokens.MsgServicePadBottom,
	}
	return DateBadgePaint{
		Bubble: bubble,
		Text: Geometry{
			Left:   left + tokens.MsgServicePadLeft,
			Top:    bubble.Top + tokens.MsgServicePadTop,
			Width:  textWidth,
			Height: fontHeight,
		},
	}
}

func ComposeBars(items []Item) []Bars {
	if items == nil {
		return nil
	}
	bars := make([]Bars, len(items))
	prevDisplayed := -1
	for i := range items {
		it := items[i]
		var bar Bars
		if it.DateText != "" && !it.hideDisplayDate() {
			display := false
			if !it.Hidden && !it.Empty && !it.Sponsored {
				if prevDisplayed < 0 {
					display = true
				} else {
					prev := items[prevDisplayed]
					display = prev.hideDisplayDate() || prev.DateText != it.DateText
				}
			}
			if display {
				bar.Date = DateBadgeHeight(tokens.FontMsgService)
			}
		}
		if it.UnreadBar != "" {
			bar.Unread = UnreadBarHeight()
		}
		bars[i] = bar
		if !(it.Empty || it.Hidden) {
			prevDisplayed = i
		}
	}
	return bars
}
