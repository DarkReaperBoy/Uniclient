package gui

// gifts.go — slice 211: the gift picker (tdesktop star_gift_box.cpp's
// catalog flow). Opened from the peer header menu ("Send a gift", user
// peers on gift-capable platforms): the purchasable gift catalog with
// sticker thumbnails, star prices and limited/sold-out badges, the
// account's live balance line, an optional message + hide-name toggle,
// and a Send that buys the gift from the star balance through the real
// payments.getPaymentForm → payments.sendStarsForm chain. Insufficient
// balance is an honest error pointing at the Stars settings page.

import (
	"image"
	"strconv"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/cores"
	"uniclient/engine"
)

var (
	giftBackBtn widget.Clickable
	giftSendBtn widget.Clickable
	giftHideBtn widget.Clickable
	giftList    widget.List
	giftCells   []widget.Clickable // catalog cells (single-select)
	giftMsgEd   widget.Editor
)

func init() {
	giftList.Axis = layout.Vertical
	giftMsgEd.SingleLine = true
}

// giftDlgState is the open gift picker (nil when closed).
type giftDlgState struct {
	accountID string
	chatID    string
	peerTitle string
	gifts     []cores.StarGiftInfo
	balance   int64 // nanostars
	loaded    bool
	err       string
	sel       string // selected GiftID ("" = none)
	sending   bool
}

// giftPriceLabel (pure, testable): whole-star price rendering.
func giftPriceLabel(stars int64) string {
	return itoa64(stars) + " Stars"
}

// giftBuyable (pure, testable): whether a catalog row can be bought —
// sold-out gifts and balance-short gifts cannot (honest disable, the row
// still shows).
func giftBuyable(g cores.StarGiftInfo, balanceNano int64, requirePremiumOwned bool) bool {
	if g.SoldOut {
		return false
	}
	if g.RequirePremium && !requirePremiumOwned {
		return false
	}
	return balanceNano >= g.NanoStars
}

// giftCellSubtitle (pure, testable): the badge line under the price.
func giftCellSubtitle(g cores.StarGiftInfo) string {
	switch {
	case g.SoldOut:
		return "Sold out"
	case g.Limited:
		if g.AvailabilityTotal > 0 {
			return "Limited · " + itoa(g.AvailabilityRemains) + "/" + itoa(g.AvailabilityTotal)
		}
		return "Limited"
	case g.Birthday:
		return "Birthday"
	}
	return ""
}

// openGiftPicker opens the picker for a user peer and kicks the catalog +
// balance loads.
func (a *App) openGiftPicker(c engine.ChatInfo) {
	st := &giftDlgState{
		accountID: c.AccountID,
		chatID:    c.ChatID,
		peerTitle: c.Title,
	}
	a.mu.Lock()
	a.giftDlg = st
	a.mu.Unlock()
	a.invalidate()
	account, chat := c.AccountID, c.ChatID
	go func() {
		gifts, gerr := a.eng.GetStarGifts(account)
		balance, berr := a.eng.GetStarsBalance(account)
		a.mu.Lock()
		if a.giftDlg == nil || a.giftDlg.accountID != account || a.giftDlg.chatID != chat {
			a.mu.Unlock()
			return
		}
		if gerr != nil {
			a.giftDlg.err = gerr.Error()
		} else {
			a.giftDlg.gifts = gifts
		}
		if berr == nil {
			a.giftDlg.balance = balance
		}
		a.giftDlg.loaded = true
		a.mu.Unlock()
		a.invalidate()
	}()
}

