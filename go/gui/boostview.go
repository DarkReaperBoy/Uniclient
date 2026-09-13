package gui

import (
	"fmt"
	"image"
	"strconv"
	"time"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Boosts page (slice 192, parity row "Giveaways / boosts" — tdesktop's
// boost info box for channels): status card (level, boosts, progress to
// the next level, gift boosts, own-boost state + real premium.applyBoost),
// the boosters list with avatar/name/multiplier/gift/date rows and offset
// paging, Boosters vs Gifts tabs. Opened from the header ⋮ menu for
// channels; other chat types never see it (§1.10). Everything renders from
// real engine state — empty lists show the honest empty row.

var boostPanelTag = new(struct{})

// boostNum reads a numeric field from a map[string]interface{} (JSON
// numbers arrive as float64). Pure.
func boostNum(m map[string]interface{}, field string) (int, bool) {
	if v, ok := m[field]; ok {
		switch n := v.(type) {
		case float64:
			return int(n), true
		case int:
			return n, true
		case int64:
			return int(n), true
		}
	}
	return 0, false
}

// boostLevelLabel: "Level N". Pure.
func boostLevelLabel(st map[string]interface{}) string {
	l, _ := boostNum(st, "level")
	return "Level " + strconv.Itoa(l)
}

// boostProgressFraction: progress from the current level's threshold to
// the next (0..1; 1 when maxed or unknown). Pure.
func boostProgressFraction(st map[string]interface{}) float64 {
	cur, okC := boostNum(st, "boosts")
	lvlCur, okL := boostNum(st, "current_level_boosts")
	lvlNext, okN := boostNum(st, "next_level_boosts")
	if !okC {
		return 0
	}
	if !okL || !okN || lvlNext <= lvlCur {
		return 1 // maxed / unknown ladder → full bar
	}
	frac := float64(cur-lvlCur) / float64(lvlNext-lvlCur)
	if frac < 0 {
		return 0
	}
	if frac > 1 {
		return 1
	}
	return frac
}

// boostToNextLabel: "N boosts to Level M" (or the maxed line). Pure.
func boostToNextLabel(st map[string]interface{}) string {
	cur, okC := boostNum(st, "boosts")
	lvlCur, okL := boostNum(st, "current_level_boosts")
	lvlNext, okN := boostNum(st, "next_level_boosts")
	if !okC || !okL || !okN || lvlNext <= lvlCur {
		return "Max level reached"
	}
	need := lvlNext - cur
	if need < 1 {
		need = 1
	}
	lvl, _ := boostNum(st, "level")
	return fmt.Sprintf("%d boosts to Level %d", need, lvl+1)
}

// boosterRowTitle: the booster's name with an honest fallback. Pure.
func boosterRowTitle(row map[string]interface{}) string {
	if n, ok := row["user_name"].(string); ok && n != "" {
		return n
	}
	if uid, ok := row["user_id"].(int64); ok {
		return "user " + strconv.FormatInt(uid, 10)
	}
	if uid, ok := row["user_id"].(float64); ok {
		return "user " + strconv.Itoa(int(uid))
	}
	return "Booster"
}

// boosterRowSub: "×N multiplier · gift · <date>". Pure.
func boosterRowSub(row map[string]interface{}) string {
	var parts []string
	if mult, ok := boostNum(row, "multiplier"); ok && mult > 1 {
		parts = append(parts, "×"+strconv.Itoa(mult))
	}
	if g, ok := row["gift"].(bool); ok && g {
		parts = append(parts, "gift")
	}
	if u, ok := row["unclaimed"].(bool); ok && u {
		parts = append(parts, "unclaimed")
	}
	if d, ok := boostNum(row, "date"); ok && d > 0 {
		parts = append(parts, time.Unix(int64(d), 0).Format("Jan 2, 2006"))
	}
	out := ""
	for i, p := range parts {
		if i > 0 {
			out += " · "
		}
		out += p
	}
	return out
}

// boostListFields extracts the rows slice, next offset, total count, and
// has-more from a GetBoostsList result map. Pure.
func boostListFields(list map[string]interface{}) (rows []map[string]interface{}, next string, total int, more bool) {
	if v, ok := list["boosters"].([]interface{}); ok {
		for _, r := range v {
			if m, ok := r.(map[string]interface{}); ok {
				rows = append(rows, m)
			}
		}
	}
	if n, ok := list["next_offset"].(string); ok {
		next = n
	}
	total, _ = boostNum(list, "count")
	more = next != ""
	return
}

// openBoostPanel loads the channel's boost status + first booster page.
func (a *App) openBoostPanel() {
	a.mu.Lock()
	k := a.selected
	a.boostPanel = true
	a.boostStatus = nil
	a.boosters = nil
	a.boostNext = ""
	a.boostTotal = 0
	a.boostGifts = false
	a.boostLoad = true
	a.boostErr = ""
	a.headerMenu = nil
	a.mu.Unlock()
	a.invalidate()
	if k == nil {
		return
	}
	acc, chatID := k.AccountID, k.ChatID
	go func() {
		st, err := a.eng.GetBoosts(acc, chatID)
		a.mu.Lock()
		if !a.boostPanel {
			a.mu.Unlock()
			return
		}
		a.boostLoad = false
		if err != nil {
			a.boostErr = err.Error()
			a.mu.Unlock()
			a.setToast("Boosts: " + err.Error())
			return
		}
		a.boostStatus = st
		a.mu.Unlock()
		a.invalidate()
	}()
	a.loadBoosters(acc, chatID, "")
}

// loadBoosters fetches one booster page (appends when offsetting).
func (a *App) loadBoosters(acc, chatID, offset string) {
	gifts := false
	a.mu.Lock()
	gifts = a.boostGifts
	a.mu.Unlock()
	go func() {
		list, err := a.eng.GetBoostsList(acc, chatID, gifts, offset)
		a.mu.Lock()
		if !a.boostPanel {
			a.mu.Unlock()
			return
		}
		if err != nil {
			a.boostErr = err.Error()
			a.mu.Unlock()
			a.setToast("Boosters: " + err.Error())
			return
		}
		rows, next, total, _ := boostListFields(list)
		if offset != "" {
			a.boosters = append(a.boosters, rows...)
		} else {
			a.boosters = rows
		}
		a.boostNext = next
		a.boostTotal = total
		a.mu.Unlock()
		a.invalidate()
	}()
}

// retoggleBoostTabs swaps Boosters/Gifts and reloads page one.
func (a *App) retoggleBoostTabs(gifts bool) {
	a.mu.Lock()
	if a.boostGifts == gifts {
		a.mu.Unlock()
		return
	}
	a.boostGifts = gifts
	a.boosters = nil
	a.boostNext = ""
	a.boostLoad = true
	k := a.selected
	a.mu.Unlock()
	a.invalidate()
	if k == nil {
		return
	}
	a.loadBoosters(k.AccountID, k.ChatID, "")
}

// applyOwnBoost spends one of the account's own boost slots on this
// channel (premium.applyBoost) and refreshes the status card.
func (a *App) applyOwnBoost() {
	a.mu.Lock()
	k := a.selected
	a.mu.Unlock()
	if k == nil {
		return
	}
	go func() {
		if err := a.eng.ApplyBoost(k.AccountID, k.ChatID); err != nil {
			a.setToast("Boost failed: " + err.Error())
			return
		}
		a.setToast("Channel boosted")
		go func() {
			st, err := a.eng.GetBoosts(k.AccountID, k.ChatID)
			a.mu.Lock()
			if !a.boostPanel || err != nil {
				a.mu.Unlock()
				return
			}
			a.boostStatus = st
			a.mu.Unlock()
			a.invalidate()
		}()
	}()
}

// closeBoostPanel dismisses the page.
func (a *App) closeBoostPanel() {
	a.mu.Lock()
	if !a.boostPanel {
		a.mu.Unlock()
		return
	}
	a.boostPanel = false
	a.boostStatus = nil
	a.boosters = nil
	a.mu.Unlock()
	a.invalidate()
}

// layoutBoostPanel: the boosts page (chat-pane replacement).
func (a *App) layoutBoostPanel(gtx layout.Context, f frame, chat *engine.ChatInfo) layout.Dimensions {
	{
		stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
		event.Op(gtx.Ops, boostPanelTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeBoostPanel()
		}
	}
	if a.wid.boostPanelBack.Clicked(gtx) {
		a.closeBoostPanel()
	}
	if a.wid.boostTabBoosters.Clicked(gtx) {
		a.retoggleBoostTabs(false)
	}
	if a.wid.boostTabGifts.Clicked(gtx) {
		a.retoggleBoostTabs(true)
	}
	if a.wid.boostMoreBtn.Clicked(gtx) {
		a.mu.Lock()
		k := a.selected
		off := a.boostNext
		a.mu.Unlock()
		if k != nil && off != "" {
			a.loadBoosters(k.AccountID, k.ChatID, off)
		}
	}
	if a.wid.boostApplyBtn.Clicked(gtx) {
		a.applyOwnBoost()
	}

	title := "Boosts"
	if chat != nil {
		title = "Boosts · " + chat.Title
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(8), Right: unit.Dp(12)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.IconButton(&a.wid.boostPanelBack, iconNavigationBack, "Back to chat")
							return btn.Layout(gtx)
						}),
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.H3(title)
							return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, lbl.Layout)
						}),
					)
				})
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			return a.boostScroll(gtx, f)
		}),
	)
}

