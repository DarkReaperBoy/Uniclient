package gui

import (
	"image"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget/material"

	"uniclient/cores"
)

// Stickers & GIFs panel tabs (AyuGram parity, matrix "Emoji picker panel"):
// the a.wid.composer helper panel gains a top-level mode row — Emoji / Stickers /
// GIFs. The sticker tab lists installed sticker packs as chips (plus a
// Recent pseudo-pack) over a grid of static sticker thumbnails; tapping a
// sticker sends it (engine SendSticker). The GIF tab grids the account's
// saved GIFs (engine GetSavedGifs) and sends on tap through the same
// document-send path. Animated .tgs/.webm playback stays a later slice —
// the static thumbnails come from the documents' stripped thumbs.

// panel modes.
const (
	panelModeEmoji = iota
	panelModeStickers
	panelModeGifs
)

// stickerTab is one pack chip + its stickers.
type stickerTab struct {
	title    string
	stickers []cores.StickerInfo
}

// stickerTabs builds the pack tabs (Recent first), clamping the selected
// pack index into range. Pure — unit-tested.
func stickerTabs(packs []cores.StickerPackSummary, recent []cores.StickerInfo, sel int) ([]stickerTab, int) {
	var tabs []stickerTab
	if len(recent) > 0 {
		tabs = append(tabs, stickerTab{title: "Recent", stickers: recent})
	}
	for _, p := range packs {
		if len(p.Stickers) == 0 {
			continue
		}
		tabs = append(tabs, stickerTab{title: p.Title, stickers: p.Stickers})
	}
	if sel < 0 || sel >= len(tabs) {
		sel = len(tabs) - 1
	}
	return tabs, sel
}

// setPanelMode switches the helper panel's top-level tab, lazily fetching
// the mode's data on first entry.
func (a *App) setPanelMode(mode int) {
	a.mu.Lock()
	if a.emojiMode == mode {
		a.mu.Unlock()
		return
	}
	a.emojiMode = mode
	a.mu.Unlock()
	a.invalidate()
}

// ensureStickerPacks loads installed packs + recent stickers once per
// account scope (async; guards stale writes).
func (a *App) ensureStickerPacks(accountID string) {
	if accountID == "" {
		return
	}
	a.mu.Lock()
	if a.stickersLoaded && a.panelMediaFor == accountID {
		a.mu.Unlock()
		return
	}
	a.stickersLoaded = true // in-flight guard
	a.panelMediaFor = accountID
	a.mu.Unlock()
	go func() {
		packs, errP := a.eng.GetInstalledStickerPacks(accountID)
		recent, errR := a.eng.GetRecentStickers(accountID)
		a.mu.Lock()
		if errP == nil {
			a.stickerPacks = packs
		}
		if errR == nil {
			a.recentStickers = recent
		}
		if errP != nil && errR != nil {
			a.stickersLoaded = false // retry on next entry
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// ensureSavedGifs loads the account's saved GIFs once per scope.
func (a *App) ensureSavedGifs(accountID string) {
	if accountID == "" {
		return
	}
	a.mu.Lock()
	if a.gifsLoaded && a.panelMediaFor == accountID {
		a.mu.Unlock()
		return
	}
	a.gifsLoaded = true
	a.panelMediaFor = accountID
	a.mu.Unlock()
	go func() {
		gifs, err := a.eng.GetSavedGifs(accountID)
		a.mu.Lock()
		if err == nil {
			a.savedGifs = gifs
		} else {
			a.gifsLoaded = false
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// sendStickerFile sends one sticker/GIF document into the open chat.
func (a *App) sendStickerFile(f frame, fileID string) {
	if f.selected == nil || fileID == "" {
		return
	}
	accountID, chatID := f.selected.AccountID, f.selected.ChatID
	go func() {
		if err := a.eng.SendSticker(accountID, chatID, fileID); err != nil {
			a.setToast("Send failed: " + err.Error())
		}
	}()
}

// panelAccountID picks the account the helper panel acts for.
func panelAccountID(f frame) string {
	if f.selected != nil {
		return f.selected.AccountID
	}
	if len(f.accounts) > 0 {
		return f.accounts[0].ID
	}
	return ""
}

// layoutPanelModeRow renders the Emoji/Stickers/GIFs switch above the
// panel body.
func (a *App) layoutPanelModeRow(gtx layout.Context, f frame) layout.Dimensions {
	labels := [...]string{"Emoji", "Stickers", "GIFs"}
	growClickables(&a.wid.stickerModeBtns, len(labels))
	acc := panelAccountID(f)
	if f.emojiMode == panelModeStickers {
		a.ensureStickerPacks(acc)
	} else if f.emojiMode == panelModeGifs {
		a.ensureSavedGifs(acc)
	}
	children := make([]layout.FlexChild, 0, len(labels))
	for i, label := range labels {
		i, label := i, label
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			btn := &a.wid.stickerModeBtns[i]
			if btn.Clicked(gtx) {
				a.setPanelMode(i)
			}
			active := f.emojiMode == i
			b := material.Button(a.ui.Theme, btn, label)
			b.Background = a.ui.p.Surface
			b.Color = a.ui.p.TextDim
			b.TextSize = unit.Sp(12)
			b.CornerRadius = 10
			b.Inset = layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3), Left: unit.Dp(8), Right: unit.Dp(8)}
			if active {
				b.Background = a.ui.p.AccentDim
				b.Color = a.ui.p.Text
			}
			return layout.Inset{Right: unit.Dp(4)}.Layout(gtx, b.Layout)
		}))
	}
	return layout.Inset{Left: unit.Dp(8), Right: unit.Dp(8), Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, children...)
	})
}

