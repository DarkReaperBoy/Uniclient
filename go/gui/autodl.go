package gui

import (
	"image"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"
)

// Automatic media download rules (AyuGram parity, matrix "Data & storage"):
// the Data & Storage page gains per-source rows ("In private chats" /
// "In groups" / "In channels") that open this editor dialog. It shows the
// type toggles (photos, videos, GIFs & animations, video messages, files)
// and the two size gates the engine applies (photos+files share the media
// limit; videos/GIFs/round videos share the video limit). Every change
// applies immediately through engine.SetAutoDownloadSettings, which feeds
// the engine's incoming-message auto-download path and persists the rules
// so they survive restarts.

// autodlSourceLabels are the three editor targets, in AyuGram order.
var autodlSourceLabels = []struct {
	source string
	label  string
}{
	{"private", "In private chats"},
	{"group", "In groups"},
	{"channel", "In channels"},
}

// autodlToggleRows are the per-type toggles rendered in the editor.
var autodlToggleRows = []struct {
	key   string
	label string
}{
	{"photos", "Photos"},
	{"videos", "Videos"},
	{"gifs", "GIFs & animations"},
	{"videoMessages", "Video messages"},
	{"files", "Files"},
}

// autodlMediaLimits / autodlVideoLimits are the size ladders, in bytes.
// 0 means unlimited (the engine treats a non-positive limit as always
// within).
var autodlMediaLimits = []int64{
	1 * 1024 * 1024,
	5 * 1024 * 1024,
	10 * 1024 * 1024,
	50 * 1024 * 1024,
	0,
}

var autodlVideoLimits = []int64{
	10 * 1024 * 1024,
	50 * 1024 * 1024,
	100 * 1024 * 1024,
	500 * 1024 * 1024,
	0,
}

// autodlLimitLabel renders a size gate for display (chips, summaries).
func autodlLimitLabel(limit int64) string {
	if limit <= 0 {
		return "Unlimited"
	}
	mb := limit / (1024 * 1024)
	if mb*1024*1024 == limit {
		return itoa(int(mb)) + " MB"
	}
	kb := limit / 1024
	return itoa(int(kb)) + " KB"
}

// autodlSummary renders a row value summarizing what auto-downloads for a
// source ("Photos, Videos · ≤10 MB" style, or "Off").
func autodlSummary(settings map[string]interface{}) string {
	on := make([]string, 0, 5)
	for _, r := range autodlToggleRows {
		if v, _ := settings[r.key].(bool); v {
			on = append(on, r.label)
		}
	}
	if len(on) == 0 {
		return "Off"
	}
	sum := ""
	for i, name := range on {
		if i > 0 {
			if i == len(on)-1 {
				sum += " · "
			} else {
				sum += ", "
			}
		}
		sum += name
	}
	if dl, _ := settings["downloadLimit"].(int64); dl > 0 {
		sum += " · ≤" + autodlLimitLabel(dl)
	}
	return sum
}

// autodlDlgState is the open rules editor.
type autodlDlgState struct {
	source string
}

var (
	autodlDlgCloseBtn widget.Clickable
	autodlMediaChips  []widget.Clickable
	autodlVideoChips  []widget.Clickable
	autodlRowBtns     []widget.Clickable // Data & Storage page rows
	autodlDlgKeyTag   = new(struct{})
)

// openAutodlDialog opens the rules editor for one source and resyncs the
// toggle pool so the switches show the effective values.
func (a *App) openAutodlDialog(source string) {
	a.mu.Lock()
	a.autoDlDlg = &autodlDlgState{source: source}
	a.mu.Unlock()
	for _, r := range autodlToggleRows {
		delete(settingsSynced, "autodl:"+source+":"+r.key)
	}
	a.invalidate()
}

