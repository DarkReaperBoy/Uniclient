package history

import (
	"strconv"

	"uniclient/ui/tokens"
)

type SendButtonType int

const (
	SendTypeSend SendButtonType = iota
	SendTypeSchedule
	SendTypeSlowmode
	SendTypeSave
	SendTypeCancel
	SendTypeRecord
	SendTypeRound
	SendTypeStop
	SendTypeEditPrice
)

func SendButtonWidth(t SendButtonType) int {
	if t == SendTypeEditPrice {
		return 0
	}
	return tokens.HistorySendSizeW
}

func SendButtonHeight() int {
	return tokens.HistorySendSizeH
}

func SendButtonRipple(t SendButtonType) Geometry {
	return Geometry{
		Left:   (tokens.HistorySendSizeW - tokens.HistoryAttachRippleSize) / 2,
		Top:    tokens.HistoryAttachRippleY,
		Width:  tokens.HistoryAttachRippleSize,
		Height: tokens.HistoryAttachRippleSize,
	}
}

func SendButtonStopRect(w, h int) Geometry {
	left := (w - tokens.HistoryStopSizeW) / 2
	top := (h - tokens.HistoryStopSizeH) / 2
	return Geometry{Left: left, Top: top, Width: tokens.HistoryStopSizeW, Height: tokens.HistoryStopSizeH}
}

func SlowmodeDelayText(seconds int) string {
	if seconds <= 0 {
		return ""
	}
	rest := seconds % 60
	return strconv.Itoa(seconds/60) + ":" + pad2(rest)
}

func pad2(v int) string {
	if v < 10 {
		return "0" + strconv.Itoa(v)
	}
	return strconv.Itoa(v)
}

func SlowmodeTextRect(w, h int) Geometry {
	return Geometry{Left: 0, Top: 0, Width: w - tokens.HistorySlowmodeCounterRight, Height: h}
}
