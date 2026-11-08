package history

import "uniclient/ui/tokens"

type Viewport struct {
	Top    int
	Height int
}

type ItemKind uint8

const (
	ItemMessage ItemKind = iota
	ItemService
)

type Item struct {
	Kind            ItemKind
	Text            string
	Out             bool
	AttachedTop     bool
	AttachedBottom  bool
	SkipTail        bool
	Sending         bool
	Unread          bool
	FromName        string
	TimeText        string
	DateText        string
	HideDisplayDate bool
	Empty           bool
	Sponsored       bool
	Hidden          bool
	UnreadBar       string
}

func (it Item) hideDisplayDate() bool {
	return it.Empty || it.HideDisplayDate
}

type List struct {
	Items   []Item
	Heights []int
	Hits    []HitBox
}

func (l List) RowHeight(i int) int {
	if i < 0 || i >= len(l.Heights) {
		return 0
	}
	return l.Heights[i]
}

func (l List) ContentHeight() int {
	total := 0
	for i := range l.Heights {
		total += l.Heights[i]
	}
	return total
}

func (l List) MaxOffset(v Viewport) int {
	m := l.ContentHeight() - v.Height
	if m < 0 {
		return 0
	}
	return m
}

func (l List) PreloadTopNeeded(v Viewport) bool {
	return len(l.Items) > 0 && v.Height > 0 &&
		v.Top < tokens.HistoryPreloadIfLessThanScreens*v.Height
}

func (l List) ClampOffset(top int, v Viewport) int {
	if top < 0 {
		return 0
	}
	if m := l.MaxOffset(v); top > m {
		return m
	}
	return top
}

func (l List) VisibleRows(v Viewport) (first, count int) {
	if len(l.Items) == 0 || v.Height <= 0 {
		return 0, 0
	}
	off := 0
	first = -1
	for i := range l.Items {
		h := l.RowHeight(i)
		if off+h-1 >= v.Top {
			first = i
			break
		}
		off += h
	}
	if first < 0 {
		return len(l.Items), 0
	}
	till := v.Top + v.Height
	for i := first; i < len(l.Items); i++ {
		if off >= till {
			break
		}
		count++
		off += l.RowHeight(i)
	}
	return first, count
}

func (l List) RowAt(y int) int {
	if y < 0 {
		return -1
	}
	off := 0
	for i := range l.Items {
		h := l.RowHeight(i)
		if y < off+h {
			return i
		}
		off += h
	}
	return -1
}

func (l List) rowTop(i int) int {
	top := 0
	for j := 0; j < i; j++ {
		top += l.RowHeight(j)
	}
	return top
}

type ChatPane struct {
	Width         int
	View          Viewport
	First         int
	Count         int
	Rows          []Item
	Ys            []int
	Heights       []int
	Bars          []Bars
	Thumb         Thumb
	ThumbDragging bool
	DateRow       int
	DateTop       int
	DateInPlace   bool
	DateText      string
	DateAlpha     float32
	DownProgress  float32
}

func (l List) Pane(v Viewport, width int) ChatPane {
	first, count := l.VisibleRows(v)
	pane := ChatPane{Width: width, View: v, First: first, Count: count,
		Thumb: l.ScrollbarThumb(v, v.Height), DateRow: -1}
	if count <= 0 {
		return pane
	}
	bars := ComposeBars(l.Items)
	date := l.ScrollDateAt(v, bars)
	pane.DateRow = date.Row
	pane.DateTop = date.Top
	pane.DateInPlace = date.InPlace
	if date.Row >= 0 && date.Row < len(l.Items) {
		pane.DateText = l.Items[date.Row].DateText
	}
	pane.Rows = make([]Item, count)
	pane.Ys = make([]int, count)
	pane.Heights = make([]int, count)
	pane.Bars = make([]Bars, count)
	for i := 0; i < count; i++ {
		idx := first + i
		pane.Rows[i] = l.Items[idx]
		pane.Ys[i] = l.rowTop(idx)
		pane.Heights[i] = l.RowHeight(idx)
		pane.Bars[i] = bars[idx]
	}
	return pane
}
