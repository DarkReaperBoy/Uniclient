package history

import (
	"uniclient/ui/text"
	"uniclient/ui/tokens"
)

type ComposeButtons struct {
	Attach bool
	Emoji  bool
}

type ComposeBar struct {
	Attach Geometry
	Field  Geometry
	Send   Geometry
	Emoji  Geometry
}

type ComposePlaceholderView struct {
	Text     string
	X        int
	Baseline float64
	Opacity  float64
}

type ComposePaneView struct {
	Shown       bool
	Geometry    ComposeBar
	LineHeight  int
	Scroll      int
	Lines       []text.Line
	Caret       Geometry
	Selection   []text.Span
	Placeholder ComposePlaceholderView
}

func ComposeBarHeight(fieldHeight int) int {
	return fieldHeight + 2*tokens.HistorySendPadding
}

func ComposeFieldMaxHeight(paneHeight, reservedAbove int, replyShown bool) int {
	max := paneHeight - reservedAbove - 2*tokens.HistorySendPadding - tokens.HistoryReplyHeight
	if replyShown {
		max -= tokens.HistoryReplyHeight
	}
	if tokens.ComposeFieldRichMax < max {
		return tokens.ComposeFieldRichMax
	}
	return max
}

func ComposeFieldHeight(canSendTexts bool, contentHeight, maxHeight int) int {
	if !canSendTexts {
		return tokens.HistorySendSizeH - 2*tokens.HistorySendPadding
	}
	min := tokens.ComposeFieldHeightMin
	if maxHeight < min {
		min = maxHeight
	}
	switch {
	case contentHeight < min:
		return min
	case contentHeight > maxHeight:
		return maxHeight
	}
	return contentHeight
}

func ComposeFieldWidth(paneWidth int, b ComposeButtons) int {
	w := paneWidth - tokens.HistorySendRight - tokens.HistorySendSizeW
	if b.Attach {
		w -= tokens.HistoryAttachSizeW
	}
	if b.Emoji {
		w -= tokens.HistorySendSizeW
	}
	return w
}

func ComposeBarGeometry(paneWidth, paneHeight, fieldHeight int, b ComposeButtons) ComposeBar {
	buttonsBottom := paneHeight - tokens.HistorySendSizeH
	fieldLeft := tokens.HistorySendRight
	fieldWidth := ComposeFieldWidth(paneWidth, b)
	if b.Attach {
		fieldLeft += tokens.HistoryAttachSizeW
	}
	bar := ComposeBar{
		Field: Geometry{
			Left:   fieldLeft,
			Top:    paneHeight - fieldHeight - tokens.HistorySendPadding,
			Width:  fieldWidth,
			Height: fieldHeight,
		},
		Send: Geometry{
			Left:   paneWidth - tokens.HistorySendRight - tokens.HistorySendSizeW,
			Top:    buttonsBottom,
			Width:  tokens.HistorySendSizeW,
			Height: tokens.HistorySendSizeH,
		},
	}
	if b.Attach {
		bar.Attach = Geometry{
			Left:   tokens.HistorySendRight,
			Top:    buttonsBottom,
			Width:  tokens.HistoryAttachSizeW,
			Height: tokens.HistoryAttachSizeH,
		}
	}
	if b.Emoji {
		bar.Emoji = Geometry{
			Left:   paneWidth - tokens.HistorySendRight - 2*tokens.HistorySendSizeW,
			Top:    buttonsBottom,
			Width:  tokens.HistorySendSizeW,
			Height: tokens.HistorySendSizeH,
		}
	}
	return bar
}

func ComposeScrollHeight(paneHeight, fieldHeight int, canSendMessages bool) int {
	if !canSendMessages {
		return paneHeight
	}
	return paneHeight - ComposeBarHeight(fieldHeight)
}
