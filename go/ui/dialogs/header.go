package dialogs

import "uniclient/ui/tokens"

type HeaderView struct {
	Band         Rect
	Toggle       Rect
	Field        Rect
	Text         string
	Cursor       int
	Focused      bool
	CaretOn      bool
	Placeholder  string
	ToggleHover  bool
	ToggleRipple tokens.Ripple
}

func HeaderLayout(width int) HeaderView {
	fieldW := width - tokens.DialogsFilterLeftWithMenu - (tokens.DialogsFilterSkip + tokens.DialogsFilterPadX)
	if fieldW < 0 {
		fieldW = 0
	}
	return HeaderView{
		Band: Rect{X: 0, Y: 0, W: width, H: tokens.TopBarHeight},
		Toggle: Rect{
			X: tokens.MainMenuToggleX,
			Y: tokens.MainMenuToggleY,
			W: tokens.MainMenuToggleSize,
			H: tokens.MainMenuToggleSize,
		},
		Field: Rect{
			X: tokens.DialogsFilterLeftWithMenu,
			Y: (tokens.TopBarHeight - tokens.DialogsFilterHeight) / 2,
			W: fieldW,
			H: tokens.DialogsFilterHeight,
		},
	}
}

func HeaderToggleHit(width, x, y int) bool {
	t := HeaderLayout(width).Toggle
	return x >= t.X && x < t.X+t.W && y >= t.Y && y < t.Y+t.H
}

func HeaderFieldHit(width, x, y int) bool {
	f := HeaderLayout(width).Field
	return x >= f.X && x < f.X+f.W && y >= f.Y && y < f.Y+f.H
}
