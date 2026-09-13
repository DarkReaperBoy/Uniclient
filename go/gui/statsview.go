package gui

import (
	"encoding/json"
	"image"
	"math"
	"strconv"
	"strings"
	"time"

	"gioui.org/f32"
	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"

	"uniclient/cores"
	"uniclient/engine"
)

// Channel statistics page (slice 184, parity row "Channel statistics
// screens" — tdesktop's channel Statistics): overview cards (followers
// with delta, views/shares/reactions per post, per-story counters,
// enabled notifications %) + line charts drawn from Telegram's chart
// JSON ({"columns":[["x",ts...],["y",v...]]}). Opened from the header ⋮
// menu for admin channels; non-channels never see it (§1.10).

var statsPanelTag = new(struct{})

// chartPoint is one (timestamp, value) sample.
type chartPoint struct {
	T int64
	V float64
}

// parseChartJSON extracts the x/y series from Telegram's chart data.
// Pure — unit-tested.
func parseChartJSON(data string) []chartPoint {
	if data == "" {
		return nil
	}
	var env struct {
		Columns [][]interface{} `json:"columns"`
	}
	if err := json.Unmarshal([]byte(data), &env); err != nil {
		return nil
	}
	var xs []float64
	var ys []float64
	for _, col := range env.Columns {
		if len(col) < 2 {
			continue
		}
		id, _ := col[0].(string)
		var dst *[]float64
		switch {
		case id == "x":
			dst = &xs
		case len(ys) == 0:
			dst = &ys // the first non-x series (single-series charts)
		default:
			continue // multi-series charts: first series only
		}
		for _, v := range col[1:] {
			if f, ok := v.(float64); ok {
				*dst = append(*dst, f)
			}
		}
	}
	if len(xs) == 0 || len(ys) == 0 {
		return nil
	}
	n := len(xs)
	if len(ys) < n {
		n = len(ys)
	}
	pts := make([]chartPoint, 0, n)
	for i := 0; i < n; i++ {
		pts = append(pts, chartPoint{T: int64(xs[i]), V: ys[i]})
	}
	return pts
}

// chartRange: the value extents (min/max) of a series.
func chartRange(pts []chartPoint) (min, max float64) {
	min, max = math.MaxFloat64, -math.MaxFloat64
	for _, p := range pts {
		if p.V < min {
			min = p.V
		}
		if p.V > max {
			max = p.V
		}
	}
	if min > max {
		return 0, 0
	}
	if min == max {
		min--
		max++
	}
	return min, max
}

// fmtChartValue renders a chart axis value compactly. Pure — tested.
func fmtChartValue(v float64) string {
	switch {
	case v >= 1e6:
		return strconv.FormatFloat(v/1e6, 'f', 1, 64) + "M"
	case v >= 1e3:
		return strconv.FormatFloat(v/1e3, 'f', 1, 64) + "K"
	case v == float64(int64(v)):
		return strconv.FormatInt(int64(v), 10)
	default:
		return strconv.FormatFloat(v, 'f', 1, 64)
	}
}

// fmtStatsDate renders a unix timestamp for the chart's date axis.
func fmtStatsDate(unix int64) string {
	return time.Unix(unix, 0).Format("Jan 2")
}

// statsDeltaLabel: the current-vs-previous delta with an arrow. Pure.
func statsDeltaLabel(cur, prev float64) string {
	if cur == prev {
		return "±0"
	}
	d := cur - prev
	sign := "+"
	if d < 0 {
		sign = "−"
	}
	d = math.Abs(d)
	if d == float64(int64(d)) {
		return sign + strconv.FormatInt(int64(d), 10)
	}
	return sign + strconv.FormatFloat(d, 'f', 1, 64)
}

// openStatsPanel loads the channel's statistics.
func (a *App) openStatsPanel() {
	a.mu.Lock()
	k := a.selected
	a.statsPanel = true
	a.statsData = nil
	a.statsLoad = true
	a.statsErr = ""
	a.headerMenu = nil
	a.mu.Unlock()
	a.invalidate()
	if k == nil {
		return
	}
	acc, chatID := k.AccountID, k.ChatID
	go func() {
		st, err := a.eng.GetChannelStats(acc, chatID)
		a.mu.Lock()
		if !a.statsPanel {
			a.mu.Unlock()
			return
		}
		a.statsLoad = false
		if err != nil {
			a.statsErr = err.Error()
			a.mu.Unlock()
			a.setToast("Statistics: " + err.Error())
			return
		}
		a.statsData = st
		a.mu.Unlock()
		a.invalidate()
	}()
}

