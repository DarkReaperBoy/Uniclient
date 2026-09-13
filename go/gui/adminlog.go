package gui

import (
	"image"
	"time"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget/material"

	"uniclient/cores"
	"uniclient/engine"
)

// Admin log / Recent Actions panel (slice 177, parity row "Moderation
// (admin log, restrictions)" — tdesktop's Recent Actions window): a
// searchable, filterable, paginated event list over the engine's
// GetAdminLogEvents (channels.getAdminLog). Opened from the chat-header
// ⋮ menu for admins of groups/channels. Message events render their
// media preview inline (ActionData's stripped thumb); change events show
// old → new values.

var adminPanelTag = new(struct{})

// adminFilterDef is one filter chip (channels.getAdminLogEventsFilter).
type adminFilterDef struct {
	id    string
	label string
}

// adminFilterDefs mirrors tdesktop's admin-log filter box (the events
// filter surface the core accepts).
var adminFilterDefs = []adminFilterDef{
	{"join", "Joined"},
	{"leave", "Left"},
	{"invite", "Invites"},
	{"ban", "Bans"},
	{"unban", "Unbans"},
	{"kick", "Removed"},
	{"unkick", "Re-added"},
	{"promote", "Promotions"},
	{"demote", "Demotions"},
	{"info", "Info"},
	{"settings", "Settings"},
	{"pinned", "Pinned"},
	{"group_call", "Calls"},
	{"stickers", "Stickers"},
	{"messages", "Messages"},
	{"edit", "Edited"},
	{"delete", "Deleted"},
	{"invites", "Invite links"},
}

// adminToggleFilter flips one filter in the active set (pure).
func adminToggleFilter(active map[string]bool, id string) {
	active[id] = !active[id]
}

// adminLogMaxID returns the paging cursor: the smallest event ID seen
// (pure).
func adminLogMaxID(events []cores.AdminLogEvent) int64 {
	if len(events) == 0 {
		return 0
	}
	min := events[0].ID
	for _, e := range events[1:] {
		if e.ID < min {
			min = e.ID
		}
	}
	return min
}

// adminEventHeadline: the acting admin's name (row title).
func adminEventHeadline(e cores.AdminLogEvent) string {
	if e.UserName != "" {
		return e.UserName
	}
	return "Admin " + userIDStr(e.UserID)
}

// adminEventActionText: the action sentence.
func adminEventActionText(e cores.AdminLogEvent) string {
	return e.Action
}

// adminEventSub: the one-line detail under the action.
func adminEventSub(e cores.AdminLogEvent) string {
	return e.Detail
}

// adminEventChanges: the old/new pair when the event is a change.
func adminEventChanges(e cores.AdminLogEvent) []string {
	if e.OldValue == "" && e.NewValue == "" {
		return nil
	}
	if e.OldValue == "" {
		return []string{e.NewValue}
	}
	if e.NewValue == "" {
		return []string{e.OldValue}
	}
	return []string{e.OldValue, e.NewValue}
}

// adminEventMedia extracts the message-event media type + stripped thumb
// from ActionData (pure).
func adminEventMedia(e cores.AdminLogEvent) (int, string) {
	if e.ActionData == nil {
		return 0, ""
	}
	var mt int
	if f, ok := e.ActionData["media_type"].(float64); ok {
		mt = int(f)
	}
	tb, _ := e.ActionData["thumb_b64"].(string)
	return mt, tb
}

// adminEventHasMessage reports whether the row shows a message preview.
func adminEventHasMessage(e cores.AdminLogEvent) bool {
	return e.MsgText != "" || e.MessageID != 0
}

// openAdminPanel loads the first page for the open chat.
func (a *App) openAdminPanel() {
	a.mu.Lock()
	k := a.selected
	a.adminPanel = true
	a.adminEvents = nil
	a.adminLoad = true
	a.adminLoadedAll = false
	a.adminFor = k
	a.adminFilters = nil
	a.headerMenu = nil
	a.mu.Unlock()
	a.wid.adminSearchEd.SetText("")
	a.invalidate()
	if k == nil {
		return
	}
	a.adminLogFetch(k.AccountID, k.ChatID, 0, "", nil)
}

// closeAdminPanel dismisses it.
func (a *App) closeAdminPanel() {
	a.mu.Lock()
	if !a.adminPanel {
		a.mu.Unlock()
		return
	}
	a.adminPanel = false
	a.adminEvents = nil
	a.adminFor = nil
	a.mu.Unlock()
	a.invalidate()
}

// adminToggleFilterNow flips a chip and refetches.
func (a *App) adminToggleFilterNow(id string) {
	a.mu.Lock()
	if a.adminFilters == nil {
		a.adminFilters = map[string]bool{}
	}
	adminToggleFilter(a.adminFilters, id)
	active := map[string]bool{}
	for k, v := range a.adminFilters {
		active[k] = v
	}
	k := a.adminFor
	a.adminEvents = nil
	a.adminLoad = true
	a.adminLoadedAll = false
	a.mu.Unlock()
	a.invalidate()
	if k == nil {
		return
	}
	a.adminLogFetch(k.AccountID, k.ChatID, 0, a.wid.adminSearchEd.Text(), active)
}

