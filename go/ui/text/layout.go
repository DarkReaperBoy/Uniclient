package text

type Line struct {
	Start int
	Runes []rune
	Width int
}

type Document struct {
	Text    []rune
	Lines   []Line
	metrics Metrics
}

type Cursor struct {
	Line   int
	Column int
	X      int
}

func Layout(s string, width int, m Metrics) *Document {
	if width < 0 {
		width = 0
	}
	rs := []rune(s)
	d := &Document{Text: rs, metrics: m}
	lineStart := 0
	var cur []rune
	curW := 0
	emit := func() {
		d.Lines = append(d.Lines, Line{Start: lineStart, Runes: cur, Width: curW})
		cur = nil
		curW = 0
	}
	i, n := 0, len(rs)
	for i < n {
		switch {
		case rs[i] == '\n':
			emit()
			i++
			lineStart = i
		case rs[i] == ' ':
			for i < n && rs[i] == ' ' {
				cur = append(cur, ' ')
				curW += m.Advance(' ')
				i++
			}
		default:
			k := i
			for k < n && rs[k] != ' ' && rs[k] != '\n' {
				k++
			}
			word := rs[i:k]
			wordW := m.width(word)
			if len(cur) == 0 {
				if wordW <= width {
					cur = append(cur, word...)
					curW += wordW
					i = k
					continue
				}
				consumed := 0
				for len(word) > 0 {
					take, takeW := 0, 0
					for take < len(word) {
						next := takeW + m.Advance(word[take])
						if take > 0 && next > width {
							break
						}
						takeW = next
						take++
					}
					cur = append(cur, word[:take]...)
					curW += takeW
					consumed += take
					word = word[take:]
					if len(word) > 0 {
						emit()
						lineStart = i + consumed
					}
				}
				i = k
			} else if curW+wordW <= width {
				cur = append(cur, word...)
				curW += wordW
				i = k
			} else {
				emit()
				lineStart = i
			}
		}
	}
	emit()
	return d
}

func (d *Document) Height(lineHeight int) int {
	return len(d.Lines) * lineHeight
}

func (d *Document) CursorAt(offset int) Cursor {
	if offset < 0 {
		offset = 0
	}
	if offset > len(d.Text) {
		offset = len(d.Text)
	}
	line := 0
	for i := range d.Lines {
		if d.Lines[i].Start <= offset {
			line = i
		}
	}
	c := Cursor{Line: line, Column: offset - d.Lines[line].Start}
	for _, r := range d.Lines[line].Runes[:c.Column] {
		c.X += d.metrics.Advance(r)
	}
	return c
}
