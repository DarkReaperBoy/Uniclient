package text

func isWordSeparator(r rune) bool {
	switch r {
	case '.', ',', '?', '!', '@', '#', '$', ':', ';', '-',
		'<', '>', '[', ']', '(', ')', '{', '}', '=',
		'/', '+', '%', '&', '^', '*', '\'', '"', '`', '~', '|', '\\':
		return true
	}
	return false
}

func (d *Document) MoveLeft(offset, anchor int) int {
	if offset != anchor {
		if offset < anchor {
			return offset
		}
		return anchor
	}
	if offset > 0 {
		return offset - 1
	}
	return 0
}

func (d *Document) MoveRight(offset, anchor int) int {
	if offset != anchor {
		if offset > anchor {
			return offset
		}
		return anchor
	}
	if offset < len(d.Text) {
		return offset + 1
	}
	return offset
}

func (d *Document) MoveStartOfLine(offset int) int {
	return d.Lines[d.lineOf(offset)].Start
}

func (d *Document) MoveEndOfLine(offset int) int {
	return d.visibleEnd(d.lineOf(offset))
}

func (d *Document) MoveHome() int {
	return 0
}

func (d *Document) MoveEnd() int {
	return len(d.Text)
}

func (d *Document) MoveWordRight(offset int) int {
	t, n := d.Text, len(d.Text)
	p := offset
	if p >= n {
		return n
	}
	switch {
	case t[p] == '\n':
		return p + 1
	case isWordSeparator(t[p]):
		for p < n && isWordSeparator(t[p]) {
			p++
		}
	case t[p] != ' ':
		for p < n && t[p] != ' ' && t[p] != '\n' && !isWordSeparator(t[p]) {
			p++
		}
	}
	for p < n && t[p] == ' ' {
		p++
	}
	return p
}

func (d *Document) MoveWordLeft(offset int) int {
	t, n := d.Text, len(d.Text)
	p := offset
	if p <= 0 {
		return 0
	}
	if p > n {
		p = n
	}
	if t[p-1] == '\n' {
		return p - 1
	}
	for p > 0 && t[p-1] == ' ' {
		p--
	}
	if p > 0 && isWordSeparator(t[p-1]) {
		for p > 0 && isWordSeparator(t[p-1]) {
			p--
		}
	} else {
		for p > 0 && t[p-1] != ' ' && t[p-1] != '\n' && !isWordSeparator(t[p-1]) {
			p--
		}
	}
	return p
}

func (d *Document) XToColumn(lineIdx, x int) int {
	line := &d.Lines[lineIdx]
	visibleCols := d.visibleEnd(lineIdx) - line.Start
	if x <= 0 || visibleCols == 0 {
		return 0
	}
	best, bestDist, w := 0, -1, 0
	for col := 0; col <= visibleCols; col++ {
		if col > 0 {
			w += d.metrics.Advance(line.Runes[col-1])
		}
		dist := x - w
		if dist < 0 {
			dist = -dist
		}
		if bestDist < 0 || dist < bestDist {
			best, bestDist = col, dist
		}
	}
	return best
}

func (d *Document) MoveVertical(offset int, goalX int, hasGoalX bool, up bool) (int, int) {
	if !hasGoalX {
		goalX = d.CursorAt(offset).X
	}
	i := d.lineOf(offset)
	var target int
	if up {
		if i == 0 {
			return offset, goalX
		}
		target = i - 1
	} else {
		if i >= len(d.Lines)-1 {
			return offset, goalX
		}
		target = i + 1
	}
	return d.Lines[target].Start + d.XToColumn(target, goalX), goalX
}
