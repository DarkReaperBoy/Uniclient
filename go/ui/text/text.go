package text

type Metrics struct {
	Height  int
	Leading int
	Advance func(rune) int
}

func (m Metrics) width(runes []rune) int {
	w := 0
	for _, r := range runes {
		w += m.Advance(r)
	}
	return w
}

func LineHeight(fontHeight, styleLineHeight int) int {
	if styleLineHeight > 0 && styleLineHeight > fontHeight {
		return styleLineHeight
	}
	return fontHeight
}

func LineAscent(m Metrics, lineHeight int) float64 {
	fixed := float64(LineHeight(m.Height, lineHeight))
	leading := float64(m.Leading)
	if leading < 0 {
		leading = 0
	}
	ascent := fixed*4/5 - leading
	if ascent < 0 {
		return 0
	}
	if ascent > fixed {
		return fixed
	}
	return ascent
}

func Elide(runes []rune, width int, m Metrics) []rune {
	if m.width(runes) <= width {
		return runes
	}
	for kept := len(runes) - 1; kept >= 0; kept-- {
		candidate := make([]rune, 0, kept+1)
		candidate = append(candidate, runes[:kept]...)
		candidate = append(candidate, '…')
		if m.width(candidate) <= width {
			return candidate
		}
	}
	return []rune{'…'}
}