// closeGiftPicker dismisses the picker.
func (a *App) closeGiftPicker() {
	a.mu.Lock()
	a.giftDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// sendGift purchases the selected gift through the engine.
func (a *App) sendGift(f frame) {
	st := f.giftDlg
	if st == nil || st.sel == "" || st.sending {
		return
	}
	giftID, err := strconv.ParseInt(st.sel, 10, 64)
	if err != nil {
		a.setToast("Gift: bad id " + st.sel)
		return
	}
	message := giftMsgEd.Text()
	hide := f.giftHideOn
	account, chat := st.accountID, st.chatID
	peerTitle := st.peerTitle
	a.mu.Lock()
	if a.giftDlg != nil {
		a.giftDlg.sending = true
	}
	a.mu.Unlock()
	a.invalidate()
	go func() {
		if err := a.eng.SendStarGift(account, chat, giftID, message, hide); err != nil {
			a.mu.Lock()
			if a.giftDlg != nil {
				a.giftDlg.sending = false
			}
			a.mu.Unlock()
			a.setToast("Gift failed: " + err.Error())
			return
		}
		a.setToast("Gift sent to " + peerTitle)
		a.closeGiftPicker()
	}()
}

// layoutGiftPicker renders the picker (content-pane surface).
func (a *App) layoutGiftPicker(gtx layout.Context, f frame) layout.Dimensions {
	st := f.giftDlg
	if st == nil {
		return layout.Dimensions{}
	}
	if giftBackBtn.Clicked(gtx) {
		a.closeGiftPicker()
	}
	if giftSendBtn.Clicked(gtx) {
		a.sendGift(f)
	}
	if giftHideBtn.Clicked(gtx) {
		a.mu.Lock()
		a.giftHideOn = !a.giftHideOn
		a.mu.Unlock()
		a.invalidate()
	}

	gifts := st.gifts
	growClickables(&giftCells, len(gifts))
	for i, g := range gifts {
		if giftCells[i].Clicked(gtx) {
			a.mu.Lock()
			if a.giftDlg != nil && a.giftDlg.accountID == st.accountID {
				if a.giftDlg.sel == g.GiftID {
					a.giftDlg.sel = ""
				} else {
					a.giftDlg.sel = g.GiftID
				}
			}
			a.mu.Unlock()
			a.invalidate()
		}
	}

	rows := giftGridRows(len(gifts))

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(8), Right: unit.Dp(12)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.IconButton(&giftBackBtn, iconNavigationBack, "Back")
							btn.Color = a.ui.p.TextDim
							return btn.Layout(gtx)
						}),
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										return a.ui.H2("Send a gift").Layout(gtx)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										if st.peerTitle == "" {
											return layout.Dimensions{}
										}
										return a.ui.Dim(unit.Sp(12), st.peerTitle).Layout(gtx)
									}),
								)
							})
						}),
					)
				})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions { return a.ui.Divider(gtx) }),
		// Balance line.
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return a.ui.Dim(unit.Sp(12), "Your balance: "+formatStars(st.balance)+" Stars").Layout(gtx)
			})
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			if !st.loaded {
				return a.centerLoader(gtx)
			}
			if st.err != "" {
				return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(24), Bottom: unit.Dp(24)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return a.ui.Dim(unit.Sp(13), "Gifts unavailable: "+st.err).Layout(gtx)
					})
				})
			}
			if len(gifts) == 0 {
				return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(24), Bottom: unit.Dp(24)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return a.ui.Dim(unit.Sp(13), "No gifts available").Layout(gtx)
					})
				})
			}
			gl := material.List(a.ui.Theme, &giftList)
			return gl.Layout(gtx, rows, func(gtx layout.Context, r int) layout.Dimensions {
				return a.giftGridRow(gtx, f, gifts, r)
			})
		}),
		// Footer: message + hide-name + Send.
		layout.Rigid(func(gtx layout.Context) layout.Dimensions { return a.ui.Divider(gtx) }),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							ed := material.Editor(a.ui.Theme, &giftMsgEd, "Message (optional)")
							ed.TextSize = unit.Sp(14)
							return ed.Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									lbl := material.Button(a.ui.Theme, &giftHideBtn, "Hide my name")
									if f.giftHideOn {
										lbl.Background = a.ui.p.Accent
									} else {
										lbl.Background = a.ui.p.SurfaceHi
									}
									return lbl.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									btn := material.Button(a.ui.Theme, &giftSendBtn, "Send gift")
									if st.sel == "" || st.sending {
										btn.Background = a.ui.p.TextDim
									}
									return btn.Layout(gtx)
								}),
							)
						}),
					)
				})
		}),
	)
}

// giftGridRows (pure, testable): row count for a 3-column grid.
func giftGridRows(n int) int {
	const cols = 3
	return (n + cols - 1) / cols
}

// giftGridRow renders one 3-cell catalog row.
func (a *App) giftGridRow(gtx layout.Context, f frame, gifts []cores.StarGiftInfo, r int) layout.Dimensions {
	const cols = 3
	children := make([]layout.FlexChild, 0, cols)
	for c := 0; c < cols; c++ {
		idx := r*cols + c
		if idx >= len(gifts) {
			break
		}
		g := gifts[idx]
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.giftCell(gtx, f, g, idx)
		}))
	}
	return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, children...)
}

// giftCell renders one catalog cell: sticker thumb (emoji fallback),
// price, badge line, selected state, sold-out disable.
func (a *App) giftCell(gtx layout.Context, f frame, g cores.StarGiftInfo, idx int) layout.Dimensions {
	st := f.giftDlg
	sel := st != nil && st.sel == g.GiftID
	buyable := st != nil && giftBuyable(g, st.balance, accountByID(f, st.accountID).IsPremium)
	cell := gtx.Dp(unit.Dp(110))
	gtx.Constraints.Max.X = cell
	gtx.Constraints.Min.X = cell

	bl := material.ButtonLayout(a.ui.Theme, &giftCells[idx])
	if sel {
		bl.Background = a.ui.p.SurfaceHi
		bl.CornerRadius = 12
	} else {
		bl.Background = a.ui.p.Surface
		bl.CornerRadius = 12
	}
	return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(6), Right: unit.Dp(6)}.Layout(gtx,
			func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						max := gtx.Dp(unit.Dp(52))
						if g.ThumbB64 != "" {
							if img := a.avatarImage("", g.ThumbB64); img != nil {
								return drawImageScaled(gtx, img, max, max, max/8)
							}
						}
						if g.StickerEmoji != "" {
							return a.ui.Label(unit.Sp(22), g.StickerEmoji).Layout(gtx)
						}
						return layout.Dimensions{Size: image.Pt(max, max)}
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(12), giftPriceLabel(g.Stars))
						if buyable {
							lbl.Color = a.ui.p.Accent
						} else {
							lbl.Color = a.ui.p.TextDim
						}
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if s := giftCellSubtitle(g); s != "" {
							return a.ui.Dim(unit.Sp(10), s).Layout(gtx)
						}
						return layout.Dimensions{}
					}),
				)
			})
	})
}

// giftAccountOK (pure, testable): the account's platform exposes the
// star-gift surface — Telegram accounts only (the engine's GiftCore is
// telegram-side, slice 211).
func giftAccountOK(f frame, accountID string) bool {
	acc := accountByID(f, accountID)
	return acc.Platform == "telegram" || acc.Platform == "Telegram"
}
