package gui

import (
	"bytes"
	"encoding/json"
	"image"

	"gioui.org/font"
	"gioui.org/layout"
	"gioui.org/unit"

	"uniclient/engine"
)

// Gift card bubbles (slice 180, parity row "Gift / star-gift messages"
// — tdesktop's gift bubble): service messages carrying gift_* Extra
// (written by the telegram core's convertServiceMessage for
// messageActionStarGift / GiftStars / GiftTon) render as a centered
// gift card — sticker artwork, star-count pill, the sender's note,
// limited/converted chips — instead of the flat service line.

// giftData is the parsed gift Extra of one message.
type giftData struct {
	Kind      string // stargift | stars | ton
	Stars     int64
	Text      string
	ThumbB64  string
	Limited   bool
	Saved     bool
	Converted bool
	Refunded  bool
}

// parseGift extracts the gift fields from a cached message's raw Extra.
// Nil when the message carries no gift. Pure — unit-tested.
func parseGift(m *engine.CachedMessage) *giftData {
	if m == nil || len(m.ContentRaw) == 0 {
		return nil
	}
	if !bytes.Contains(m.ContentRaw, []byte(`"gift_kind"`)) {
		return nil
	}
	var env struct {
		Extra map[string]interface{} `json:"extra"`
	}
	if err := json.Unmarshal(m.ContentRaw, &env); err != nil || env.Extra == nil {
		return nil
	}
	kind, _ := env.Extra["gift_kind"].(string)
	if kind == "" {
		return nil
	}
	g := &giftData{Kind: kind}
	if f, ok := env.Extra["gift_stars"].(float64); ok {
		g.Stars = int64(f)
	}
	g.Text, _ = env.Extra["gift_text"].(string)
	g.ThumbB64, _ = env.Extra["gift_thumb_b64"].(string)
	g.Limited, _ = env.Extra["gift_limited"].(bool)
	g.Saved, _ = env.Extra["gift_saved"].(bool)
	g.Converted, _ = env.Extra["gift_converted"].(bool)
	g.Refunded, _ = env.Extra["gift_refunded"].(bool)
	return g
}

// giftStarsText: "1 Star" / "75 Stars" ("" when none). Pure.
func giftStarsText(stars int64) string {
	if stars <= 0 {
		return ""
	}
	if stars == 1 {
		return "1 Star"
	}
	return itoa64(stars) + " Stars"
}

// giftBubbleVisible: parsed gifts render the card.
func giftBubbleVisible(g *giftData) bool {
	return g != nil
}

// layoutGiftBubble renders the gift card (centered, like tdesktop's):
// sticker artwork (stripped thumb, square), the star-count pill, the
// sender's note, and the status chips (Limited / Converted / Refunded /
// Saved).
func (a *App) layoutGiftBubble(gtx layout.Context, m *engine.CachedMessage, g *giftData) layout.Dimensions {
	maxW := gtx.Constraints.Max.X
	side := maxW
	if cap := gtx.Dp(unit.Dp(220)); side > cap {
		side = cap
	}

	var rows []layout.FlexChild

	// Sticker artwork (stripped thumb; placeholder box while decoding).
	if g.ThumbB64 != "" {
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				if img := mediaImgs.get("thumb:" + g.ThumbB64); img != nil {
					return drawImageScaled(gtx, img, side, side, 0)
				}
				a.decodeThumbAsync("thumb:"+g.ThumbB64, g.ThumbB64)
				return layout.Dimensions{Size: image.Pt(side, side)}
			})
		}))
	}

	// Star-count pill (stars gifts + star gifts both carry counts).
	if st := giftStarsText(g.Stars); st != "" && g.Kind != "ton" {
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return roundedFill(gtx, a.ui.p.Accent, unit.Dp(12), func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3), Left: unit.Dp(10), Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(13), "★ "+st)
							lbl.Color = a.ui.p.Background
							lbl.Font.Weight = font.Bold
							return lbl.Layout(gtx)
						})
					})
				})
			})
		}))
	}

	// The sender's note.
	if g.Text != "" {
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(13), g.Text)
					lbl.Color = a.ui.p.TextDim
					lbl.MaxLines = 3
					return lbl.Layout(gtx)
				})
			})
		}))
	}

	// Status chips.
	var chips []string
	if g.Limited {
		chips = append(chips, "Limited")
	}
	if g.Converted {
		chips = append(chips, "Converted to Stars")
	}
	if g.Refunded {
		chips = append(chips, "Refunded")
	}
	if g.Saved {
		chips = append(chips, "On profile")
	}
	if len(chips) > 0 {
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
						flexForEach(len(chips), func(gtx layout.Context, i int) layout.Dimensions {
							return layout.Inset{Right: unit.Dp(4), Left: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return roundedFill(gtx, a.ui.p.SurfaceHi, unit.Dp(8), func(gtx layout.Context) layout.Dimensions {
									return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(8), Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
										lbl := a.ui.Label(unit.Sp(11), chips[i])
										lbl.Color = a.ui.p.TextDim
										return lbl.Layout(gtx)
									})
								})
							})
						})...)
				})
			})
		}))
	}

	return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			gtx.Constraints.Max.X = side + gtx.Dp(unit.Dp(24))
			return roundedFill(gtx, a.ui.p.Surface, unit.Dp(14), func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(12)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
				})
			})
		})
	})
}
