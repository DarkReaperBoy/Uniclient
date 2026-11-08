package history

import (
	"math"

	"uniclient/ui/text"
	"uniclient/ui/tokens"
)

func ComposeFieldWrapWidth(innerWidth int) int {
	w := innerWidth - tokens.ComposeCaretReserve
	if w < 0 {
		return 0
	}
	return w
}

func ComposeFieldDocument(s string, innerWidth int, m text.Metrics) *text.Document {
	return text.Layout(s, ComposeFieldWrapWidth(innerWidth), m)
}

func ComposeFieldContentHeight(s string, innerWidth int, m text.Metrics) int {
	doc := ComposeFieldDocument(s, innerWidth, m)
	return doc.Height(text.LineHeight(m.Height, tokens.ComposeFieldStyleLineHeight))
}

func ComposePlaceholderShown(textLen int) bool {
	return textLen == 0
}

func ComposePlaceholderMaxWidth(fieldWidth int) int {
	w := fieldWidth
	w -= tokens.ComposeTextMarginLeft + tokens.ComposeTextMarginRight
	w -= tokens.ComposePlaceholderMarginLeft + tokens.ComposePlaceholderMarginRight
	if w < 0 {
		return 0
	}
	return w
}

func ComposePlaceholderText(placeholder string, fieldWidth int, m text.Metrics) string {
	return string(text.Elide([]rune(placeholder), ComposePlaceholderMaxWidth(fieldWidth), m))
}

func interpolateInt(from, to int, ratio float64) int {
	return int(math.Round(float64(from) + float64(to-from)*ratio))
}

func ComposePlaceholderX(hiddenDegree float64) int {
	drift := interpolateInt(0, -tokens.ComposePlaceholderShift, hiddenDegree)
	return tokens.ComposeTextMarginLeft + tokens.ComposePlaceholderMarginLeft + drift
}

func ComposePlaceholderBaseline(m text.Metrics) float64 {
	top := tokens.ComposeTextMarginTop + tokens.ComposePlaceholderMarginTop
	return float64(top) + text.LineAscent(m, text.LineHeight(m.Height, tokens.ComposeFieldStyleLineHeight))
}

func ComposePlaceholderOpacity(hiddenDegree float64) float64 {
	return 1 - hiddenDegree
}