// boostScroll: status card + tabs + rows.
func (a *App) boostScroll(gtx layout.Context, f frame) layout.Dimensions {
	st := f.boostStatus
	var children []layout.FlexChild

	// Status card.
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		if st == nil {
			label := "Loading…"
			if f.boostErr != "" {
				label = "Boosts unavailable: " + f.boostErr
			}
			return layout.Inset{Top: unit.Dp(16), Left: unit.Dp(16), Right: unit.Dp(16)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(14), label)
					return lbl.Layout(gtx)
				})
		}
		boosts, _ := boostNum(st, "boosts")
		gift, _ := boostNum(st, "gift_boosts")
		myBoost, _ := st["my_boost"].(bool)
		frac := boostProgressFraction(st)

		return layout.Inset{Top: unit.Dp(8), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx,
			func(gtx layout.Context) layout.Dimensions {
				return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(14)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										lbl := a.ui.H3(boostLevelLabel(st))
										return lbl.Layout(gtx)
									}),
									layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
										return layout.Dimensions{}
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										lbl := a.ui.Dim(unit.Sp(14), strconv.Itoa(boosts)+" boosts")
										return lbl.Layout(gtx)
									}),
								)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											lbl := a.ui.Dim(unit.Sp(12), boostToNextLabel(st))
											return lbl.Layout(gtx)
										}),
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
												return boostProgressBar(gtx, a, frac)
											})
										}),
									)
								})
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								sub := ""
								if gift > 0 {
									sub = strconv.Itoa(gift) + " gift boosts"
								}
								if myBoost {
									if sub != "" {
										sub += " · "
									}
									sub += "You boosted this channel"
								}
								if sub == "" {
									return layout.Dimensions{}
								}
								return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Dim(unit.Sp(12), sub)
									return lbl.Layout(gtx)
								})
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								// Spend one of our own slots (premium.applyBoost).
								label := "Boost this channel"
								if myBoost {
									label = "Boost again"
								}
								return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									btn := material.Button(a.ui.Theme, &a.wid.boostApplyBtn, label)
									btn.CornerRadius = 10
									btn.TextSize = unit.Sp(13)
									return btn.Layout(gtx)
								})
							}),
						)
					})
				})
			})
	}))

	// Tabs.
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(10), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx,
			func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return boostTabBtn(gtx, a, &a.wid.boostTabBoosters, "Boosters", !f.boostGifts)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return boostTabBtn(gtx, a, &a.wid.boostTabGifts, "Gifts", f.boostGifts)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						if f.boostTotal > 0 {
							return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(12), strconv.Itoa(f.boostTotal)+" total")
								return lbl.Layout(gtx)
							})
						}
						return layout.Dimensions{}
					}),
				)
			})
	}))

	// Rows.
	rows := f.boosters
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		if f.boostLoad && len(rows) == 0 {
			return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(13), "Loading boosters…")
				return lbl.Layout(gtx)
			})
		}
		if len(rows) == 0 {
			// Honest empty state (§1.10): real server list, zero rows.
			empty := "No boosters yet"
			if f.boostGifts {
				empty = "No gift boosts"
			}
			if f.boostErr != "" && st == nil && f.boostStatus == nil {
				empty = "Boosters unavailable: " + f.boostErr
			}
			return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(13), empty)
				return lbl.Layout(gtx)
			})
		}
		var listChildren []layout.FlexChild
		for _, row := range rows {
			row := row
			listChildren = append(listChildren, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(4), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx,
					func(gtx layout.Context) layout.Dimensions {
						return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
							return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										lbl := a.ui.Label(unit.Sp(14), boosterRowTitle(row))
										return lbl.Layout(gtx)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										if sub := boosterRowSub(row); sub != "" {
											return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
												lbl := a.ui.Dim(unit.Sp(12), sub)
												return lbl.Layout(gtx)
											})
										}
										return layout.Dimensions{}
									}),
								)
							})
						})
					})
			}))
		}
		// Load-more row.
		if f.boostNext != "" {
			listChildren = append(listChildren, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.TextButton(&a.wid.boostMoreBtn, "Load more")
					return btn.Layout(gtx)
				})
			}))
		}
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, listChildren...)
	}))

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// boostProgressBar: the level progress track (rounded fill + accent).
func boostProgressBar(gtx layout.Context, a *App, frac float64) layout.Dimensions {
	w := gtx.Constraints.Max.X
	if w <= 0 {
		return layout.Dimensions{}
	}
	h := gtx.Dp(unit.Dp(4))
	// Track.
	paint.FillShape(gtx.Ops, a.ui.p.SurfaceHi, clip.Rect{Max: image.Pt(w, h)}.Op())
	// Fill.
	fw := int(float64(w) * frac)
	if fw > 0 {
		paint.FillShape(gtx.Ops, a.ui.p.Accent, clip.Rect{Max: image.Pt(fw, h)}.Op())
	}
	return layout.Dimensions{Size: image.Pt(w, h)}
}

// boostTabBtn: one tab chip.
func boostTabBtn(gtx layout.Context, a *App, btn *widget.Clickable, label string, active bool) layout.Dimensions {
	b := material.Button(a.ui.Theme, btn, label)
	b.CornerRadius = 8
	b.TextSize = unit.Sp(12)
	if active {
		b.Background = a.ui.p.Accent
	} else {
		b.Background = a.ui.p.Surface
		b.Color = a.ui.p.Text
	}
	return b.Layout(gtx)
}
