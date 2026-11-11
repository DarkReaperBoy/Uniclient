package dialogs

import "uniclient/ui/tokens"

type Viewport struct {
	Top    int
	Height int
}

func clampInt(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func (l List) MaxOffset(width, viewH int) int {
	if c := l.Height(width) - viewH; c > 0 {
		return c
	}
	return 0
}

func (l List) ClampOffset(off, width, viewH int) int {
	return clampInt(off, 0, l.MaxOffset(width, viewH))
}

func (l List) VisibleRows(v Viewport, width int) (first, last int) {
	if len(l.Rows) == 0 || v.Height <= 0 {
		return 0, 0
	}
	off := 0
	first = -1
	for i := range l.Rows {
		h := l.RowHeight(i, width)
		if off+h-1 >= v.Top {
			first = i
			break
		}
		off += h
	}
	if first < 0 {
		return len(l.Rows), len(l.Rows)
	}
	till := v.Top + v.Height
	last = first
	for i := first; i < len(l.Rows); i++ {
		if off >= till {
			break
		}
		last = i + 1
		off += l.RowHeight(i, width)
	}
	return first, last
}

func (l List) PreloadWindow(v Viewport) (from, to int) {
	return v.Top, v.Top + (tokens.PreloadScreens+1)*v.Height
}

func (l List) LoadMoreNeeded(v Viewport, width int) bool {
	return v.Top+tokens.PreloadScreens*v.Height >= l.Height(width)
}

func ScrollToReveal(top, bottom, current, viewH, max int) int {
	if top < 0 {
		top = 0
	} else if top > max {
		top = max
	}
	if bottom >= 0 && top >= current {
		if bottom < top {
			bottom = top
		}
		if bottom <= current+viewH {
			return current
		}
		to := bottom - viewH
		if to > top {
			to = top
		}
		return to
	}
	return top
}

type Thumb struct {
	Y      int
	H      int
	Hidden bool
}

type Pane struct {
	Width        int
	View         Viewport
	First        int
	Rows         []Entry
	RowYs        []int
	Selected     int
	Thumb        Thumb
	ToUpProgress float32
	ToUpHover    bool
	ToUpRipple   tokens.Ripple
	Header       HeaderView
	EmptyText    string

	Global      []Entry
	GlobalRowYs []int
	GlobalBar   bool
	GlobalBarY  int
	BarText     string
	GlobalFirst int

	SearchEmptyShown bool
	SearchEmptyTitle string
	SearchEmptyLine  string
}

func (l List) Pane(v Viewport, width int) Pane {
	p := Pane{
		Width:    width,
		View:     v,
		Selected: l.Selected,
		Thumb:    l.ScrollbarThumb(v, width, v.Height),
	}
	first, last := l.VisibleRows(v, width)
	if last > first {
		p.First = first
		p.Rows = l.Rows[first:last]
		off := 0
		for i := 0; i < first; i++ {
			off += l.RowHeight(i, width)
		}
		p.RowYs = make([]int, last-first)
		for i := first; i < last; i++ {
			p.RowYs[i-first] = off
			off += l.RowHeight(i, width)
		}
	}
	l.fillGlobalPane(&p, v, width)
	p.SearchEmptyShown = l.SearchEmptyShown
	p.SearchEmptyTitle = l.SearchEmptyTitle
	p.SearchEmptyLine = l.SearchEmptyLine
	return p
}

func (l List) fillGlobalPane(p *Pane, v Viewport, width int) {
	if !l.GlobalBar {
		return
	}
	p.GlobalBar = true
	p.GlobalBarY = l.Height(width) - l.globalHeight(width)
	p.BarText = l.BarText
	narrow := width < tokens.ColumnMinWidthLeft/2
	y := p.GlobalBarY + tokens.SearchedBarHeight
	for k := range l.Global {
		h := rowHeight(l.Global[k], narrow)
		if y+h > v.Top && y < v.Top+v.Height {
			if len(p.Global) == 0 {
				p.GlobalFirst = len(l.Rows) + k
			}
			p.Global = append(p.Global, l.Global[k])
			p.GlobalRowYs = append(p.GlobalRowYs, y)
		}
		y += h
	}
}

func (l List) ScrollbarThumb(v Viewport, width, trackH int) Thumb {
	fullSkip := tokens.ScrollBarDeltat + tokens.ScrollBarDeltab
	thickness := tokens.ScrollBarWidth - 2*tokens.ScrollBarDeltax
	contentH := l.Height(width)
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
		Y: tokens.ScrollBarDeltat + cutFrom,
		H: cutTill - cutFrom,
	}
}
