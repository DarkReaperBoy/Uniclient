package gui

import (
	"image"
	"image/color"
	"strings"
	"time"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

type sharedTab struct {
	key   string
	label string
	count int
}

func sharedTabsFor(counts []engine.SharedMediaCountItem) []sharedTab {
	byType := make(map[string]int, len(counts))
	for _, mc := range counts {
		byType[mc.MediaType] = mc.Count
	}
	img := byType["photo"] + byType["gif"] + byType["sticker"]
	tabs := []sharedTab{{"image", "Photos", img}}
	if vid := byType["video"] + byType["videonote"]; vid > 0 {
		tabs = append(tabs, sharedTab{"video", "Videos", vid})
	}
	if g := byType["gif"]; g > 0 {
		tabs = append(tabs, sharedTab{"gif", "GIFs", g})
	}
	if v := byType["voice"]; v > 0 {
		tabs = append(tabs, sharedTab{"voice", "Voice", v})
	}
	if a := byType["audio"]; a > 0 {
		tabs = append(tabs, sharedTab{"audio", "Audio", a})
	}
	if f := byType["file"]; f > 0 {
		tabs = append(tabs, sharedTab{"file", "Files", f})
	}
	tabs = append(tabs, sharedTab{"links", "Links", -1})
	return tabs
}

func sharedRowTitle(tab, fileName string) string {
	if fileName != "" {
		return fileName
	}
	switch tab {
	case "voice":
		return "Voice message"
	case "audio":
		return "Audio file"
	case "file":
		return "File"
	}
	return "Media"
}

func sharedRowSub(tab string, it engine.SharedMediaItem) string {
	var parts []string
	if (tab == "voice" || tab == "audio") && it.Duration > 0 {
		parts = append(parts, fmtDur(it.Duration))
	}
	if it.FileSize > 0 {
		parts = append(parts, fmtBytes(it.FileSize))
	}
	if d := fmtTabDate(it.Timestamp); d != "" {
		parts = append(parts, d)
	}
	return strings.Join(parts, " · ")
}

func fmtTabDate(ms int64) string {
	if ms <= 0 {
		return ""
	}
	return time.UnixMilli(ms).Format("Jan 2, 15:04")
}

func hostOfURL(u string) string {
	s := u
	for _, p := range []string{"https://", "http://", "tg://"} {
		if strings.HasPrefix(s, p) {
			s = s[len(p):]
			break
		}
	}
	cut := len(s)
	for i := 0; i < len(s); i++ {
		if s[i] == '/' || s[i] == '?' || s[i] == '#' {
			cut = i
			break
		}
	}
	return s[:cut]
}

func estChipWidthDp(label string) int {
	return 18 + int(float32(len([]rune(label)))*6.3)
}

func wrapChipRows(maxWidthDp int, tabs []sharedTab) [][]int {
	var rows [][]int
	x := 0
	var cur []int
	for i, t := range tabs {
		w := estChipWidthDp(t.label)
		gap := 0
		if len(cur) > 0 {
			gap = 4
		}
		if len(cur) > 0 && x+gap+w > maxWidthDp {
			rows = append(rows, cur)
			cur, x = nil, 0
			gap = 0
		}
		cur = append(cur, i)
		x += gap + w
	}
	if len(cur) > 0 {
		rows = append(rows, cur)
	}
	return rows
}

func (a *App) loadPanelTab(k chatKey, tab string) {
	a.mu.Lock()
	if a.panelTabPending[tab] || a.panelTabLoaded[tab] {
		a.mu.Unlock()
		return
	}
	if a.panelTabPending == nil {
		a.panelTabPending = make(map[string]bool)
	}
	a.panelTabPending[tab] = true
	a.mu.Unlock()
	go func() {
		if tab == "links" {
			items, _ := a.eng.GetSharedLinks(k.AccountID, k.ChatID, 100, 0)
			a.mu.Lock()
			a.panelLinks = items
			a.panelLinksLoaded = true
			a.panelTabPending[tab] = false
			a.mu.Unlock()
		} else {
			items, _ := a.eng.GetSharedMedia(k.AccountID, k.ChatID, tab, 60, 0, "")
			a.mu.Lock()
			if a.panelTabItems == nil {
				a.panelTabItems = make(map[string][]engine.SharedMediaItem)
			}
			a.panelTabItems[tab] = items
			if a.panelTabLoaded == nil {
				a.panelTabLoaded = make(map[string]bool)
			}
			a.panelTabLoaded[tab] = true
			a.panelTabPending[tab] = false
			a.mu.Unlock()
		}
		a.invalidate()
	}()
}

func (a *App) sharedTabClickable(key string) *widget.Clickable {
	if c, ok := a.wid.sharedTabClicks[key]; ok {
		return c
	}
	if len(a.wid.sharedTabClicks) > 24 {
		a.wid.sharedTabClicks = make(map[string]*widget.Clickable)
	}
	c := new(widget.Clickable)
	a.wid.sharedTabClicks[key] = c
	return c
}

func (a *App) sharedTabClick(k chatKey, tab string) {
	a.mu.Lock()
	changed := a.panelTab != tab
	a.panelTab = tab
	a.mu.Unlock()
	if changed {
		a.invalidate()
	}
}

func (a *App) sharedMediaTabs(gtx layout.Context, f frame, chat *engine.ChatInfo, narrow bool) layout.Dimensions {
	k := *f.selected
	tabs := sharedTabsFor(f.mediaCounts)
	tab := f.panelTab
	if tab == "" {
		tab = "image"
	}

	tabReady := f.panelTabLoaded[tab] || (tab == "image" && f.panelLoaded && f.panelTabItems[tab] != nil)
	if tab == "links" {
		tabReady = f.panelLinksLoaded
	}
	if !tabReady {
		a.loadPanelTab(k, tab)
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.sharedChipBar(gtx, f, k, tabs, tab)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if !tabReady {
				return layout.Inset{Top: unit.Dp(10), Bottom: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					ld := material.Loader(a.ui.Theme)
					ld.Color = a.ui.p.Accent
					return layout.Center.Layout(gtx, ld.Layout)
				})
			}
			switch tab {
			case "links":
				return a.sharedLinksList(gtx, f, k, narrow)
			case "image", "video", "gif":
				return a.sharedMediaGrid(gtx, f, k, chat, tab)
			default:
				return a.sharedMediaList(gtx, f, k, tab, narrow)
			}
		}),
	)
}

