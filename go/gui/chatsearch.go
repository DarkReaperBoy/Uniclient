package gui

import (
	"fmt"
	"strings"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// In-chat search (AyuGram parity, matrix #256): the header search toggle
// opens a search bar under the chat header with live FTS results for THIS
// chat (engine.SearchMessages scoped by chatID), prev/next hit navigation,
// and jump-to-message. Escape closes.

var (
	inSearchEd       widget.Editor
	inSearchCloseBtn widget.Clickable
	inSearchPrevBtn  widget.Clickable
	inSearchNextBtn  widget.Clickable
	inSearchRows     []widget.Clickable
	inSearchList     widget.List
	inSearchKeyTag   = new(struct{})
)

func init() {
	inSearchList.Axis = layout.Vertical
}

// inChatSearchKey: the staleness guard key for async result writes.
func inChatSearchKey(q string, k chatKey) string {
	return q + "@" + k.String()
}

// toggleInChatSearch opens/closes the in-chat search bar.
func (a *App) toggleInChatSearch() {
	a.mu.Lock()
	opening := !a.inSearch
	a.inSearch = opening
	a.inSearchQ = ""
	a.inChatHits = nil
	a.inChatIdx = 0
	a.inChatBusy = false
	a.mu.Unlock()
	if !opening {
		inSearchEd.SetText("")
	}
	a.invalidate()
}

// closeInChatSearch dismisses the bar (chat switches call this too).
func (a *App) closeInChatSearch() {
	a.mu.Lock()
	if !a.inSearch {
		a.mu.Unlock()
		return
	}
	a.inSearch = false
	a.inSearchQ = ""
	a.inChatHits = nil
	a.inChatIdx = 0
	a.inChatBusy = false
	a.mu.Unlock()
	inSearchEd.SetText("")
	a.invalidate()
}

// onInChatSearchChanged (GUI goroutine, editor ChangeEvents) launches the
// async scoped search; stale writes are dropped by key.
func (a *App) onInChatSearchChanged(q string, k chatKey) {
	q = strings.TrimSpace(q)
	key := inChatSearchKey(q, k)
	a.mu.Lock()
	a.inSearchQ = q
	a.inChatBusy = len([]rune(q)) >= 2
	if a.inChatFor != key {
		a.inChatHits = nil
		a.inChatIdx = 0
	}
	a.inChatFor = key
	if len([]rune(q)) < 2 {
		a.inChatBusy = false
		a.inChatHits = nil
		a.inChatIdx = 0
		a.mu.Unlock()
		return
	}
	a.mu.Unlock()

	go func() {
		hits, err := a.eng.SearchMessages(q, k.AccountID, 50, k.ChatID, "", "")
		if err != nil {
			hits = nil
		}
		a.mu.Lock()
		if a.inChatFor == key {
			a.inChatHits = hits
			a.inChatIdx = 0
			a.inChatBusy = false
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// inChatSearchStep moves to the prev (newer) / next (older) hit and jumps.
func (a *App) inChatSearchStep(delta int) {
	a.mu.Lock()
	hits := a.inChatHits
	idx := a.inChatIdx
	if len(hits) == 0 {
		a.mu.Unlock()
		return
	}
	idx += delta
	if idx < 0 {
		idx = 0
	}
	if idx >= len(hits) {
		idx = len(hits) - 1
	}
	r := hits[idx]
	a.inChatIdx = idx
	a.mu.Unlock()
	a.jumpToMessageAt(r.MsgID, r.Timestamp)
}

// layoutInChatSearch renders the search bar + result rows below the chat
// header. Returns the block height for listTop accounting.
func (a *App) layoutInChatSearch(gtx layout.Context, f frame, k chatKey) layout.Dimensions {
	// Escape closes (registered within the pane; the composer keeps focus).
	{
		stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
		event.Op(gtx.Ops, inSearchKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeInChatSearch()
		}
	}

	// Editor change events.
	for {
		ev, ok := inSearchEd.Update(gtx)
		if !ok {
			break
		}
		if _, is := ev.(widget.ChangeEvent); is {
			a.onInChatSearchChanged(inSearchEd.Text(), k)
		}
	}

	if inSearchCloseBtn.Clicked(gtx) {
		a.closeInChatSearch()
	}
	if inSearchPrevBtn.Clicked(gtx) {
		a.inChatSearchStep(-1)
	}
	if inSearchNextBtn.Clicked(gtx) {
		a.inChatSearchStep(1)
	}

	hits := f.inChatHits
	growClickables(&inSearchRows, len(hits))
	for i, r := range hits {
		i, r := i, r
		if inSearchRows[i].Clicked(gtx) {
			a.mu.Lock()
			a.inChatIdx = i
			a.mu.Unlock()
			a.jumpToMessageAt(r.MsgID, r.Timestamp)
		}
	}

	children := []layout.FlexChild{
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.inChatSearchBar(gtx, f)
		}),
	}
	// Results (only while a query is active; caps at 45% of the pane).
	if q := strings.TrimSpace(f.inSearchQ); len([]rune(q)) >= 2 {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			maxH := gtx.Dp(unit.Dp(300))
			if maxH > gtx.Constraints.Max.Y*45/100 {
				maxH = gtx.Constraints.Max.Y * 45 / 100
			}
			return layout.Inset{Left: unit.Dp(8), Right: unit.Dp(8), Bottom: unit.Dp(4)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					gtx.Constraints.Max.Y = maxH
					return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
						return a.inChatSearchResults(gtx, f, hits)
					})
				})
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func (a *App) inChatSearchBar(gtx layout.Context, f frame) layout.Dimensions {
	// Keep the keyboard in the search editor while the bar is open (the
	// router dedups unchanged focus, so this is cheap).
	gtx.Execute(key.FocusCmd{Tag: &inSearchEd})
	return insetAll(gtx, unit.Dp(8), 4, 4, 4, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return iconActionSearch.Layout(gtx, a.ui.p.TextDim)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						ed := a.ui.Editor(&inSearchEd, "Search in this chat")
						return ed.Layout(gtx)
					}),
					// Position counter.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(8), Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							var txt string
							switch {
							case f.inChatBusy:
								txt = "…"
							case len(f.inChatHits) == 0:
								txt = "0/0"
							default:
								txt = fmt.Sprintf("%d/%d", f.inChatIdx+1, len(f.inChatHits))
							}
							lbl := a.ui.Dim(unit.Sp(12), txt)
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.ui.IconButton(&inSearchPrevBtn, iconNavChevronLeft, "Newer hit").Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.ui.IconButton(&inSearchNextBtn, iconNavChevronRight, "Older hit").Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.ui.IconButton(&inSearchCloseBtn, iconContentClear, "Close search").Layout(gtx)
					}),
				)
			})
		})
	})
}

