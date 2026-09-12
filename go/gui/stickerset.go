package gui

// Sticker pack info/add (AyuGram parity slice 108): sticker messages gain
// a context-menu "View sticker pack" — a card dialog over the engine's
// sticker-set info (title, count, kind, installed state, thumbnail grid)
// with an Install button dispatching engine.InstallStickerSet. Set keys
// parse from the message's cached MediaExtra; sticker messages without
// keys (or cores without the fetcher) honestly get no menu item (§1.10).

import (
	"encoding/json"
	"image"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget/material"

	"uniclient/cores"
	"uniclient/engine"
)

// stickerSetDlgState is the open sticker-pack dialog.
type stickerSetDlgState struct {
	accountID  string
	shortName  string
	setID      int64
	accessHash int64

	set     *cores.StickerSetResult
	loading bool
	err     string
}

// stickerSetKeys parses the pack identifier from a sticker message's
// cached media extra (pure).
func stickerSetKeys(m engine.CachedMessage) (shortName string, setID, accessHash int64, ok bool) {
	if m.MediaType != engine.MediaSticker || m.MediaExtra == "" {
		return "", 0, 0, false
	}
	var extra struct {
		ShortName  string `json:"sticker_set_short_name"`
		SetID      int64  `json:"sticker_set_id"`
		AccessHash int64  `json:"sticker_set_access_hash"`
	}
	if err := json.Unmarshal([]byte(m.MediaExtra), &extra); err != nil {
		return "", 0, 0, false
	}
	if extra.ShortName != "" {
		return extra.ShortName, 0, 0, true
	}
	if extra.SetID != 0 {
		return "", extra.SetID, extra.AccessHash, true
	}
	return "", 0, 0, false
}

// stickerPackMenuGate: which messages offer the pack dialog item.
func stickerPackMenuGate(m engine.CachedMessage) bool {
	_, _, _, ok := stickerSetKeys(m)
	return ok
}

// stickerPackSummaryLabel renders the count line.
func stickerPackSummaryLabel(s *cores.StickerSetResult) string {
	switch {
	case s == nil || s.Count == 0:
		return "no stickers"
	case s.Count == 1:
		return "1 sticker"
	default:
		return itoa(s.Count) + " stickers"
	}
}

// stickerPackKindLabel renders the pack kind line.
func stickerPackKindLabel(s *cores.StickerSetResult) string {
	if s == nil {
		return "static"
	}
	switch {
	case s.Video:
		return "video"
	case s.Animated:
		return "animated"
	case s.Emojis:
		return "custom emoji"
	}
	return "static"
}

// ── state transitions ─────────────────────────────────────────────────────

var (
	stickerSetKeyTag = new(struct{})
)

