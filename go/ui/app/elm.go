package app

import (
	"image/color"
	"math"

	"uniclient/ui/material"
	"uniclient/ui/tokens"
)

type Msg interface{ isMsg() }

type Resized struct {
	Width  int
	Height int
}

func (Resized) isMsg() {}

type Quit struct{}

func (Quit) isMsg() {}

type Cmd func() Msg

type Model struct {
	Width      int
	Height     int
	HasDialogs bool
	ThirdPane  bool
	Running    bool
}

func InitialModel() Model {
	return Model{HasDialogs: true, Running: true}
}

func Update(m Model, msg Msg) (Model, Cmd) {
	switch msg := msg.(type) {
	case Resized:
		if msg.Width < 0 {
			msg.Width = 0
		}
		if msg.Height < 0 {
			msg.Height = 0
		}
		m.Width = msg.Width
		m.Height = msg.Height
		return m, nil
	case Quit:
		m.Running = false
		return m, nil
	}
	return m, nil
}

type PaneMode int

const (
	PaneSingle PaneMode = iota
	PaneDouble
	PaneTriple
)

type Columns struct {
	Dialogs int
	Chat    int
	Third   int
}

func (m Model) PaneMode() PaneMode {
	if m.HasDialogs && m.Width < tokens.LayoutOneColumnMaxWidth {
		return PaneSingle
	}
	if m.Width < m.minimalThreeColumnWidth() || !m.ThirdPane {
		return PaneDouble
	}
	return PaneTriple
}

func (m Model) Columns() Columns {
	switch m.PaneMode() {
	case PaneSingle:
		return Columns{Dialogs: m.Width, Chat: m.Width}
	case PaneDouble:
		dialogs := m.dialogsWidthFromRatio()
		if max := m.Width - tokens.ColumnMinWidthMain; dialogs > max {
			dialogs = max
		}
		return Columns{Dialogs: dialogs, Chat: m.Width - dialogs}
	default:
		dialogs := m.dialogsWidthFromRatio()
		third := m.thirdWidth()
		dialogs, third = m.shrinkDialogsAndThird(dialogs, third)
		return Columns{Dialogs: dialogs, Chat: m.Width - dialogs - third, Third: third}
	}
}

func (m Model) minimalThreeColumnWidth() int {
	left := 0
	if m.HasDialogs {
		left = tokens.ColumnMinWidthLeft
	}
	return left + tokens.ColumnMinWidthMain + tokens.ColumnMinWidthThird
}

func (m Model) dialogsWidthFromRatio() int {
	if !m.HasDialogs {
		return 0
	}
	w := int(math.Round(float64(m.Width) * tokens.DialogsWidthRatioDefault))
	if w < tokens.ColumnMinWidthLeft {
		w = tokens.ColumnMinWidthLeft
	}
	return w
}

func (m Model) thirdWidth() int {
	w := tokens.ThirdColumnWidthDefault
	if w < tokens.ColumnMinWidthThird {
		w = tokens.ColumnMinWidthThird
	}
	if w > tokens.ColumnMaxWidthThird {
		w = tokens.ColumnMaxWidthThird
	}
	return w
}

func (m Model) shrinkDialogsAndThird(dialogs, third int) (int, int) {
	chat := tokens.ColumnMinWidthMain
	if dialogs+third+chat <= m.Width {
		return dialogs, third
	}
	thirdNew := (m.Width - chat) * third / (dialogs + third)
	dialogsNew := (m.Width - chat) * dialogs / (dialogs + third)
	if thirdNew < tokens.ColumnMinWidthThird {
		thirdNew = tokens.ColumnMinWidthThird
		dialogsNew = m.Width - thirdNew - chat
	} else if m.HasDialogs && dialogsNew < tokens.ColumnMinWidthLeft {
		dialogsNew = tokens.ColumnMinWidthLeft
		thirdNew = m.Width - dialogsNew - chat
	}
	return dialogsNew, thirdNew
}

type Scene struct {
	Background color.NRGBA
}

func View(m Model) Scene {
	return Scene{Background: material.SchemeFor(material.Light).Surface}
}
