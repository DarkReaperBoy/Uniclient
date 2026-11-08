package history

import "uniclient/ui/tokens"

func (l List) ScrollDateAnchor(v Viewport) (row, offset int) {
	if len(l.Items) == 0 || v.Height <= 0 {
		return -1, 0
	}
	row = l.RowAt(v.Top)
	if row < 0 {
		row = len(l.Items) - 1
	}
	for row >= 0 && row < len(l.Items) && l.Items[row].Sponsored {
		row++
	}
	if row < 0 || row >= len(l.Items) {
		return -1, 0
	}
	return row, v.Top - l.rowTop(row)
}

type ScrollDate struct {
	Row     int
	Top     int
	InPlace bool
}

func (l List) ScrollDateAt(v Viewport, bars []Bars) ScrollDate {
	anchor, _ := l.ScrollDateAnchor(v)
	if anchor < 0 || anchor >= len(bars) {
		return ScrollDate{Row: -1}
	}
	owner := anchor
	for owner >= 0 && (owner >= len(bars) || bars[owner].Date <= 0) {
		owner--
	}
	if owner < 0 || bars[owner].Date <= 0 {
		return ScrollDate{Row: -1}
	}
	packDate := l.Items[owner].DateText
	end := owner
	for end+1 < len(l.Items) && bars[end+1].Date <= 0 && l.Items[end+1].DateText == packDate {
		end++
	}
	dateHeight := tokens.MsgServicePadTop + tokens.FontMsgService + tokens.MsgServicePadBottom
	ownerTop := l.rowTop(owner)
	top := ownerTop
	if v.Top > top {
		top = v.Top
	}
	top += tokens.MsgServiceMarginTop
	packBottom := l.rowTop(end) + l.RowHeight(end) - tokens.MsgMarginBottom
	if limit := packBottom - dateHeight; top > limit {
		top = limit
	}
	return ScrollDate{
		Row:     owner,
		Top:     top,
		InPlace: top < ownerTop+tokens.MsgServiceMarginTop+dateHeight,
	}
}
