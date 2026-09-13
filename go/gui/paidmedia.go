package gui

import (
	"bytes"
	"encoding/json"
	"image"
	"image/color"

	"gioui.org/font"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Paid-media star wall (slice 181, parity row "Paid messages / paid
// posts" — tdesktop's blurred paid-media wall): locked paid media
// renders a darkened preview wall with the star price and an Unlock
// button; unlocking walks the engine's UnlockPaidMedia
// (payments.getPaymentForm → payments.sendStarsForm), and the server's
// message update turns the wall into the real media bubble
// (paid_unlocked). Never shown for plain bot invoices or unlocked media
// (§1.10).

// paidData is the parsed paid-media Extra of one message.
type paidData struct {
	Stars      int64
	ThumbB64   string
	W, H       int
	VideoDur   int
	FirstVideo bool
	Unlocked   bool
}

// parsePaidMedia extracts the paid-media fields from a cached message's
// raw Extra. Nil when the message is not paid media. Pure — tested.
func parsePaidMedia(m *engine.CachedMessage) *paidData {
	if m == nil || len(m.ContentRaw) == 0 {
		return nil
	}
	if !bytes.Contains(m.ContentRaw, []byte(`"invoice_is_paid_media"`)) {
		return nil
	}
	var env struct {
		Extra map[string]interface{} `json:"extra"`
	}
	if err := json.Unmarshal(m.ContentRaw, &env); err != nil || env.Extra == nil {
		return nil
	}
	if v, _ := env.Extra["invoice_is_paid_media"].(bool); !v {
		return nil
	}
	p := &paidData{
		FirstVideo: env.Extra["invoice_first_video"] == true,
		Unlocked:   env.Extra["paid_unlocked"] == true,
	}
	if f, ok := env.Extra["paid_stars"].(float64); ok {
		p.Stars = int64(f)
	}
	p.ThumbB64, _ = env.Extra["paid_thumb_b64"].(string)
	if f, ok := env.Extra["paid_w"].(float64); ok {
		p.W = int(f)
	}
	if f, ok := env.Extra["paid_h"].(float64); ok {
		p.H = int(f)
	}
	if f, ok := env.Extra["paid_video_duration"].(float64); ok {
		p.VideoDur = int(f)
	}
	return p
}

// paidWallVisible: locked paid media renders the wall.
func paidWallVisible(p *paidData) bool {
	return p != nil && !p.Unlocked
}

// paidStarsText: "1 Star" / "25 Stars" ("" when free). Pure.
func paidStarsText(stars int64) string {
	if stars <= 0 {
		return ""
	}
	if stars == 1 {
		return "1 Star"
	}
	return itoa64(stars) + " Stars"
}

// layoutPaidMediaWall renders the star wall inside the bubble: the
// darkened preview (stripped thumb, aspect-true box), the star glyph +
// price label overlay, and the Unlock button below.
func (a *App) layoutPaidMediaWall(gtx layout.Context, m *engine.CachedMessage, p *paidData) layout.Dimensions {
	key := m.AccountID + "|" + m.ChatID + "|" + m.MsgID
	btn := a.paidUnlockClickable(key)
	if btn.Clicked(gtx) {
		a.confirmUnlockPaidMedia(m, p)
	}

	w := gtx.Constraints.Max.X
	h := w
	if p.W > 0 && p.H > 0 {
		h = w * p.H / p.W
	}
	if cap := gtx.Dp(unit.Dp(360)); h > cap {
		h = cap
	}

	var rows []layout.FlexChild
	rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.SurfaceHi, unit.Dp(10), func(gtx layout.Context) layout.Dimensions {
			// The preview: dark scrim over the low-res thumb (tdesktop
			// blurs; a uniform scrim is the honest pure-Go equivalent —
			// the preview is already "extremely low resolution").
			d := layout.Dimensions{}
			if p.ThumbB64 != "" {
				if img := mediaImgs.get("thumb:" + p.ThumbB64); img != nil {
					d = drawImageScaled(gtx, img, w, h, gtx.Dp(unit.Dp(10)))
				} else {
					a.decodeThumbAsync("thumb:"+p.ThumbB64, p.ThumbB64)
					d = layout.Dimensions{Size: image.Pt(w, h)}
				}
			} else {
				d = layout.Dimensions{Size: image.Pt(w, h)}
			}
			stack := clip.Rect{Max: d.Size}.Push(gtx.Ops)
			paint.FillShape(gtx.Ops, color.NRGBA{R: 0, G: 0, B: 0, A: 0x8C}, clip.Rect{Max: d.Size}.Op())
			stack.Pop()
			// Star glyph + price centered over the scrim.
			return layout.Stack{}.Layout(gtx,
				layout.Expanded(func(gtx layout.Context) layout.Dimensions { return d }),
				layout.Stacked(func(gtx layout.Context) layout.Dimensions {
					return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								gtx.Constraints.Max.X = gtx.Dp(unit.Dp(40))
								gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(40))
								return iconToggleStar.Layout(gtx, a.ui.p.Accent)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(16), paidStarsText(p.Stars))
								lbl.Color = color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF}
								lbl.Font.Weight = font.Bold
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								kind := "Photo"
								if p.FirstVideo {
									kind = "Video"
								}
								lbl := a.ui.Label(unit.Sp(12), kind)
								lbl.Color = color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xD0}
								return lbl.Layout(gtx)
							}),
						)
					})
				}),
			)
		})
	}))
	rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return roundedFill(gtx, a.ui.p.Accent, unit.Dp(10), func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(14), "Unlock for "+paidStarsText(p.Stars))
						lbl.Color = a.ui.p.Background
						lbl.Font.Weight = font.Bold
						return lbl.Layout(gtx)
					})
				})
			})
		})
	}))
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
}

