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

func (d *Document) MoveStartOfWord(offset int) int {
	t, n := d.Text, len(d.Text)
	p := d.clampOffset(offset)
	if p == 0 {
		return 0
	}
	blockEnd := p == n || t[p] == '\n'
	if blockEnd && (t[p-1] == ' ' || t[p-1] == '\n' || isWordSeparator(t[p-1])) {
		return p
	}
	if !blockEnd {
		p++
	}
	for p > 0 && (t[p-1] == ' ' || t[p-1] == '\n') {
		p--
	}
	if p > 0 && isWordSeparator(t[p-1]) {
		for p > 0 && isWordSeparator(t[p-1]) && t[p-1] != '\n' {
			p--
		}
	} else {
		for p > 0 && t[p-1] != ' ' && t[p-1] != '\n' && !isWordSeparator(t[p-1]) {
			p--
		}
	}
	return p
}

func (d *Document) MoveEndOfWord(offset int) int {
	t, n := d.Text, len(d.Text)
	p := d.clampOffset(offset)
	if p >= n || t[p] == '\n' {
		return p
	}
	if isWordSeparator(t[p]) {
		for p < n && isWordSeparator(t[p]) && t[p] != '\n' {
			p++
		}
	} else {
		for p < n && t[p] != ' ' && t[p] != '\n' && !isWordSeparator(t[p]) {
			p++
		}
	}
	return p
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

func splice(runes []rune, lo, hi int, ins []rune) []rune {
	out := make([]rune, 0, len(runes)-(hi-lo)+len(ins))
	out = append(out, runes[:lo]...)
	out = append(out, ins...)
	out = append(out, runes[hi:]...)
	return out
}

func (d *Document) clampOffset(v int) int {
	if v < 0 {
		return 0
	}
	if v > len(d.Text) {
		return len(d.Text)
	}
	return v
}

func (d *Document) selectionRange(offset, anchor int) (int, int) {
	offset = d.clampOffset(offset)
	anchor = d.clampOffset(anchor)
	if offset <= anchor {
		return offset, anchor
	}
	return anchor, offset
}

func (d *Document) InsertAt(offset, anchor int, s string) (string, int) {
	ins := []rune(s)
	lo, hi := d.selectionRange(offset, anchor)
	if lo == hi {
		return string(splice(d.Text, lo, lo, ins)), lo + len(ins)
	}
	return string(splice(d.Text, lo, hi, ins)), lo + len(ins)
}

func (d *Document) DeleteBackward(offset, anchor int) (string, int) {
	lo, hi := d.selectionRange(offset, anchor)
	if lo != hi {
		return string(splice(d.Text, lo, hi, nil)), lo
	}
	if lo == 0 {
		return string(d.Text), 0
	}
	return string(splice(d.Text, lo-1, lo, nil)), lo - 1
}

func (d *Document) DeleteForward(offset, anchor int) (string, int) {
	lo, hi := d.selectionRange(offset, anchor)
	if lo != hi {
		return string(splice(d.Text, lo, hi, nil)), lo
	}
	if lo >= len(d.Text) {
		return string(d.Text), lo
	}
	return string(splice(d.Text, lo, lo+1, nil)), lo
}

func (d *Document) DeleteWordBackward(offset, anchor int) (string, int) {
	lo, hi := d.selectionRange(offset, anchor)
	if lo != hi {
		return string(splice(d.Text, lo, hi, nil)), lo
	}
	from := d.MoveWordLeft(lo)
	return string(splice(d.Text, from, lo, nil)), from
}

func (d *Document) DeleteWordForward(offset, anchor int) (string, int) {
	lo, hi := d.selectionRange(offset, anchor)
	if lo != hi {
		return string(splice(d.Text, lo, hi, nil)), lo
	}
	to := d.MoveWordRight(lo)
	return string(splice(d.Text, lo, to, nil)), lo
}