// closeStatsPanel dismisses the page.
func (a *App) closeStatsPanel() {
	a.mu.Lock()
	if !a.statsPanel {
		a.mu.Unlock()
		return
	}
	a.statsPanel = false
	a.statsData = nil
	a.mu.Unlock()
	a.invalidate()
}

// layoutStatsPanel: the statistics page (chat-pane replacement).
func (a *App) layoutStatsPanel(gtx layout.Context, f frame, chat *engine.ChatInfo) layout.Dimensions {
	{
		stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
		event.Op(gtx.Ops, statsPanelTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeStatsPanel()
		}
	}
	if a.wid.statsPanelBack.Clicked(gtx) {
		a.closeStatsPanel()
	}

	title := "Statistics"
	if chat != nil {
		title = "Statistics · " + chat.Title
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(8), Right: unit.Dp(12)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.IconButton(&a.wid.statsPanelBack, iconNavigationBack, "Back to chat")
							btn.Color = a.ui.p.TextDim
							return btn.Layout(gtx)
						}),
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.H3(title)
								lbl.MaxLines = 1
								return lbl.Layout(gtx)
							})
						}),
					)
				})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.ui.Divider(gtx)
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			if f.statsLoad {
				return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
					return a.ui.Dim(unit.Sp(14), "Loading statistics…").Layout(gtx)
				})
			}
			if f.statsErr != "" && f.statsData == nil {
				return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(13), "Could not load: "+f.statsErr)
					lbl.MaxLines = 3
					return lbl.Layout(gtx)
				})
			}
			st := f.statsData
			if st == nil {
				return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
					return a.ui.Dim(unit.Sp(14), "No statistics available").Layout(gtx)
				})
			}
			return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return a.wid.statsPanelList.Layout(gtx, 2+len(st.Graphs), func(gtx layout.Context, i int) layout.Dimensions {
					switch i {
					case 0:
						return a.statsOverviewCards(gtx, st)
					case 1:
						if len(st.Graphs) == 0 {
							return layout.Dimensions{}
						}
						return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(13), "Charts")
							lbl.Color = a.ui.p.TextDim
							return lbl.Layout(gtx)
						})
					default:
						return a.statsChartCard(gtx, st.Graphs[i-2])
					}
				})
			})
		}),
	)
}

// statsOverviewCards: the 2-column card grid of headline counters.
func (a *App) statsOverviewCards(gtx layout.Context, st *cores.ChannelStats) layout.Dimensions {
	cards := []struct {
		label string
		value string
		delta string
	}{
		{"Followers", fmtChartValue(st.Followers.Current), statsDeltaLabel(st.Followers.Current, st.Followers.Previous)},
		{"Views per post", fmtChartValue(st.ViewsPerPost.Current), statsDeltaLabel(st.ViewsPerPost.Current, st.ViewsPerPost.Previous)},
		{"Shares per post", fmtChartValue(st.SharesPerPost.Current), statsDeltaLabel(st.SharesPerPost.Current, st.SharesPerPost.Previous)},
		{"Reactions per post", fmtChartValue(st.ReactionsPerPost.Current), statsDeltaLabel(st.ReactionsPerPost.Current, st.ReactionsPerPost.Previous)},
		{"Story views", fmtChartValue(st.ViewsPerStory.Current), statsDeltaLabel(st.ViewsPerStory.Current, st.ViewsPerStory.Previous)},
		{"Story shares", fmtChartValue(st.SharesPerStory.Current), statsDeltaLabel(st.SharesPerStory.Current, st.SharesPerStory.Previous)},
		{"Notifications on", strconv.FormatFloat(st.NotifPercent, 'f', 1, 64) + "%", ""},
	}
	var rows []layout.FlexChild
	for i := 0; i < len(cards); i += 2 {
		var cells []layout.FlexChild
		for j := i; j < i+2 && j < len(cards); j++ {
			c := cards[j]
			cells = append(cells, layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Right: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return roundedFill(gtx, a.ui.p.SurfaceHi, unit.Dp(12), func(gtx layout.Context) layout.Dimensions {
						return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							var r []layout.FlexChild
							r = append(r, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(11), c.label)
								lbl.Color = a.ui.p.TextDim
								lbl.MaxLines = 1
								return lbl.Layout(gtx)
							}))
							r = append(r, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(18), c.value)
								return lbl.Layout(gtx)
							}))
							if c.delta != "" {
								r = append(r, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									col := a.ui.p.TextDim
									if strings.HasPrefix(c.delta, "+") {
										col = a.ui.p.Online
									} else if strings.HasPrefix(c.delta, "−") {
										col = a.ui.p.Error
									}
									lbl := a.ui.Label(unit.Sp(11), c.delta)
									lbl.Color = col
									return lbl.Layout(gtx)
								}))
							}
							return layout.Flex{Axis: layout.Vertical}.Layout(gtx, r...)
						})
					})
				})
			}))
		}
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, cells...)
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
}

