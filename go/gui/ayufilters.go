package gui

// Ayu message filters editor (slice 90, matrix row 238): the Ayu settings
// page gains "Message filters" — a dialog listing the local regex
// hide-rules with per-filter enable/delete, plus an add field with live
// regex validation errors. Changes apply to the open chat immediately
// (refreshMessages re-runs the engine filter).

import (
	"image"
	"regexp"
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

// ayuFilterDlgState is the open filters editor.
type ayuFilterDlgState struct {
	filters    []engine.AyuFilter
	loaded     bool
	err        string // last add error, shown inline
	clearInput bool   // set by a successful add; layout clears the editor
}

var (
	ayuFilterTag       = new(struct{})
	ayuFilterEd        widget.Editor
	ayuFilterAddBtn    widget.Clickable
	ayuFilterCloseBtn  widget.Clickable
	ayuFilterManageBtn widget.Clickable   // settings-page row button
	ayuFilterRowBtns   []widget.Clickable // enable chips
	ayuFilterDelBtns   []widget.Clickable // delete buttons
)

// openAyuFilterDialog opens the editor and loads the filter list.
func (a *App) openAyuFilterDialog() {
	a.mu.Lock()
	a.ayuFilterDlg = &ayuFilterDlgState{}
	a.mu.Unlock()
	go func() {
		fs := a.eng.ListAyuFilters()
		a.mu.Lock()
		if a.ayuFilterDlg != nil {
			a.ayuFilterDlg.filters = fs
			a.ayuFilterDlg.loaded = true
		}
		a.mu.Unlock()
		a.invalidate()
	}()
	a.invalidate()
}

// openAyuFilterDialogPrefilled is the quick-add path (matrix row 168):
// the menu hands a suggested pattern; the editor opens seeded with it so
// one press of Add applies. GUI-loop only (SetText).
func (a *App) openAyuFilterDialogPrefilled(pattern string) {
	a.openAyuFilterDialog()
	ayuFilterEd.SetText(pattern)
}

// quickFilterPattern derives the suggested filter regex from a message's
// text: first line, spaces collapsed, capped at 64 runes, regex-quoted so
// the suggestion matches the literal text. Pure.
func quickFilterPattern(text string) string {
	first := text
	if i := strings.IndexAny(first, "\n\r"); i >= 0 {
		first = first[:i]
	}
	first = strings.Join(strings.Fields(first), " ")
	if first == "" {
		return ""
	}
	r := []rune(first)
	if len(r) > 64 {
		r = r[:64]
	}
	return regexp.QuoteMeta(string(r))
}

// closeAyuFilterDialog dismisses the editor and re-arms the settings
// row count (it changed).
func (a *App) closeAyuFilterDialog() {
	a.mu.Lock()
	a.ayuFilterDlg = nil
	a.ayuFilterCountOn = false
	a.mu.Unlock()
	a.invalidate()
}

// ensureAyuFilterCount (GUI loop) lazily loads the count for the
// settings row when the Ayu page renders without a cached value.
func (a *App) ensureAyuFilterCount(f frame) {
	a.mu.Lock()
	stale := !a.ayuFilterCountOn
	a.mu.Unlock()
	if !stale || a.ayuFilterCountBusy {
		return
	}
	a.ayuFilterCountBusy = true
	go func() {
		fs := a.eng.ListAyuFilters()
		a.mu.Lock()
		a.ayuFilterCount = len(fs)
		a.ayuFilterCountOn = true
		a.ayuFilterCountBusy = false
		a.mu.Unlock()
		a.invalidate()
	}()
}

// reloadAyuFilters re-reads the list (after a mutation).
func (a *App) reloadAyuFilters() {
	go func() {
		fs := a.eng.ListAyuFilters()
		a.mu.Lock()
		if a.ayuFilterDlg != nil {
			a.ayuFilterDlg.filters = fs
			a.ayuFilterDlg.loaded = true
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// addAyuFilter validates + stores the editor's pattern, then refreshes.
// Text is read on the GUI loop (layout calls this); the DB write runs off
// the loop. Clearing the editor is deferred to the layout pass via the
// dialog's clearInput flag — Editor methods are not goroutine-safe.
func (a *App) addAyuFilter() {
	pattern := strings.TrimSpace(ayuFilterEd.Text())
	go func() {
		_, err := a.eng.AddAyuFilter(pattern)
		a.mu.Lock()
		if a.ayuFilterDlg != nil {
			if err != nil {
				a.ayuFilterDlg.err = err.Error()
			} else {
				a.ayuFilterDlg.err = ""
				a.ayuFilterDlg.clearInput = true
			}
		}
		a.mu.Unlock()
		a.reloadAyuFilters()
		a.refreshOpenChat()
	}()
}

// refreshOpenChat re-runs the message load for the open chat so filter
// changes show immediately.
func (a *App) refreshOpenChat() {
	a.mu.Lock()
	k := a.msgFor
	a.mu.Unlock()
	if k == nil {
		return
	}
	go a.refreshMessages()
}

// filterCountLabel summarizes the filter list for the settings row. Pure.
func filterCountLabel(fs []engine.AyuFilter) string {
	if len(fs) == 0 {
		return "Off"
	}
	on := 0
	for _, f := range fs {
		if f.Enabled {
			on++
		}
	}
	if on == 0 {
		return itoa(len(fs)) + " filters · all off"
	}
	return itoa(on) + "/" + itoa(len(fs)) + " active"
}

// filterCountText maps the cached count to the row value. Pure.
func filterCountText(loaded bool, n int) string {
	if !loaded {
		return "…"
	}
	if n == 0 {
		return "Off"
	}
	return itoa(n)
}

// layoutAyuFilterRow renders the settings-page entry: count + Manage.
func (a *App) layoutAyuFilterRow(gtx layout.Context, f frame) layout.Dimensions {
	a.ensureAyuFilterCount(f)
	if ayuFilterManageBtn.Clicked(gtx) {
		a.openAyuFilterDialog()
	}
	return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(10), Bottom: unit.Dp(10), Left: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(14), "Message filters")
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(12), "Hide matching messages locally — never deleted")
						lbl.Color = a.ui.p.TextFaint
						return lbl.Layout(gtx)
					}),
				)
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Right: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(12), filterCountText(f.ayuFilterCountOn, f.ayuFilterCount))
				lbl.Color = a.ui.p.TextDim
				return lbl.Layout(gtx)
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			bl := a.ui.TextButton(&ayuFilterManageBtn, "Manage")
			bl.Color = a.ui.p.Accent
			return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, bl.Layout)
		}),
	)
}

