package dialogs

import "uniclient/ui/tokens"

type List struct {
	Rows     []Entry
	Selected int

	Global    []Entry
	GlobalBar bool
	BarText   string

	SearchEmptyShown bool
	SearchEmptyTitle string
	SearchEmptyLine  string
}

func SearchEmptyQueryPreview(query string) string {
	runes := []rune(query)
	if len(runes) <= searchEmptyQueryLimit {
		return query
	}
	return string(runes[:searchEmptyQueryLimit])
}

const searchEmptyQueryLimit = 32

func (l List) RowCount() int {
	return len(l.Rows) + len(l.Global)
}

func (l List) EntryAt(i int) Entry {
	if i < len(l.Rows) {
		return l.Rows[i]
	}
	if g := i - len(l.Rows); g < len(l.Global) {
		return l.Global[g]
	}
	return Entry{}
}

func (l List) globalHeight(width int) int {
	if !l.GlobalBar {
		return 0
	}
	total := tokens.SearchedBarHeight
	narrow := width < tokens.ColumnMinWidthLeft/2
	for i := range l.Global {
		total += rowHeight(l.Global[i], narrow)
	}
	return total
}

func (l List) RowHeight(i, width int) int {
	if i < 0 || i >= len(l.Rows) {
		return 0
	}
	return rowHeight(l.Rows[i], width < tokens.ColumnMinWidthLeft/2)
}

func (l List) Height(width int) int {
	total := l.globalHeight(width)
	for i := range l.Rows {
		total += l.RowHeight(i, width)
	}
	if l.SearchEmptyShown {
		total += tokens.SearchEmptyHeightMin
	}
	return total
}

func (l List) RowAt(y, width int) int {
	if y < 0 {
		return -1
	}
	off := 0
	for i := range l.Rows {
		h := l.RowHeight(i, width)
		if y < off+h {
			return i
		}
		off += h
	}
	if l.GlobalBar {
		if y < off+tokens.SearchedBarHeight {
			return -1
		}
		off += tokens.SearchedBarHeight
		narrow := width < tokens.ColumnMinWidthLeft/2
		for k := range l.Global {
			h := rowHeight(l.Global[k], narrow)
			if y < off+h {
				return len(l.Rows) + k
			}
			off += h
		}
	}
	return -1
}