// closeAutodlDialog dismisses it.
func (a *App) closeAutodlDialog() {
	a.mu.Lock()
	a.autoDlDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// applyAutodl copies the current effective settings for the source, applies
// one override, pushes the whole map to the engine (persists + feeds the
// auto-download path), and refreshes the cached summary.
func (a *App) applyAutodl(source string, override map[string]interface{}) {
	a.mu.Lock()
	merged := map[string]interface{}{}
	for k, v := range a.autoDlRules[source] {
		merged[k] = v
	}
	a.mu.Unlock()
	for k, v := range override {
		merged[k] = v
	}
	a.eng.SetAutoDownloadSettings(source, merged)
	a.mu.Lock()
	if a.autoDlRules == nil {
		a.autoDlRules = map[string]map[string]interface{}{}
	}
	a.autoDlRules[source] = merged
	a.mu.Unlock()
	a.invalidate()
}

// loadAutoDl reads the effective rules per source (memory read, quick).
func (a *App) loadAutoDl() {
	st := a.eng.GetAutoDownloadSettings()
	a.mu.Lock()
	a.autoDlRules, a.autoDlOn = st, true
	a.mu.Unlock()
	a.invalidate()
}

// layoutAutoDlChip renders one size-gate chip (active = accent).
func (a *App) layoutAutoDlChip(gtx layout.Context, btn *widget.Clickable, label string, active bool) layout.Dimensions {
	bl := material.ButtonLayout(a.ui.Theme, btn)
	if active {
		bl.Background = a.ui.p.Accent
	} else {
		bl.Background = a.ui.p.SurfaceHi
	}
	bl.CornerRadius = 8
	return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(12), label)
				if active {
					lbl.Color = rgb(0x0D1821)
				} else {
					lbl.Color = a.ui.p.Text
				}
				return lbl.Layout(gtx)
			})
		})
	})
}

// layoutAutoDownloadDialog renders the rules editor (content-pane
// replacement, like the other settings dialogs).
func (a *App) layoutAutoDownloadDialog(gtx layout.Context, f frame) layout.Dimensions {
	st := f.autoDlDlg
	settings := f.autoDlRules[st.source]
	growClickables(&autodlMediaChips, len(autodlMediaLimits))
	growClickables(&autodlVideoChips, len(autodlVideoLimits))

	// Esc closes (self-handled).
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, autodlDlgKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeAutodlDialog()
		}
	}
	if autodlDlgCloseBtn.Clicked(gtx) {
		a.closeAutodlDialog()
	}

	title := "Automatic media download"
	for _, r := range autodlSourceLabels {
		if r.source == st.source {
			title += " — " + r.label
		}
	}

	mediaLimit, _ := settings["downloadLimit"].(int64)
	videoLimit, _ := settings["autoPlayLimit"].(int64)

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(360))
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(430))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.H3(title)
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(12), "Changes apply immediately")
						lbl.Color = a.ui.p.TextFaint
						return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(8)}.Layout(gtx, lbl.Layout)
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						var children []layout.FlexChild
						for _, r := range autodlToggleRows {
							r := r
							value, _ := settings[r.key].(bool)
							children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return a.toggleRow(gtx, "autodl:"+st.source+":"+r.key, r.label, value, func(v bool) {
									a.applyAutodl(st.source, map[string]interface{}{r.key: v})
								})
							}))
						}
						children = append(children,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return a.subHeader(gtx, "Max media size")
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, a.autodlChipRow(gtx, autodlMediaChips, autodlMediaLimits, mediaLimit, "downloadLimit", st.source)...)
								})
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return a.subHeader(gtx, "Max video size")
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, a.autodlChipRow(gtx, autodlVideoChips, autodlVideoLimits, videoLimit, "autoPlayLimit", st.source)...)
							}),
						)
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						bl := material.Button(a.ui.Theme, &autodlDlgCloseBtn, "Done")
						bl.Background = a.ui.p.SurfaceHi
						bl.Color = a.ui.p.Text
						bl.CornerRadius = 10
						return bl.Layout(gtx)
					}),
				)
			})
		})
	})
}

// autodlChipRow builds the chip list for one size ladder.
func (a *App) autodlChipRow(gtx layout.Context, btns []widget.Clickable, limits []int64, current int64, field, source string) []layout.FlexChild {
	children := make([]layout.FlexChild, 0, len(limits))
	for i, limit := range limits {
		i, limit := i, limit
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			btn := &btns[i]
			if btn.Clicked(gtx) {
				a.applyAutodl(source, map[string]interface{}{field: limit})
			}
			return a.layoutAutoDlChip(gtx, btn, autodlLimitLabel(limit), limit == current)
		}))
	}
	return children
}

// autodlRowSummaryFor renders the per-source row value shown on the Data &
// Storage page ("" while loading).
func autodlRowSummaryFor(f frame, source string) string {
	if !f.autoDlOn {
		return ""
	}
	return autodlSummary(f.autoDlRules[source])
}