// adminLogSearch refetches with the field's query.
func (a *App) adminLogSearch() {
	a.mu.Lock()
	k := a.adminFor
	if k == nil {
		a.mu.Unlock()
		return
	}
	active := map[string]bool{}
	if a.adminFilters != nil {
		for kk, v := range a.adminFilters {
			active[kk] = v
		}
	}
	a.adminEvents = nil
	a.adminLoad = true
	a.adminLoadedAll = false
	a.mu.Unlock()
	q := a.wid.adminSearchEd.Text()
	a.invalidate()
	a.adminLogFetch(k.AccountID, k.ChatID, 0, q, active)
}

// adminLoadMore pages with the smallest seen ID as the cursor.
func (a *App) adminLoadMore() {
	a.mu.Lock()
	k := a.adminFor
	if k == nil || a.adminLoad || a.adminLoadedAll {
		a.mu.Unlock()
		return
	}
	maxID := adminLogMaxID(a.adminEvents)
	if maxID == 0 {
		a.mu.Unlock()
		return
	}
	active := map[string]bool{}
	if a.adminFilters != nil {
		for kk, v := range a.adminFilters {
			active[kk] = v
		}
	}
	a.adminLoad = true
	a.mu.Unlock()
	a.invalidate()
	a.adminLogFetch(k.AccountID, k.ChatID, maxID, a.wid.adminSearchEd.Text(), active)
}

// adminLogFetch runs one page fetch and merges the result.
func (a *App) adminLogFetch(accountID, chatID string, maxID int64, query string, filters map[string]bool) {
	go func() {
		events, err := a.eng.GetAdminLogEvents(accountID, chatID, 50, query, maxID, filters, nil)
		a.mu.Lock()
		if !a.adminPanel {
			a.mu.Unlock()
			return
		}
		if err != nil {
			a.adminLoad = false
			a.adminErr = err.Error()
			a.mu.Unlock()
			a.invalidate()
			a.setToast("Recent actions: " + err.Error())
			return
		}
		a.adminErr = ""
		if maxID > 0 {
			a.adminEvents = append(a.adminEvents, events...)
		} else {
			a.adminEvents = events
		}
		if len(events) == 0 {
			a.adminLoadedAll = true
		}
		a.adminLoad = false
		a.mu.Unlock()
		a.invalidate()
	}()
}

// layoutAdminPanel: the Recent Actions surface (chat pane replacement,
// like the scheduled-messages panel).
func (a *App) layoutAdminPanel(gtx layout.Context, f frame, chat *engine.ChatInfo) layout.Dimensions {
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, adminPanelTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeAdminPanel()
		}
	}
	if a.wid.adminPanelBack.Clicked(gtx) {
		a.closeAdminPanel()
	}
	if a.wid.adminSearchBtn.Clicked(gtx) {
		a.adminLogSearch()
	}
	growClickables(&a.wid.adminFilterBtns, len(adminFilterDefs))
	for i := range adminFilterDefs {
		if a.wid.adminFilterBtns[i].Clicked(gtx) {
			a.adminToggleFilterNow(adminFilterDefs[i].id)
		}
	}
	if a.wid.adminMoreBtn.Clicked(gtx) {
		a.adminLoadMore()
	}

	title := "Recent actions"
	if chat != nil {
		title = "Recent actions · " + chat.Title
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		// Header.
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(8), Right: unit.Dp(12)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.IconButton(&a.wid.adminPanelBack, iconNavigationBack, "Back to chat")
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
		// Search + filters.
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						ed := a.ui.Editor(&a.wid.adminSearchEd, "Search admin actions")
						ed.Editor.SingleLine = true
						return ed.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.ui.IconButton(&a.wid.adminSearchBtn, iconActionSearch, "Search").Layout(gtx)
						})
					}),
				)
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.adminFilterStrip(gtx, f)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.ui.Divider(gtx)
		}),
		// List.
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			if f.adminLoad && len(f.adminEvents) == 0 {
				return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(14), "Loading recent actions…")
					return lbl.Layout(gtx)
				})
			}
			if f.adminErr != "" && len(f.adminEvents) == 0 {
				return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(13), "Could not load: "+f.adminErr)
					lbl.MaxLines = 3
					return lbl.Layout(gtx)
				})
			}
			if len(f.adminEvents) == 0 {
				return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.H3("No recent actions")
							lbl.Color = a.ui.p.TextFaint
							return lbl.Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(13), "Admin activity in this chat will appear here.")
							lbl.Color = a.ui.p.TextFaint
							return lbl.Layout(gtx)
						}),
					)
				})
			}
			return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				n := len(f.adminEvents)
				if !f.adminLoadedAll && !f.adminLoad {
					n++ // the load-more row rides the list
				}
				return a.wid.adminPanelList.Layout(gtx, n, func(gtx layout.Context, i int) layout.Dimensions {
					if i == len(f.adminEvents) {
						return a.adminMoreRow(gtx)
					}
					return a.adminEventRow(gtx, f.adminEvents[i])
				})
			})
		}),
	)
}

