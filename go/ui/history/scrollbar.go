package history

import "uniclient/ui/tokens"

func clampInt(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func oppositeSigns(a, b int) bool {
	return (a < 0 && b > 0) || (a > 0 && b < 0)
}

type Thumb struct {
	Y      int
	H      int
	Hidden bool
}

func (l List) ScrollbarThumb(v Viewport, trackH int) Thumb {
	fullSkip := tokens.HistoryScrollBarDeltat + tokens.HistoryScrollBarDeltab
	thickness := tokens.HistoryScrollBarWidth - 2*tokens.HistoryScrollBarDeltax
	contentH := l.ContentHeight()
	if contentH <= 0 || v.Height <= 0 || trackH < fullSkip+2*thickness {
		return Thumb{Hidden: true}
	}
	available := trackH - fullSkip
	barMin := tokens.ScrollBarThumbMin
	if half := available / 2; half < barMin {
		barMin = half
	}
	barWanted := available * v.Height / contentH
	if barWanted >= available {
		return Thumb{Hidden: true}
	}
	bar := barWanted
	if bar < barMin {
		bar = barMin
	}
	scrollable := contentH - v.Height
	barFrom := 0
	if scrollable > 0 {
		barFrom = (available - bar) * v.Top / scrollable
	}
	cutFrom := clampInt(barFrom, 0, available-thickness)
	cutTill := clampInt(barFrom+bar, thickness, available)
	return Thumb{
		Y: tokens.HistoryScrollBarDeltat + cutFrom,
		H: cutTill - cutFrom,
	}
}

func BarOver(t Thumb, x, y int) bool {
	if t.Hidden {
		return false
	}
	thickness := tokens.HistoryScrollBarWidth - 2*tokens.HistoryScrollBarDeltax
	return x >= tokens.HistoryScrollBarDeltax && x < tokens.HistoryScrollBarDeltax+thickness &&
		y >= t.Y && y < t.Y+t.H
}

func (l List) BarTrackJump(v Viewport, trackH, y int) int {
	thumb := l.ScrollbarThumb(v, trackH)
	if thumb.Hidden {
		return v.Top
	}
	fullSkip := tokens.HistoryScrollBarDeltat + tokens.HistoryScrollBarDeltab
	available := trackH - fullSkip
	bar := thumb.H
	half := bar / 2
	middle := clampInt(y,
		tokens.HistoryScrollBarDeltat+half,
		tokens.HistoryScrollBarDeltat+available+half-bar)
	scrollable := l.MaxOffset(v)
	return scrollable * (middle - half - tokens.HistoryScrollBarDeltat) / (available - bar)
}

func (l List) BarDragScale(v Viewport, trackH, dy int) int {
	thumb := l.ScrollbarThumb(v, trackH)
	if thumb.Hidden {
		return dy
	}
	fullSkip := tokens.HistoryScrollBarDeltat + tokens.HistoryScrollBarDeltab
	available := trackH - fullSkip
	outsideBar := available - thumb.H
	scrollable := l.MaxOffset(v)
	if outsideBar <= 0 || scrollable <= outsideBar {
		return dy
	}
	return dy * scrollable / outsideBar
}

func (l List) ApplyBarDrag(v Viewport, trackH, dy, accum int) (top, newAccum int) {
	change := l.BarDragScale(v, trackH, dy)
	if change == 0 {
		return v.Top, accum
	}
	if oppositeSigns(accum, change) {
		overscroll := accum + change
		if change < 0 {
			overscroll = maxInt(overscroll, 0)
		} else {
			overscroll = minInt(overscroll, 0)
		}
		change -= overscroll - accum
		accum = overscroll
	}
	if change == 0 {
		return v.Top, accum
	}
	scrollableTill := l.ContentHeight() - (v.Top + v.Height)
	now := clampInt(v.Top+change,
		minInt(v.Top, 0),
		maxInt(v.Top, v.Top+scrollableTill))
	if change != now-v.Top {
		if oppositeSigns(accum, change) {
			accum = change
		} else {
			accum = accum + change
		}
	}
	return now, accum
}