func (a *App) sharedChipBar(gtx layout.Context, f frame, k chatKey, tabs []sharedTab, active string) layout.Dimensions {
	maxW := gtx.Dp(unit.Dp(gtx.Constraints.Max.X))
	if px := gtx.Constraints.Max.X; px > 0 {
		maxW = px
	}
	rows := wrapChipRows(maxW, tabs)
	children := make([]layout.FlexChild, 0, len(rows)+len(tabs))
	for _, row := range rows {
		cells := make([]layout.FlexChild, 0, len(row))
		for _, i := range row {
			t := tabs[i]
			cells = append(cells, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				key := k.ChatID + ":" + t.key
				btn := a.sharedTabClickable(key)
				if btn.Clicked(gtx) {
					a.sharedTabClick(k, t.key)
				}
				bg, fg := a.ui.p.SurfaceHi, a.ui.p.TextDim
				if t.key == active {
					bg, fg = a.ui.p.Accent, color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF}
				}
				bl := material.ButtonLayout(a.ui.Theme, btn)
				bl.Background = bg
				bl.CornerRadius = 8
				return layout.Inset{Right: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3), Left: unit.Dp(9), Right: unit.Dp(9)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(11), t.label)
							lbl.Color = fg
							return lbl.Layout(gtx)
						})
					})
				})
			}))
		}
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, cells...)
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func (a *App) sharedMediaGrid(gtx layout.Context, f frame, k chatKey, chat *engine.ChatInfo, tab string) layout.Dimensions {
	items := f.panelTabItems[tab]
	if len(items) == 0 {
		lbl := a.ui.Dim(unit.Sp(13), "No "+tabLabelFor(tab)+" yet")
		return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(6)}.Layout(gtx, lbl.Layout)
	}
	const cols = 3
	cell := gtx.Dp(unit.Dp(84))
	growClickables(&a.wid.photoGridClicks, len(items))
	var rows []layout.FlexChild
	for i := 0; i < len(items); i += cols {
		end := i + cols
		if end > len(items) {
			end = len(items)
		}
		part := items[i:end]
		base := i
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			cells := make([]layout.FlexChild, 0, len(part))
			for j, it := range part {
				it := it
				idx := base + j
				cells = append(cells, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Right: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						gtx.Constraints.Max.X = cell
						gtx.Constraints.Max.Y = cell
						gtx.Constraints.Min = image.Pt(cell, cell)
						if btn := &a.wid.photoGridClicks[idx]; btn.Clicked(gtx) {
							title := ""
							if chat != nil {
								title = chat.Title
							}
							a.openViewerAt(k, title, tab, it.MsgID)
						}
						bl := material.ButtonLayout(a.ui.Theme, &a.wid.photoGridClicks[idx])
						bl.Background = a.ui.p.Surface
						bl.CornerRadius = 4
						return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							isVideo := tab == "video"
							thumb := func(gtx layout.Context) layout.Dimensions {
								var img *image.RGBA
								if it.ThumbB64 != "" {
									key := "thumb:" + it.ThumbB64
									if img = mediaImgs.get(key); img == nil {
										a.decodeThumbAsync(key, it.ThumbB64)
									}
								}
								if img != nil {
									return drawImageScaled(gtx, img, cell, cell, 4)
								}
								return roundedFill(gtx, a.ui.p.SurfaceHi, 4, func(gtx layout.Context) layout.Dimensions {
									return layout.Dimensions{Size: image.Pt(cell, cell)}
								})
							}
							if !isVideo {
								return thumb(gtx)
							}
							return layout.Stack{}.Layout(gtx,
								layout.Stacked(thumb),
								layout.Stacked(func(gtx layout.Context) layout.Dimensions {
									return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
										return drawPlayBadge(gtx, gtx.Dp(unit.Dp(44)))
									})
								}),
								layout.Expanded(func(gtx layout.Context) layout.Dimensions {
									if it.Duration <= 0 {
										return layout.Dimensions{}
									}
									return layout.Stack{Alignment: layout.SE}.Layout(gtx,
										layout.Stacked(func(gtx layout.Context) layout.Dimensions {
											return layout.Inset{Right: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
												return roundedFill(gtx, color.NRGBA{A: 0xB0}, 8, func(gtx layout.Context) layout.Dimensions {
													return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(6), Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
														lbl := a.ui.Label(unit.Sp(10), fmtDur(it.Duration))
														lbl.Color = color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF}
														return lbl.Layout(gtx)
													})
												})
											})
										}),
									)
								}),
							)
						})
					})
				}))
			}
			return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, cells...)
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
}

