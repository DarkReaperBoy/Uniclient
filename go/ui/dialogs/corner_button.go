package dialogs

import "uniclient/ui/tokens"

func (l List) ToUpShown(v Viewport, paneWidth int) bool {
	if paneWidth < tokens.DialogsRightButtonMinPaneWidth {
		return false
	}
	max := l.MaxOffset(paneWidth, v.Height)
	return v.Top > tokens.DialogsToUpShownAfter && v.Top < max
}

func ToUpGeometry(paneWidth, paneHeight int, progress float32) Rect {
	if progress < 0 {
		progress = 0
	}
	if progress > 1 {
		progress = 1
	}
	return Rect{
		X: paneWidth - tokens.HistoryToDownPositionX - tokens.HistoryToDownWidth,
		Y: paneHeight - int(float32(tokens.DialogsToUpTravel)*progress),
		W: tokens.HistoryToDownWidth,
		H: tokens.HistoryToDownHeight,
	}
}

func ToUpHit(paneWidth, paneHeight int, progress float32, x, y int) bool {
	g := ToUpGeometry(paneWidth, paneHeight, progress)
	return x >= g.X && x < g.X+g.W && y >= g.Y && y < g.Y+g.H
}
