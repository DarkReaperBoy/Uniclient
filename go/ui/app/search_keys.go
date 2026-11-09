package app

import "gioui.org/io/key"

func SearchKeyMsg(e key.Event, now int) Msg {
	if e.State != key.Press {
		return nil
	}
	if e.Modifiers&(key.ModAlt|key.ModSuper) != 0 {
		return nil
	}
	if e.Modifiers.Contain(key.ModCtrl) || e.Modifiers.Contain(key.ModShift) {
		return nil
	}
	if e.Name == key.NameDeleteBackward {
		return SearchBackspace{Now: now}
	}
	return nil
}

func SearchEditMsg(e key.EditEvent, now int) Msg {
	if e.Text == "" {
		return nil
	}
	if e.Text == "\n" || e.Text == "\r" {
		return nil
	}
	if e.Range.Start == 0 && e.Range.End == 0 {
		return SearchTyped{Text: e.Text, Now: now}
	}
	return nil
}
