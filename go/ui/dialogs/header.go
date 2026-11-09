package dialogs

import "uniclient/ui/tokens"

type HeaderView struct {
	Band        Rect
	Field       Rect
	Text        string
	Cursor      int
	Focused     bool
	CaretOn     bool
	Placeholder string
}

func HeaderLayout(width int) HeaderView {
	fieldW := width - tokens.DialogsFilterPadX - (tokens.DialogsFilterSkip + tokens.DialogsFilterPadX)
	if fieldW < 0 {
		fieldW = 0
	}
	return HeaderView{
		Band: Rect{X: 0, Y: 0, W: width, H: tokens.TopBarHeight},
		Field: Rect{
			X: tokens.DialogsFilterPadX,
			Y: (tokens.TopBarHeight - tokens.DialogsFilterHeight) / 2,
			W: fieldW,
			H: tokens.DialogsFilterHeight,
		},
	}
}

func HeaderFieldHit(width, x, y int) bool {
	f := HeaderLayout(width).Field
	return x >= f.X && x < f.X+f.W && y >= f.Y && y < f.Y+f.H
}