// statsChartCard renders one chart: title + the polyline + axis labels.
func (a *App) statsChartCard(gtx layout.Context, g cores.StatsGraphData) layout.Dimensions {
	pts := parseChartJSON(g.JSON)
	if len(pts) < 2 {
		// A single-point or unparseable graph is honestly skipped.
		return layout.Dimensions{}
	}
	minV, maxV := chartRange(pts)
	h := gtx.Dp(unit.Dp(160))
	w := gtx.Constraints.Max.X
	pad := gtx.Dp(unit.Dp(8))

	return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.SurfaceHi, unit.Dp(12), func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Baseline}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(13), g.Title)
								lbl.MaxLines = 1
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), fmtChartValue(maxV))
								return lbl.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							gtx.Constraints.Max.Y = h
							return a.drawChartLine(gtx, pts, minV, maxV, w-2*pad-gtx.Dp(unit.Dp(20)), h-pad)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(10), fmtStatsDate(pts[0].T))
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(10), fmtStatsDate(pts[len(pts)-1].T))
								return lbl.Layout(gtx)
							}),
						)
					}),
				)
			})
		})
	})
}

// drawChartLine paints the polyline (accent) over faint gridlines.
func (a *App) drawChartLine(gtx layout.Context, pts []chartPoint, minV, maxV float64, w, h int) layout.Dimensions {
	if w <= 0 || h <= 0 || len(pts) < 2 {
		return layout.Dimensions{}
	}
	minT, maxT := float64(pts[0].T), float64(pts[len(pts)-1].T)
	if maxT <= minT {
		maxT = minT + 1
	}
	xAt := func(i int) float32 {
		return float32((float64(pts[i].T)-minT)/(maxT-minT)) * float32(w)
	}
	yAt := func(i int) float32 {
		return float32(h) - float32((pts[i].V-minV)/(maxV-minV))*float32(h)
	}

	// Gridlines: 4 horizontal hairlines.
	for k := 1; k < 4; k++ {
		y := h * k / 4
		stack := clip.Rect{Max: image.Pt(w, 1)}.Push(gtx.Ops)
		paint.FillShape(gtx.Ops, a.ui.p.Divider, clip.Rect{Min: image.Pt(0, y), Max: image.Pt(w, y+1)}.Op())
		stack.Pop()
	}

	// The polyline.
	var p clip.Path
	p.Begin(gtx.Ops)
	p.MoveTo(f32.Pt(xAt(0), yAt(0)))
	for i := 1; i < len(pts); i++ {
		p.LineTo(f32.Pt(xAt(i), yAt(i)))
	}
	stroke := clip.Stroke{Path: p.End(), Width: float32(gtx.Dp(unit.Dp(2)))}
	stack := stroke.Op().Push(gtx.Ops)
	paint.Fill(gtx.Ops, a.ui.p.Accent)
	stack.Pop()
	return layout.Dimensions{Size: image.Pt(w, h)}
}
