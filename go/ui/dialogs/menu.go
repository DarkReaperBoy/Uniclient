package dialogs

import "uniclient/ui/tokens"

type MenuAccountRow struct {
	Name   string
	Active bool
}

type MenuView struct {
	Slide           float32
	Fade            float32
	Width           int
	WindowW         int
	Height          int
	Rows            []MenuAccountRow
	CoverHasAccount bool
	CoverName       string
	CoverStatus     string
	FooterName      string
	FooterVersion   string
}

const menuAccountIconBox = 24

func MenuAccountUserpicLeft() int {
	return tokens.MainMenuAccountIconLeft + (menuAccountIconBox-MenuAccountUserpicFullSize())/2
}

func MenuAccountUserpicFullSize() int {
	skip := 2*tokens.MainMenuAccountRingLine + 1
	return tokens.MainMenuAccountUserpicSize + 2*skip
}

func MenuAccountSkip() int {
	return 2*tokens.MainMenuAccountRingLine + 1
}

func MenuRowY(i int) int {
	return tokens.MainMenuCoverHeight + tokens.MainMenuSkip + i*tokens.MainMenuAccountRowHeight
}

func MenuSeparatorY(rowCount int) int {
	return MenuRowY(rowCount) + tokens.MainMenuSkip
}