// layoutStickerMode: pack chips + sticker grid.
func (a *App) layoutStickerMode(gtx layout.Context, f frame) layout.Dimensions {
	tabs, sel := stickerTabs(f.stickerPacks, f.recentStickers, a.stickerPackIdx)
	a.mu.Lock()
	a.stickerPackIdx = sel
	a.mu.Unlock()
	if len(tabs) == 0 {
		return a.centeredStateLabel(gtx, "No stickers yet")
	}
	growClickables(&a.wid.stickerPackBtns, len(tabs))
	var stickers []cores.StickerInfo
	if sel >= 0 && sel < len(tabs) {
		stickers = tabs[sel].stickers
	}
	growClickables(&a.wid.stickerCellBtns, len(stickers))

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		// pack chips
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(40))
			return layout.Inset{Left: unit.Dp(4), Right: unit.Dp(4), Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				a.wid.stickerPacksList.Axis = layout.Horizontal
				tl := material.List(a.ui.Theme, &a.wid.stickerPacksList)
				return tl.Layout(gtx, len(tabs), func(gtx layout.Context, i int) layout.Dimensions {
					btn := &a.wid.stickerPackBtns[i]
					if btn.Clicked(gtx) {
						a.mu.Lock()
						a.stickerPackIdx = i
						a.mu.Unlock()
						a.invalidate()
					}
					cur := i == sel
					bl := material.ButtonLayout(a.ui.Theme, btn)
					bl.Background = a.ui.p.Surface
					bl.CornerRadius = 8
					if cur {
						bl.Background = a.ui.p.AccentDim
					}
					return layout.Inset{Right: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(12), tabs[i].title)
							if cur {
								lbl.Color = a.ui.p.Text
							} else {
								lbl.Color = a.ui.p.TextDim
							}
							return lbl.Layout(gtx)
						})
					})
				})
			})
		}),
		// sticker grid
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			const cols = 5
			const cellDp = unit.Dp(60)
			rows := emojiRowCount(len(stickers), cols)
			a.wid.stickerGridList.Axis = layout.Vertical
			gl := material.List(a.ui.Theme, &a.wid.stickerGridList)
			return gl.Layout(gtx, rows, func(gtx layout.Context, r int) layout.Dimensions {
				children := make([]layout.FlexChild, 0, cols)
				for c := 0; c < cols; c++ {
					idx := r*cols + c
					if idx >= len(stickers) {
						break
					}
					st := stickers[idx]
					children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						btn := &a.wid.stickerCellBtns[idx]
						if btn.Clicked(gtx) {
							a.sendStickerFile(f, st.FileID)
						}
						cell := gtx.Dp(cellDp)
						gtx.Constraints.Max.X = cell
						gtx.Constraints.Max.Y = cell
						gtx.Constraints.Min = image.Pt(cell, cell)
						bl := material.ButtonLayout(a.ui.Theme, btn)
						bl.Background = a.ui.p.Surface
						bl.CornerRadius = 8
						return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
								return a.stickerThumb(gtx, st)
							})
						})
					}))
				}
				return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, children...)
			})
		}),
	)
}

// stickerThumb paints a sticker's static thumbnail (aspect-fit) or its
// emoji as a text fallback while decoding / when missing.
func (a *App) stickerThumb(gtx layout.Context, st cores.StickerInfo) layout.Dimensions {
	max := gtx.Dp(unit.Dp(52))
	if st.ThumbB64 != "" {
		if img := a.avatarImage("", st.ThumbB64); img != nil {
			return drawImageScaled(gtx, img, max, max, max/8)
		}
		return layout.Dimensions{Size: image.Pt(max, max)} // decode in flight
	}
	if st.Emoji != "" {
		lbl := a.ui.Label(unit.Sp(22), st.Emoji)
		return lbl.Layout(gtx)
	}
	return layout.Dimensions{Size: image.Pt(max, max)}
}

// layoutGifMode: saved-GIF grid.
func (a *App) layoutGifMode(gtx layout.Context, f frame) layout.Dimensions {
	gifs := f.savedGifs
	if len(gifs) == 0 {
		return a.centeredStateLabel(gtx, "No saved GIFs")
	}
	growClickables(&a.wid.gifCellBtns, len(gifs))
	const cols = 4
	const cellDp = unit.Dp(76)
	rows := emojiRowCount(len(gifs), cols)
	a.wid.gifGridList.Axis = layout.Vertical
	gl := material.List(a.ui.Theme, &a.wid.gifGridList)
	return gl.Layout(gtx, rows, func(gtx layout.Context, r int) layout.Dimensions {
		children := make([]layout.FlexChild, 0, cols)
		for c := 0; c < cols; c++ {
			idx := r*cols + c
			if idx >= len(gifs) {
				break
			}
			g := gifs[idx]
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := &a.wid.gifCellBtns[idx]
				if btn.Clicked(gtx) {
					a.sendStickerFile(f, g.FileID)
				}
				cell := gtx.Dp(cellDp)
				gtx.Constraints.Max.X = cell
				gtx.Constraints.Max.Y = cell
				gtx.Constraints.Min = image.Pt(cell, cell)
				bl := material.ButtonLayout(a.ui.Theme, btn)
				bl.Background = a.ui.p.Surface
				bl.CornerRadius = 8
				return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
						max := gtx.Dp(unit.Dp(68))
						if g.ThumbB64 != "" {
							if img := a.avatarImage("", g.ThumbB64); img != nil {
								return drawImageScaled(gtx, img, max, max, max/8)
							}
						}
						lbl := a.ui.Dim(unit.Sp(11), "GIF")
						lbl.Color = a.ui.p.TextFaint
						return lbl.Layout(gtx)
					})
				})
			}))
		}
		return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, children...)
	})
}