// paidUnlockClickable pools the unlock buttons per message.
func (a *App) paidUnlockClickable(key string) *widget.Clickable {
	if c, ok := a.wid.paidUnlockBtns[key]; ok {
		return c
	}
	if len(a.wid.paidUnlockBtns) > 256 {
		a.wid.paidUnlockBtns = make(map[string]*widget.Clickable)
	}
	c := new(widget.Clickable)
	a.wid.paidUnlockBtns[key] = c
	return c
}

// confirmUnlockPaidMedia arms the paid-media confirm dialog (real stars
// leave the balance — always ask).
func (a *App) confirmUnlockPaidMedia(m *engine.CachedMessage, p *paidData) {
	a.mu.Lock()
	a.paidDlg = &paidConfirmState{
		accountID: m.AccountID,
		chatID:    m.ChatID,
		msgID:     m.MsgID,
		stars:     p.Stars,
	}
	a.mu.Unlock()
	a.invalidate()
}

// paidConfirmState is the unlock confirm card.
type paidConfirmState struct {
	accountID string
	chatID    string
	msgID     string
	stars     int64
}

// layoutPaidConfirm renders the confirm card over a scrim.
func (a *App) layoutPaidConfirm(gtx layout.Context, f frame) layout.Dimensions {
	st := f.paidDlg
	if a.wid.paidConfirmBtn.Clicked(gtx) {
		acc, chat, msg, stars := st.accountID, st.chatID, st.msgID, st.stars
		a.mu.Lock()
		a.paidDlg = nil
		a.mu.Unlock()
		a.invalidate()
		go func() {
			if err := a.eng.UnlockPaidMedia(acc, chat, msg); err != nil {
				a.setToast("Unlock failed: " + err.Error())
				return
			}
			a.setToast("Paid " + paidStarsText(stars) + " — media unlocked")
			a.refreshMessages()
		}()
	}
	if a.wid.paidCancelBtn.Clicked(gtx) {
		a.closePaidConfirm()
	}

	paint.FillShape(gtx.Ops, color.NRGBA{R: 0, G: 0, B: 0, A: 0x66},
		clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Op())

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		cardW := gtx.Dp(unit.Dp(340))
		if cardW > gtx.Constraints.Max.X {
			cardW = gtx.Constraints.Max.X
		}
		gtx.Constraints.Max.X = cardW
		return roundedFill(gtx, a.ui.p.Surface, unit.Dp(16), func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(18)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							gtx.Constraints.Max.X = gtx.Dp(unit.Dp(36))
							gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(36))
							return iconToggleStar.Layout(gtx, a.ui.p.Accent)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.H3("Unlock paid media")
								return lbl.Layout(gtx)
							})
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(13), "Pay "+paidStarsText(st.stars)+" from your balance to view this media.")
								lbl.MaxLines = 2
								return lbl.Layout(gtx)
							})
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									btn := material.Button(a.ui.Theme, &a.wid.paidCancelBtn, "Cancel")
									btn.Background = a.ui.p.SurfaceHi
									btn.Color = a.ui.p.Text
									btn.CornerRadius = 12
									return btn.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
										btn := material.Button(a.ui.Theme, &a.wid.paidConfirmBtn, "Pay "+paidStarsText(st.stars))
										btn.Background = a.ui.p.Accent
										btn.Color = a.ui.p.Background
										btn.CornerRadius = 12
										return btn.Layout(gtx)
									})
								}),
							)
						})
					}),
				)
			})
		})
	})
}

// closePaidConfirm dismisses the card.
func (a *App) closePaidConfirm() {
	a.mu.Lock()
	a.paidDlg = nil
	a.mu.Unlock()
	a.invalidate()
}