// layoutAyuFilterDialog renders the filters editor (content-pane
// replacement, like the other settings dialogs).
func (a *App) layoutAyuFilterDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.ayuFilterDlg
	growClickables(&ayuFilterRowBtns, len(d.filters))
	growClickables(&ayuFilterDelBtns, len(d.filters))

	// Esc closes (window-wide key listener for this dialog's tag —
	// the dialog replaces the whole content pane, so the opaque
	// registration is fine and blocks input behind it).
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, ayuFilterTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeAyuFilterDialog()
		}
	}
	// Drain editor events: Enter submits (sidebar-search pattern —
	// editor events come from Editor.Update, not key.Filters).
	for {
		ev, ok := ayuFilterEd.Update(gtx)
		if !ok {
			break
		}
		if _, is := ev.(widget.SubmitEvent); is {
			a.addAyuFilter()
		}
	}
	// Deferred editor clear (set by the add goroutine on success).
	if d.clearInput {
		a.mu.Lock()
		d.clearInput = false
		a.mu.Unlock()
		ayuFilterEd.SetText("")
	}
	if ayuFilterCloseBtn.Clicked(gtx) {
		a.closeAyuFilterDialog()
	}
	if ayuFilterAddBtn.Clicked(gtx) {
		a.addAyuFilter()
	}
	for i, fb := range ayuFilterRowBtns {
		if fb.Clicked(gtx) && i < len(d.filters) {
			id, next := d.filters[i].ID, !d.filters[i].Enabled
			go func() {
				if err := a.eng.SetAyuFilterEnabled(id, next); err != nil {
					a.setToast("Filters: " + err.Error())
				}
				a.reloadAyuFilters()
				a.refreshOpenChat()
			}()
		}
	}
	for i, db := range ayuFilterDelBtns {
		if db.Clicked(gtx) && i < len(d.filters) {
			id := d.filters[i].ID
			go func() {
				if err := a.eng.RemoveAyuFilter(id); err != nil {
					a.setToast("Filters: " + err.Error())
				}
				a.reloadAyuFilters()
				a.refreshOpenChat()
			}()
		}
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(380))
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(480))
		return roundedFill(gtx, a.ui.p.Surface, 16, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(18)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.ui.H3("Message Filters").Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(12), "Messages matching an active regex are hidden locally — never deleted.")
							lbl.Color = a.ui.p.TextFaint
							return lbl.Layout(gtx)
						})
					}),
					// add row
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
									return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
										ayuFilterEd.SingleLine = true
										ed := a.ui.Editor(&ayuFilterEd, "regex, e.g. (?i)promo")
										return ed.Layout(gtx)
									})
								})
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								bl := material.Button(a.ui.Theme, &ayuFilterAddBtn, "Add")
								bl.Background = a.ui.p.Accent
								bl.CornerRadius = 10
								return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, bl.Layout)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if d.err == "" {
							return layout.Dimensions{}
						}
						return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(11), d.err)
							lbl.Color = a.ui.p.Error
							return lbl.Layout(gtx)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						if !d.loaded {
							return layout.Center.Layout(gtx, a.ui.Dim(unit.Sp(12), "Loading…").Layout)
						}
						if len(d.filters) == 0 {
							return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(12), "No filters yet")
								lbl.Color = a.ui.p.TextFaint
								return lbl.Layout(gtx)
							})
						}
						var rows []layout.FlexChild
						for i, flt := range d.filters {
							rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return a.ayuFilterRow(gtx, flt, &ayuFilterRowBtns[i], &ayuFilterDelBtns[i])
							}))
						}
						return layout.Flex{Axis: layout.Vertical, Spacing: layout.Spacing(6)}.Layout(gtx, rows...)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						bl := material.Button(a.ui.Theme, &ayuFilterCloseBtn, "Close")
						bl.Background = a.ui.p.SurfaceHi
						bl.Color = a.ui.p.Text
						bl.CornerRadius = 10
						return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, bl.Layout)
					}),
				)
			})
		})
	})
}

// ayuFilterRow: one filter — pattern (mono hint), enable chip, delete.
func (a *App) ayuFilterRow(gtx layout.Context, flt engine.AyuFilter, toggle, del *widget.Clickable) layout.Dimensions {
	return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
		return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(13), flt.Pattern)
					lbl.MaxLines = 1
					if !flt.Enabled {
						lbl.Color = a.ui.p.TextFaint
					}
					return lbl.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					label := "off"
					if flt.Enabled {
						label = "on"
					}
					return segmentChip(gtx, a, toggle, label, flt.Enabled)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.IconButton(del, iconContentClear, "Delete filter")
						btn.Color = a.ui.p.Error
						btn.Background = color00
						btn.Size = unit.Dp(16)
						btn.Inset = layout.UniformInset(unit.Dp(5))
						return btn.Layout(gtx)
					})
				}),
			)
		})
	})
}