// adminFilterStrip: horizontal chip row (active chips tinted).
func (a *App) adminFilterStrip(gtx layout.Context, f frame) layout.Dimensions {
	growClickables(&a.wid.adminFilterBtns, len(adminFilterDefs))
	return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6), Left: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Min = image.Point{}
		return a.wid.adminFilterList.Layout(gtx, len(adminFilterDefs), func(gtx layout.Context, i int) layout.Dimensions {
			def := adminFilterDefs[i]
			active := f.adminFilters != nil && f.adminFilters[def.id]
			bg := a.ui.p.SurfaceHi
			col := a.ui.p.Text
			if active {
				bg = a.ui.p.Accent
				col = a.ui.p.Background
			}
			return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				btn := material.Button(a.ui.Theme, &a.wid.adminFilterBtns[i], def.label)
				btn.Background = bg
				btn.Color = col
				btn.CornerRadius = 14
				btn.Inset = layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4), Left: unit.Dp(10), Right: unit.Dp(10)}
				btn.TextSize = unit.Sp(12)
				return btn.Layout(gtx)
			})
		})
	})
}

// adminMoreRow: the load-more row.
func (a *App) adminMoreRow(gtx layout.Context) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			if a.wid.adminMoreBtn.Clicked(gtx) {
				a.adminLoadMore()
			}
			btn := material.Button(a.ui.Theme, &a.wid.adminMoreBtn, "Load more")
			btn.Background = a.ui.p.SurfaceHi
			btn.Color = a.ui.p.Text
			btn.CornerRadius = 10
			return btn.Layout(gtx)
		})
	})
}

// adminEventRow: one event card.
func (a *App) adminEventRow(gtx layout.Context, e cores.AdminLogEvent) layout.Dimensions {
	when := ""
	if e.Date > 0 {
		when = time.Unix(int64(e.Date), 0).Format("Jan 2, 15:04")
	}
	var body []layout.FlexChild
	if sub := adminEventSub(e); sub != "" {
		body = append(body, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Label(unit.Sp(13), sub)
			lbl.MaxLines = 2
			return lbl.Layout(gtx)
		}))
	}
	if chgs := adminEventChanges(e); len(chgs) > 0 {
		body = append(body, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					flexForEach(len(chgs), func(gtx layout.Context, i int) layout.Dimensions {
						prefix := "New"
						if len(chgs) == 2 && i == 0 {
							prefix = "Old"
						}
						lbl := a.ui.Dim(unit.Sp(12), prefix+": "+chgs[i])
						lbl.MaxLines = 2
						return lbl.Layout(gtx)
					})...)
			})
		}))
	}
	if adminEventHasMessage(e) {
		body = append(body, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.adminMsgPreview(gtx, e)
		}))
	}
	return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4), Left: unit.Dp(8), Right: unit.Dp(8)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return roundedFill(gtx, a.ui.p.SurfaceHi, 12, func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return a.ui.Avatar(gtx, adminEventHeadline(e), unit.Dp(36), dotNone)
							})
						}),
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							head := []layout.FlexChild{
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Baseline}.Layout(gtx,
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											lbl := a.ui.Label(unit.Sp(13), adminEventHeadline(e))
											lbl.Color = a.ui.p.Accent
											lbl.MaxLines = 1
											return lbl.Layout(gtx)
										}),
									)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Label(unit.Sp(14), adminEventActionText(e))
									lbl.MaxLines = 2
									return lbl.Layout(gtx)
								}),
							}
							body = append(head, body...)
							return layout.Flex{Axis: layout.Vertical}.Layout(gtx, body...)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							if when == "" {
								return layout.Dimensions{}
							}
							lbl := a.ui.Dim(unit.Sp(11), when)
							lbl.MaxLines = 1
							return layout.Inset{Left: unit.Dp(8), Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return lbl.Layout(gtx)
							})
						}),
					)
				})
			})
		})
}

// adminMsgPreview: the inline message bubble for message events.
func (a *App) adminMsgPreview(gtx layout.Context, e cores.AdminLogEvent) layout.Dimensions {
	_, thumb := adminEventMedia(e)
	return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Background, 10, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if thumb == "" {
							return layout.Dimensions{}
						}
						return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.mediaThumb(gtx, thumb, unit.Dp(44))
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						text := e.MsgText
						if text == "" {
							text = "Message " + itoa64(int64(e.MessageID))
						}
						lbl := a.ui.Label(unit.Sp(13), text)
						lbl.MaxLines = 3
						return lbl.Layout(gtx)
					}),
				)
			})
		})
	})
}

// UserIDstr / UserIDstr2: small formatting helpers (kept local so the
// pure tests can pin them).
func userIDStr(id int64) string {
	if id == 0 {
		return ""
	}
	return itoa64(id)
}

// itoa64 formats an int64.
func itoa64(v int64) string {
	if v == 0 {
		return "0"
	}
	neg := v < 0
	if neg {
		v = -v
	}
	var buf [24]byte
	i := len(buf)
	for v > 0 {
		i--
		buf[i] = byte('0' + v%10)
		v /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}
