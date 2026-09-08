package gui

import (
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
)

// Recent searches (AyuGram parity slice 37).
//
// Telegram remembers the last 8 submitted search queries and shows them
// in a dropdown under the (focused, empty) search field. Submitting a
// query (Enter) records it through the engine; picking a recent fills
// the field; a clear row empties the list.

var (
	recentSearchBtns []widget.Clickable
	recentClearBtn   widget.Clickable
)

// trimRecentSearch caps and normalizes the stored list for display.
func trimRecentSearch(list []string) []string {
	out := make([]string, 0, len(list))
	for _, q := range list {
		q = strings.TrimSpace(q)
		if q != "" {
			out = append(out, q)
		}
	}
	if len(out) > 8 {
		out = out[:8]
	}
	return out
}

// submitSearch records a query into the engine's recents and refreshes.
func (a *App) submitSearch(query string) {
	query = strings.TrimSpace(query)
	if query == "" {
		return
	}
	go func() {
		_ = a.eng.AddRecentSearch(query)
		a.refreshConfig()
	}()
}

// layoutRecentSearches renders the recents dropdown below the search field
// while the editor is focused and empty (Telegram behavior). Rows are
// click-to-fill; the last row clears the list.
func (a *App) layoutRecentSearches(gtx layout.Context, f frame) layout.Dimensions {
	recents := trimRecentSearch(f.cfg.RecentSearches)
	if len(recents) == 0 {
		return layout.Dimensions{}
	}
	if !gtx.Focused(&sidebarSearch) || sidebarSearch.Text() != "" {
		return layout.Dimensions{}
	}

	for len(recentSearchBtns) < len(recents) {
		recentSearchBtns = append(recentSearchBtns, widget.Clickable{})
	}
	for i, q := range recents {
		i := i
		if recentSearchBtns[i].Clicked(gtx) {
			sidebarSearch.SetText(q)
			a.mu.Lock()
			a.search = q
			a.mu.Unlock()
			a.invalidate()
			break
		}
	}
	if recentClearBtn.Clicked(gtx) {
		go func() {
			_ = a.eng.ClearRecentSearches()
			a.refreshConfig()
		}()
	}

	rows := make([]layout.FlexChild, 0, len(recents)+1)
	for i, q := range recents {
		i, q := i, q
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				btn := &recentSearchBtns[i]
				bl := materialButtonFlat(gtx, a.ui, btn)
				return bl(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(7)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(13), q)
						lbl.Color = a.ui.p.Text
						return lbl.Layout(gtx)
					})
				})
			})
		}))
	}
	rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(4), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return materialButtonFlat(gtx, a.ui, &recentClearBtn)(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(7)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(13), "Clear recent searches")
					lbl.Color = a.ui.p.Error
					return lbl.Layout(gtx)
				})
			})
		})
	}))

	return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
		return layout.UniformInset(unit.Dp(4)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
		})
	})
}

// materialButtonFlat wraps a clickable as a quiet surface row (hover bg).
func materialButtonFlat(gtx layout.Context, u *UI, btn *widget.Clickable) func(gtx layout.Context, w layout.Widget) layout.Dimensions {
	bg := u.p.Surface
	if btn.Hovered() {
		bg = u.p.SurfaceHi
	}
	return func(gtx layout.Context, w layout.Widget) layout.Dimensions {
		return roundedFill(gtx, bg, 8, w)
	}
}