func tabLabelFor(tab string) string {
	switch tab {
	case "image":
		return "photos"
	case "video":
		return "videos"
	case "gif":
		return "GIFs"
	}
	return tab
}

func (a *App) tabRowIcon(tab string, it engine.SharedMediaItem) *widget.Icon {
	switch tab {
	case "voice":
		return iconAVPlayCircle
	case "audio":
		return iconAVNote
	case "file":
		return iconFileAttach
	case "links":
		return iconActionSearch
	}
	return iconFileAttach
}

func (a *App) sharedMediaList(gtx layout.Context, f frame, k chatKey, tab string, narrow bool) layout.Dimensions {
	items := f.panelTabItems[tab]
	if len(items) == 0 {
		lbl := a.ui.Dim(unit.Sp(13), "No "+tabLabelFor(tab)+" yet")
		return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(6)}.Layout(gtx, lbl.Layout)
	}
	growClickables(&a.wid.sharedRowClicks, len(items))
	children := make([]layout.FlexChild, 0, len(items))
	for i, it := range items {
		it := it
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if btn := &a.wid.sharedRowClicks[i]; btn.Clicked(gtx) {
				a.jumpFromPanel(narrow, it.MsgID, it.Timestamp)
			}
			bl := material.ButtonLayout(a.ui.Theme, &a.wid.sharedRowClicks[i])
			bl.Background = a.ui.p.Surface
			bl.CornerRadius = 8
			return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									ic := a.tabRowIcon(tab, it)
									return ic.Layout(gtx, a.ui.p.Accent)
								})
							}),
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										lbl := a.ui.Label(unit.Sp(13), sharedRowTitle(tab, it.FileName))
										return lbl.Layout(gtx)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										if sub := sharedRowSub(tab, it); sub != "" {
											lbl := a.ui.Dim(unit.Sp(11), sub)
											return lbl.Layout(gtx)
										}
										return layout.Dimensions{}
									}),
								)
							}),
						)
					})
				})
			})
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func (a *App) sharedLinksList(gtx layout.Context, f frame, k chatKey, narrow bool) layout.Dimensions {
	items := f.panelLinks
	if len(items) == 0 {
		lbl := a.ui.Dim(unit.Sp(13), "No links yet")
		return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(6)}.Layout(gtx, lbl.Layout)
	}
	growClickables(&a.wid.sharedRowClicks, len(items))
	children := make([]layout.FlexChild, 0, len(items))
	for i, it := range items {
		it := it
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if btn := &a.wid.sharedRowClicks[i]; btn.Clicked(gtx) {
				a.jumpFromPanel(narrow, it.MsgID, it.Timestamp)
			}
			bl := material.ButtonLayout(a.ui.Theme, &a.wid.sharedRowClicks[i])
			bl.Background = a.ui.p.Surface
			bl.CornerRadius = 8
			return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return iconActionSearch.Layout(gtx, a.ui.p.Accent)
								})
							}),
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								sub := fmtTabDate(it.Timestamp)
								if it.SenderName != "" {
									if sub != "" {
										sub = it.SenderName + " · " + sub
									} else {
										sub = it.SenderName
									}
								}
								return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										lbl := a.ui.Label(unit.Sp(13), hostOfURL(it.URL))
										return lbl.Layout(gtx)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										if sub == "" {
											return layout.Dimensions{}
										}
										lbl := a.ui.Dim(unit.Sp(11), sub)
										return lbl.Layout(gtx)
									}),
								)
							}),
						)
					})
				})
			})
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func (a *App) jumpFromPanel(narrow bool, msgID string, ts int64) {
	if narrow {
		a.closePanel()
	}
	a.jumpToMessageAt(msgID, ts)
}
