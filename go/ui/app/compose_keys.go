package app

import (
	"gioui.org/io/key"

	"uniclient/ui/tokens"
)

func ComposeKeyMsg(e key.Event, now int) Msg {
	if e.State != key.Press {
		return nil
	}
	if e.Modifiers&(key.ModAlt|key.ModSuper) != 0 {
		return nil
	}
	ctrl := e.Modifiers.Contain(key.ModCtrl)
	shift := e.Modifiers.Contain(key.ModShift)
	switch e.Name {
	case key.NameLeftArrow:
		if ctrl {
			return ChatComposeCursorKey{Dir: ComposeWordLeft, Select: shift}
		}
		return ChatComposeCursorKey{Dir: ComposeLeft, Select: shift}
	case key.NameRightArrow:
		if ctrl {
			return ChatComposeCursorKey{Dir: ComposeWordRight, Select: shift}
		}
		return ChatComposeCursorKey{Dir: ComposeRight, Select: shift}
	case key.NameHome:
		if ctrl {
			return ChatComposeCursorKey{Dir: ComposeDocHome, Select: shift}
		}
		return ChatComposeCursorKey{Dir: ComposeHome, Select: shift}
	case key.NameEnd:
		if ctrl {
			return ChatComposeCursorKey{Dir: ComposeDocEnd, Select: shift}
		}
		return ChatComposeCursorKey{Dir: ComposeEnd, Select: shift}
	case key.NameDeleteBackward:
		return ChatComposeBackspace{Word: ctrl, Now: now}
	case key.NameDeleteForward:
		return ChatComposeDelete{Word: ctrl, Now: now}
	case key.NameReturn, key.NameEnter:
		if ctrl || shift {
			return ChatComposeTyped{Text: "\n", Now: now}
		}
		return ChatComposeSubmitted{Now: now}
	case key.NameUpArrow:
		return ChatScrolled{DeltaY: -tokens.ScrollKeyStep, Now: now}
	case key.NameDownArrow:
		return ChatScrolled{DeltaY: tokens.ScrollKeyStep, Now: now}
	case key.NamePageUp:
		return ChatScrolled{DeltaY: -tokens.ScrollKeyPageStep, Now: now}
	case key.NamePageDown:
		return ChatScrolled{DeltaY: tokens.ScrollKeyPageStep, Now: now}
	case "A":
		if ctrl {
			return ChatComposeSelectAll{}
		}
	}
	return nil
}

func ComposeEditMsg(e key.EditEvent, now int) Msg {
	if e.Text == "" {
		return nil
	}
	if e.Range.Start == 0 && e.Range.End == 0 {
		return ChatComposeTyped{Text: e.Text, Now: now}
	}
	return nil
}
