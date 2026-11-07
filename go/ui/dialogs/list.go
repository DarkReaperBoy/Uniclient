package dialogs

import "uniclient/ui/tokens"

type List struct {
	Rows     []Entry
	Selected int
}

func (l List) RowHeight(i, width int) int {
	if i < 0 || i >= len(l.Rows) {
		return 0
	}
	return rowHeight(l.Rows[i], width < tokens.ColumnMinWidthLeft/2)
}

func (l List) Height(width int) int {
	total := 0
	for i := range l.Rows {
		total += l.RowHeight(i, width)
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
	return -1
}
