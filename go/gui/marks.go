package gui

import (
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
)

// Ayu mark strings (AyuGram parity, matrix "Ayu deleted/edited mark
// strings"): settings_ayu exposes the strings used to mark anti-recall
// (deleted) and edited messages. Empty config values fall back to the
// defaults below; rendering goes through these pure helpers.

const (
	defaultDeletedMark = "— deleted"
	defaultEditedMark  = "edited "
)

// deletedMarkText (pure, testable): the body text of a deleted
// (anti-recall) message — the surviving text plus the mark, or the mark
// alone when the recall came without cached text.
func deletedMarkText(text, mark string) string {
	if mark == "" {
		mark = defaultDeletedMark
	}
	if strings.TrimSpace(text) == "" {
		return mark
	}
	return text + " " + mark
}

// editedMark (pure, testable): the meta prefix for an edited message.
func editedMark(mark string) string {
	if mark == "" {
		return defaultEditedMark
	}
	return mark
}

// markEditorRow renders one Ayu mark-string editor (settings_ayu).
func (a *App) markEditorRow(gtx layout.Context, ed *widget.Editor, hint string) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(4), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					e := a.ui.Editor(ed, hint)
					return e.Layout(gtx)
				})
			})
		})
}