// openStickerSetDialog opens the pack viewer for a sticker message.
func (a *App) openStickerSetDialog(m *engine.CachedMessage) {
	if m == nil {
		return
	}
	sn, id, hash, ok := stickerSetKeys(*m)
	if !ok {
		return
	}
	a.mu.Lock()
	a.stickerSetDlg = &stickerSetDlgState{
		accountID:  m.AccountID,
		shortName:  sn,
		setID:      id,
		accessHash: hash,
		loading:    true,
	}
	a.mu.Unlock()
	a.invalidate()
	go func() {
		set, err := a.eng.GetStickerSetInfo(m.AccountID, sn, id, hash)
		a.mu.Lock()
		d := a.stickerSetDlg
		if d == nil || d.accountID != m.AccountID || d.shortName != sn || d.setID != id {
			a.mu.Unlock()
			return
		}
		d.loading = false
		if err != nil {
			d.err = err.Error()
		} else {
			d.set = set
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// closeStickerSetDialog dismisses it.
func (a *App) closeStickerSetDialog() {
	a.mu.Lock()
	a.stickerSetDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// installStickerSet dispatches the engine install.
func (a *App) installStickerSet(d *stickerSetDlgState) {
	if d == nil || d.set == nil {
		return
	}
	setID, hash := d.set.SetID, d.set.AccessHash
	if setID == 0 {
		setID, hash = d.setID, d.accessHash
	}
	accountID := d.accountID
	go func() {
		if err := a.eng.InstallStickerSet(accountID, setID, hash); err != nil {
			a.setToast("Add pack failed: " + err.Error())
			return
		}
		a.setToast("Sticker pack added")
		a.mu.Lock()
		if cur := a.stickerSetDlg; cur != nil && cur.set != nil {
			cur.set.Installed = true
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// ── layout ────────────────────────────────────────────────────────────────

// layoutStickerSetDialog renders the pack card (msgDetail card pattern).
func (a *App) layoutStickerSetDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.stickerSetDlg

	// Keyboard: Esc closes.
	{
		stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
		event.Op(gtx.Ops, stickerSetKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeStickerSetDialog()
		}
	}

	if a.wid.stickerSetCloseBtn.Clicked(gtx) {
		a.closeStickerSetDialog()
	}

	var stickers []cores.StickerInfo
	if d.set != nil {
		stickers = d.set.Stickers
	}

	title := "Sticker pack"
	if d.set != nil && d.set.Title != "" {
		title = d.set.Title
	} else if d.shortName != "" {
		title = d.shortName
	}

	cardW := gtx.Dp(unit.Dp(340))
	if cardW > gtx.Constraints.Max.X-gtx.Dp(unit.Dp(32)) {
		cardW = gtx.Constraints.Max.X - gtx.Dp(unit.Dp(32))
	}

	growClickables(&a.wid.stickerSetCellBtns, len(stickers))
	if d.set != nil && !d.set.Installed && a.wid.stickerSetInstallBtn.Clicked(gtx) {
		a.installStickerSet(d)
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = cardW
		gtx.Constraints.Min.X = cardW
		return roundedFill(gtx, a.ui.p.Surface, 14, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					// Header: title + close.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(16), title)
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								btn := a.ui.IconButton(&a.wid.stickerSetCloseBtn, iconContentClear, "Close")
								btn.Color = a.ui.p.TextDim
								return btn.Layout(gtx)
							}),
						)
					}),
					// Status / summary / install.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							switch {
							case d.loading:
								lbl := a.ui.Dim(unit.Sp(13), "Loading pack…")
								lbl.Color = a.ui.p.TextFaint
								return lbl.Layout(gtx)
							case d.err != "":
								lbl := a.ui.Dim(unit.Sp(13), "Could not load pack: "+d.err)
								lbl.Color = a.ui.p.Error
								return lbl.Layout(gtx)
							case d.set == nil:
								lbl := a.ui.Dim(unit.Sp(13), "No stickers")
								lbl.Color = a.ui.p.TextFaint
								return lbl.Layout(gtx)
							default:
								return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										line := stickerPackSummaryLabel(d.set) + " · " + stickerPackKindLabel(d.set)
										if d.set.Installed {
											line += " · installed"
										}
										lbl := a.ui.Dim(unit.Sp(12), line)
										lbl.Color = a.ui.p.TextDim
										return lbl.Layout(gtx)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										if d.set.Installed {
											return layout.Dimensions{}
										}
										return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
											btn := a.ui.PrimaryButton(&a.wid.stickerSetInstallBtn, "ADD TO STICKERS")
											return btn.Layout(gtx)
										})
									}),
								)
							}
						})
					}),
					// Sticker grid (5 columns, thumbnails only — the
					// a.wid.composer picker's cell rendering).
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if len(stickers) == 0 {
							return layout.Dimensions{}
						}
						const cols = 5
						const cellDp = unit.Dp(60)
						rows := emojiRowCount(len(stickers), cols)
						maxH := gtx.Dp(unit.Dp(240))
						gtx.Constraints.Max.Y = maxH
						gl := material.List(a.ui.Theme, &a.wid.stickerSetGrid)
						return gl.Layout(gtx, rows, func(gtx layout.Context, r int) layout.Dimensions {
							children := make([]layout.FlexChild, 0, cols)
							for c := 0; c < cols; c++ {
								idx := r*cols + c
								if idx >= len(stickers) {
									break
								}
								st := stickers[idx]
								children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									cell := gtx.Dp(cellDp)
									gtx.Constraints.Max.X = cell
									gtx.Constraints.Max.Y = cell
									gtx.Constraints.Min = image.Pt(cell, cell)
									return roundedFill(gtx, a.ui.p.SurfaceHi, 8, func(gtx layout.Context) layout.Dimensions {
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
			})
		})
	})
}