func (a *App) inChatSearchResults(gtx layout.Context, f frame, hits []engine.SearchResult) layout.Dimensions {
	if f.inChatBusy {
		return layout.UniformInset(unit.Dp(12)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(13), "Searching…")
			return lbl.Layout(gtx)
		})
	}
	if len(hits) == 0 {
		return layout.UniformInset(unit.Dp(12)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(13), "No messages found")
			return lbl.Layout(gtx)
		})
	}
	return layout.UniformInset(unit.Dp(4)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return inSearchList.Layout(gtx, len(hits), func(gtx layout.Context, i int) layout.Dimensions {
			return a.inChatSearchRow(gtx, hits[i], &inSearchRows[i], i == f.inChatIdx)
		})
	})
}

func (a *App) inChatSearchRow(gtx layout.Context, r engine.SearchResult, btn *widget.Clickable, current bool) layout.Dimensions {
	return layout.Inset{Left: unit.Dp(4), Right: unit.Dp(4), Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return material.ButtonLayout(a.ui.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				bg := a.ui.p.Surface
				if current {
					bg = a.ui.p.AccentDim
				}
				return roundedFill(gtx, bg, 8, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(12), r.SenderName)
								lbl.Color = a.ui.p.TextDim
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(13), searchSnippet(r.Text))
								return lbl.Layout(gtx)
							}),
						)
					})
				})
			})
		})
}

// searchSnippet clamps a hit's text for the row (pure, testable).
func searchSnippet(text string) string {
	const max = 96
	r := []rune(text)
	if len(r) > max {
		return strings.TrimSpace(string(r[:max])) + "…"
	}
	if text == "" {
		return "(no text)"
	}
	return text
}
