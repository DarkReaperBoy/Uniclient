package gui

import (
	"image"
	"strconv"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"

	"uniclient/cores"
	"uniclient/engine"
)

// Reactions list (AyuGram parity, matrix "Reactions/views list"): the
// message context menu gains "Who reacted" for messages with reactions —
// a dialog with one tab per reaction emoji, listing the users who chose
// it (engine GetMessageReactorsList, per-emoji filter + offset paging).

// reactorsState: open "who reacted" dialog (nil when closed).
type reactorsState struct {
	msg    engine.CachedMessage
	emojis []string         // tab list (the message's reaction emojis)
	sel    int              // selected emoji index
	users  []cores.Reaction // reactors for the selected emoji
	offset string           // next-page cursor ("" = exhausted)
	busy   bool
}

var (
	reactorsKeyTag = new(struct{})
)

// reactorTabs (pure, testable): the emoji tabs for a message's reactions,
// in strip order, custom-emoji placeholders skipped.
func reactorTabs(m *engine.CachedMessage) []string {
	var tabs []string
	for _, r := range m.Reactions {
		if r.Emoji != "" {
			tabs = append(tabs, r.Emoji)
		}
	}
	return tabs
}

// reactorRowName (pure, testable): display name for one reactor row.
func reactorRowName(r cores.Reaction) string {
	if r.PeerName != "" {
		return r.PeerName
	}
	if r.PeerID != "" {
		return "user " + r.PeerID
	}
	return "someone"
}

// openReactors shows the who-reacted dialog for a message (fetches the
// selected emoji's reactors; the first emoji when none is passed).
func (a *App) openReactors(m *engine.CachedMessage, emoji string) {
	if m == nil || len(m.Reactions) == 0 {
		return
	}
	tabs := reactorTabs(m)
	if len(tabs) == 0 {
		return
	}
	sel := 0
	if emoji != "" {
		for i, e := range tabs {
			if e == emoji {
				sel = i
				break
			}
		}
	}
	msg := *m
	a.mu.Lock()
	a.reactors = &reactorsState{msg: msg, emojis: tabs, sel: sel}
	a.mu.Unlock()
	a.invalidate()
	a.loadReactors("")
}

// closeReactors dismisses the dialog.
func (a *App) closeReactors() {
	a.mu.Lock()
	a.reactors = nil
	a.mu.Unlock()
	a.invalidate()
}

// loadReactors fetches one page of reactors for the selected emoji
// (appending when paging with an offset).
func (a *App) loadReactors(offset string) {
	a.mu.Lock()
	d := a.reactors
	if d == nil || d.busy {
		a.mu.Unlock()
		return
	}
	if offset == "" {
		d.users = nil
	}
	d.busy = true
	acc, chat := d.msg.AccountID, d.msg.ChatID
	msgID := d.msg.MsgID
	filter := d.emojis[d.sel]
	a.mu.Unlock()
	a.invalidate()

	go func() {
		id, err := strconv.Atoi(msgID)
		if err != nil {
			a.setToast("Who reacted: bad message id")
			a.mu.Lock()
			if a.reactors != nil {
				a.reactors.busy = false
			}
			a.mu.Unlock()
			return
		}
		users, next, err := a.eng.GetMessageReactorsList(acc, chat, id, 100, offset, filter)
		a.mu.Lock()
		if a.reactors == nil {
			a.mu.Unlock()
			return
		}
		a.reactors.busy = false
		if err == nil {
			a.reactors.users = append(a.reactors.users, users...)
			a.reactors.offset = next
		}
		a.mu.Unlock()
		if err != nil {
			a.setToast("Who reacted: " + err.Error())
		}
		a.invalidate()
	}()
}

// layoutReactorsDialog renders the who-reacted card over the chat pane.
func (a *App) layoutReactorsDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.reactors
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, reactorsKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeReactors()
		}
	}
	if a.wid.reactorsClose.Clicked(gtx) {
		a.closeReactors()
	}
	growClickables(&a.wid.reactorsTabs, len(d.emojis))
	for i := range a.wid.reactorsTabs {
		if a.wid.reactorsTabs[i].Clicked(gtx) {
			a.mu.Lock()
			if a.reactors != nil && a.reactors.sel != i {
				a.reactors.sel = i
				a.mu.Unlock()
				a.loadReactors("")
			} else {
				a.mu.Unlock()
			}
		}
	}
	if a.wid.reactorsMoreBtn.Clicked(gtx) && d.offset != "" {
		a.loadReactors(d.offset)
	}

	paintScrimRect(gtx)

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(360))
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(480))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(14)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					// Header + close.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.H3("Who reacted")
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								btn := a.ui.IconButton(&a.wid.reactorsClose, iconContentClear, "Close")
								btn.Color = a.ui.p.TextDim
								return btn.Layout(gtx)
							}),
						)
					}),
					// Emoji tabs.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, tabRowChildren(a, d)...)
						})
					}),
					// Reactor rows.
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						if d.busy && len(d.users) == 0 {
							return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return a.loadingNote(gtx)
							})
						}
						if len(d.users) == 0 {
							return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(13), "Nobody yet")
								return lbl.Layout(gtx)
							})
						}
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx, reactorRowsChildren(a, d)...)
					}),
					// Load more.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if d.offset == "" || d.busy {
							return layout.Dimensions{}
						}
						return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.TextButton(&a.wid.reactorsMoreBtn, "Load more")
							btn.Color = a.ui.p.Accent
							return btn.Layout(gtx)
						})
					}),
				)
			})
		})
	})
}

// tabRowChildren builds the emoji tab chips (selected highlighted).
func tabRowChildren(a *App, d *reactorsState) []layout.FlexChild {
	children := make([]layout.FlexChild, 0, len(d.emojis))
	for i, e := range d.emojis {
		i, e := i, e
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Right: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				bg := a.ui.p.SurfaceHi
				if i == d.sel {
					bg = a.ui.p.AccentDim
				}
				return roundedFill(gtx, bg, 10, func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3), Left: unit.Dp(8), Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(14), e)
						if i == d.sel {
							lbl.Color = a.ui.p.Text
						}
						return lbl.Layout(gtx)
					})
				})
			})
		}))
	}
	return children
}

// reactorRowsChildren builds the user rows ("emoji + name").
func reactorRowsChildren(a *App, d *reactorsState) []layout.FlexChild {
	children := make([]layout.FlexChild, 0, len(d.users))
	for _, u := range d.users {
		u := u
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(14), u.Emoji)
							return lbl.Layout(gtx)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(14), reactorRowName(u))
						lbl.MaxLines = 1
						return lbl.Layout(gtx)
					}),
				)
			})
		}))
	}
	return children
}
