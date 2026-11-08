package history

import "uniclient/ui/tokens"

func (l List) firstUnreadRow() int {
	for i := range l.Items {
		if l.Items[i].UnreadBar != "" {
			return i
		}
	}
	return -1
}

func (l List) DownShown(v Viewport) bool {
	if len(l.Items) == 0 || v.Height <= 0 {
		return false
	}
	if v.Top+tokens.HistoryToDownShownAfter < l.MaxOffset(v) {
		return true
	}
	row := l.firstUnreadRow()
	if row < 0 {
		return false
	}
	return l.rowTop(row) >= v.Top+v.Height
}

func (l List) DownJumpTop(v Viewport) int {
	max := l.MaxOffset(v)
	row := l.firstUnreadRow()
	if row < 0 {
		return max
	}
	top := l.rowTop(row)
	if top < 0 {
		return 0
	}
	if top > max {
		return max
	}
	return top
}

func DownButtonGeometry(paneWidth, paneHeight int, progress float32) Geometry {
	if progress < 0 {
		progress = 0
	}
	if progress > 1 {
		progress = 1
	}
	travel := float32(tokens.HistoryToDownHeight + tokens.HistoryToDownPositionY)
	return Geometry{
		Left:   paneWidth - tokens.HistoryToDownPositionX - tokens.HistoryToDownWidth,
		Top:    paneHeight - int(travel*progress),
		Width:  tokens.HistoryToDownWidth,
		Height: tokens.HistoryToDownHeight,
	}
}

func DownButtonHit(paneWidth, paneHeight int, progress float32, x, y int) bool {
	g := DownButtonGeometry(paneWidth, paneHeight, progress)
	return x >= g.Left && x < g.Left+g.Width && y >= g.Top && y < g.Top+g.Height
}
