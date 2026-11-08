package history

import "uniclient/ui/tokens"

const MaxSelectedItems = 100

type SelectAction uint8

const (
	SelectInvert SelectAction = iota
	SelectAdd
	SelectRemove
)

func (it Item) CanBeSelected() bool {
	return it.Kind != ItemService && !it.Empty
}

type Selection map[int]bool

func (s Selection) HasSelectedItems() bool {
	return len(s) != 0
}

func (s Selection) InSelectionMode() bool {
	return len(s) != 0
}

func (s Selection) ContainsRow(row int) bool {
	return s[row]
}

func ChangeSelection(s Selection, row int, it Item, action SelectAction) Selection {
	if action == SelectInvert {
		if s[row] {
			action = SelectRemove
		} else {
			action = SelectAdd
		}
	}
	switch action {
	case SelectAdd:
		if !it.CanBeSelected() || s[row] || len(s) >= MaxSelectedItems {
			return s
		}
		out := make(Selection, len(s)+1)
		for k, v := range s {
			out[k] = v
		}
		out[row] = true
		return out
	case SelectRemove:
		if !s[row] {
			return s
		}
		if len(s) == 1 {
			return nil
		}
		out := make(Selection, len(s)-1)
		for k, v := range s {
			if k != row {
				out[k] = v
			}
		}
		return out
	}
	return s
}

type PointState uint8

const (
	PointOutside PointState = iota
	PointInside
)

type HitBox struct {
	Item Geometry
	Time Geometry
}

func (h HitBox) PointStateOf(it Item, x, y int) PointState {
	if h.Item.Width < 1 || it.Hidden {
		return PointOutside
	}
	if h.Item.Contains(x, y) {
		return PointInside
	}
	return PointOutside
}

func (h HitBox) TimeHit(x, y int) bool {
	return h.Time.Contains(x, y)
}

func TimeRect(g Geometry, infoWidth, dateFontHeight int, sendState bool) Geometry {
	textX, textY, _, _ := TimeLabel(g, infoWidth, dateFontHeight, dateFontHeight, sendState)
	width := infoWidth
	if sendState {
		width += tokens.HistorySendStateSpace
	}
	return Geometry{Left: textX, Top: textY, Width: width, Height: dateFontHeight}
}

func (g Geometry) Contains(x, y int) bool {
	return x >= g.Left && x < g.Left+g.Width && y >= g.Top && y < g.Top+g.Height
}
