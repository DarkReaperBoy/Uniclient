package gui

import (
	"image"
	"image/color"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

var (
	drawerScrimTag   = new(struct{})
	drawerKeyTag     = new(struct{})
	drawerAcctRows   []widget.Clickable
	drawerAcctAll    widget.Clickable
	drawerAcctAdd    widget.Clickable
	drawerAcctHeader widget.Clickable
	drawerContacts   widget.Clickable
	drawerCalls      widget.Clickable
	drawerSettings   widget.Clickable
	drawerNewGroup   widget.Clickable
	drawerNewChan    widget.Clickable
	drawerGhostCfg   widget.Clickable
	drawerSavedBtn   widget.Clickable
	drawerNight      = new(widget.Bool)
	drawerGhost      = new(widget.Bool)
	drawerStreamer   = new(widget.Bool)
	drawerLRead      = new(widget.Bool)
	drawerSRead      = new(widget.Bool)
	drawerNightSync  bool
	drawerGhostSync  bool
	drawerStreamSync bool
	drawerReadSync   bool
	drawerList       widget.List
)

func init() {
	drawerList.Axis = layout.Vertical
}

func ghostAllOn(c cfgSnapshot) bool {
	return c.SendReadReceipts && c.SendUploadProgress && c.SendReadStories &&
		c.SendOnlinePackets && c.SendOfflineAfterOnline && c.MarkReadAfterAction &&
		c.UseScheduledMessages && c.SendWithoutSound
}

func (a *App) openDrawer() {
	a.mu.Lock()
	a.drawerOpen = true
	a.chatMenu = nil
	a.headerMenu = nil
	a.mu.Unlock()
	accountMenuOpen = false
	drawerNightSync = false
	drawerGhostSync = false
	drawerStreamSync = false
	drawerReadSync = false
	a.invalidate()
}

func (a *App) closeDrawer() {
	a.mu.Lock()
	if !a.drawerOpen {
		a.mu.Unlock()
		return
	}
	a.drawerOpen = false
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) setGhostAll(v bool) {
	go func() {
		for _, field := range []string{
			"send_read_receipts", "send_upload_progress", "send_read_stories",
			"send_online_packets", "send_offline_after_online",
			"mark_read_after_action", "use_scheduled_messages", "send_without_sound",
		} {
			c := configFieldChanges(field, v)
			if c == nil {
				continue
			}
			if err := a.eng.UpdateConfigFromBridge(c); err != nil {
				a.setToast("Ghost mode: " + err.Error())
				return
			}
		}
		if v {
			a.setToast("Ghost mode on")
		} else {
			a.setToast("Ghost mode off")
		}
		a.refreshConfig()
	}()
}

func (a *App) layoutDrawer(gtx layout.Context, f frame) layout.Dimensions {
	gtx.Execute(key.FocusCmd{Tag: nil})
	{
		stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
		event.Op(gtx.Ops, drawerKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeDrawer()
		}
	}

	paint.FillShape(gtx.Ops, color.NRGBA{R: 0, G: 0, B: 0, A: 0x66},
		clip.Rect{Max: gtx.Constraints.Max}.Op())
	{
		stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
		event.Op(gtx.Ops, drawerScrimTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(pointer.Filter{Target: drawerScrimTag, Kinds: pointer.Press})
		if !ok {
			break
		}
		if pe, is := ev.(pointer.Event); is && pe.Kind == pointer.Press {
			a.closeDrawer()
		}
	}

	w := gtx.Dp(unit.Dp(300))
	if w > gtx.Constraints.Max.X {
		w = gtx.Constraints.Max.X
	}
	panelStack := clip.Rect{Max: image.Pt(w, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
	paint.Fill(gtx.Ops, a.ui.p.Surface)
	inner := gtx
	inner.Constraints = layout.Constraints{
		Min: image.Pt(w, gtx.Constraints.Min.Y),
		Max: image.Pt(w, gtx.Constraints.Max.Y),
	}
	a.drawerPanel(inner, f)
	panelStack.Pop()

	return layout.Dimensions{Size: gtx.Constraints.Max}
}

func (a *App) drawerPanel(gtx layout.Context, f frame) layout.Dimensions {
	growClickables(&drawerAcctRows, len(f.accounts))

	if drawerAcctHeader.Clicked(gtx) {
		a.closeDrawer()
		a.openSettings(setSectionMain)
	}
	if drawerAcctAll.Clicked(gtx) {
		a.mu.Lock()
		a.acctFilter = ""
		a.folder = 0
		a.mu.Unlock()
		a.closeDrawer()
	}
	for i, acc := range f.accounts {
		i, acc := i, acc
		if drawerAcctRows[i].Clicked(gtx) {
			a.mu.Lock()
			if a.acctFilter == acc.ID {
				a.acctFilter = ""
			} else {
				a.acctFilter = acc.ID
			}
			a.folder = 0
			scope := a.acctFilter
			a.mu.Unlock()
			a.refreshFolders(scope)
			a.closeDrawer()
		}
	}
	if drawerAcctAdd.Clicked(gtx) {
		a.closeDrawer()
		a.mu.Lock()
		a.showPicker = true
		a.mu.Unlock()
		a.invalidate()
	}
	if drawerContacts.Clicked(gtx) {
		acc := a.acctFilterLocked()
		if acc == "" {
			acc = currentAccount(f).ID
		}
		a.closeDrawer()
		a.openContacts(acc)
	}
	if drawerCalls.Clicked(gtx) {
		acc := a.acctFilterLocked()
		if acc == "" {
			acc = currentAccount(f).ID
		}
		a.closeDrawer()
		a.openCallsBox(acc)
	}
	if drawerSettings.Clicked(gtx) {
		a.closeDrawer()
		a.openSettings(setSectionMain)
	}
	if drawerNewGroup.Clicked(gtx) {
		acc := a.acctFilterLocked()
		if acc == "" {
			acc = currentAccount(f).ID
		}
		a.closeDrawer()
		a.openNewChat(0, acc)
	}
	if drawerNewChan.Clicked(gtx) {
		acc := a.acctFilterLocked()
		if acc == "" {
			acc = currentAccount(f).ID
		}
		a.closeDrawer()
		a.openNewChat(1, acc)
	}
	if drawerGhostCfg.Clicked(gtx) {
		a.closeDrawer()
		a.openSettings(setSectionAyu)
	}
	if drawerSavedBtn.Clicked(gtx) {
		a.closeDrawer()
		if id := savedTargetAccount(f); id != "" {
			a.openSavedMessages(id)
		} else {
			a.setToast("No saved-messages capable account")
		}
	}

	current := currentAccount(f)
	if !drawerNightSync {
		drawerNight.Value = f.cfg.Theme == "light"
		drawerNightSync = true
	}
	if !drawerGhostSync {
		drawerGhost.Value = ghostAllOn(f.cfg)
		drawerGhostSync = true
	}
	if !drawerReadSync {
		drawerLRead.Value = f.cfg.LocalReadMark
		drawerSRead.Value = f.cfg.SendReadReceipts
		drawerReadSync = true
	}
	if !drawerStreamSync {
		drawerStreamer.Value = f.cfg.Streamer
		drawerStreamSync = true
	}
	prevNight, prevGhost, prevStreamer := drawerNight.Value, drawerGhost.Value, drawerStreamer.Value
	prevLRead, prevSRead := drawerLRead.Value, drawerSRead.Value

	children := a.drawerChildren(f, current)
	dims := layout.UniformInset(unit.Dp(4)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return drawerList.Layout(gtx, len(children), func(gtx layout.Context, idx int) layout.Dimensions {
			return children[idx](gtx)
		})
	})

	if drawerNight.Value != prevNight {
		a.applyTheme(drawerNight.Value)
	}
	if drawerGhost.Value != prevGhost {
		a.setGhostAll(drawerGhost.Value)
	}
	if drawerLRead.Value != prevLRead {
		a.applyConfigBool("local_read_mark", drawerLRead.Value)
		if drawerLRead.Value {
			a.setToast("Messages marked read locally")
		} else {
			a.setToast("Chats stay unread until you mark them")
		}
	}
	if drawerSRead.Value != prevSRead {
		a.applyConfigBool("send_read_receipts", drawerSRead.Value)
		if drawerSRead.Value {
			a.setToast("Read receipts sent")
		} else {
			a.setToast("Read receipts hidden (ghost)")
		}
	}
	if drawerStreamer.Value != prevStreamer {
		a.applyStreamer(drawerStreamer.Value)
	}
	return dims
}

func (a *App) drawerChildren(f frame, current engine.AccountInfo) []func(gtx layout.Context) layout.Dimensions {
	rows := make([]func(gtx layout.Context) layout.Dimensions, 0, 20)

	rows = append(rows, func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(10), Left: unit.Dp(12), Right: unit.Dp(12), Bottom: unit.Dp(6)}.Layout(gtx,
			func(gtx layout.Context) layout.Dimensions {
				return material.ButtonLayout(a.ui.Theme, &drawerAcctHeader).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return a.streamerAccountAvatar(gtx, f, current, unit.Dp(42), connDotFor(current))
								})
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										lbl := a.ui.H3(accountName(current))
										if f.cfg.Streamer {
											return a.masked(gtx, lbl.Layout)
										}
										return lbl.Layout(gtx)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										lbl := a.ui.Dim(unit.Sp(12), accountSubtitle(current, f))
										return lbl.Layout(gtx)
									}),
								)
							}),
						)
					})
				})
			})
	})

	for i, acc := range f.accounts {
		i, acc := i, acc
		if current.ID != "" && acc.ID == current.ID {
			continue
		}
		rows = append(rows, func(gtx layout.Context) layout.Dimensions {
			return drawerAccountRow(gtx, a.ui, &drawerAcctRows[i], acc, f.acctFilter == acc.ID, accountUnread(f.chats, acc.ID))
		})
	}
	if len(f.accounts) > 1 || current.ID == "" {
		rows = append(rows, func(gtx layout.Context) layout.Dimensions {
			return drawerAccountRowLabel(gtx, a.ui, &drawerAcctAll, "All accounts", f.acctFilter == "")
		})
	}
	rows = append(rows, func(gtx layout.Context) layout.Dimensions {
		return drawerAccountRowLabel(gtx, a.ui, &drawerAcctAdd, "Add account", false)
	})

	if !drawerRowHidden(f.cfg.DrawerHidden, drawerItemSaved) {
		rows = append(rows, a.drawerIconRow(&drawerSavedBtn, iconActionBackup, "Saved messages"))
	}

	rows = append(rows, a.drawerDividerRow())

	if !drawerRowHidden(f.cfg.DrawerHidden, drawerItemContacts) {
		rows = append(rows, a.drawerIconRow(&drawerContacts, iconCommunicationContacts, "Contacts"))
	}
	if !drawerRowHidden(f.cfg.DrawerHidden, drawerItemCalls) {
		rows = append(rows, a.drawerIconRow(&drawerCalls, iconCommunicationCall, "Calls"))
	}
	rows = append(rows, func(gtx layout.Context) layout.Dimensions {
		return a.drawerSwitchRow(gtx, iconImagePalette, "Night mode", drawerNight)
	})
	rows = append(rows, func(gtx layout.Context) layout.Dimensions {
		return a.drawerSwitchRow(gtx, iconAVPlayCircle, "Streamer mode", drawerStreamer)
	})

	rows = append(rows, a.drawerDividerRow())

	if !drawerRowHidden(f.cfg.DrawerHidden, drawerItemGhost) {
		rows = append(rows, a.drawerSectionLabel("AyuGram"))
		rows = append(rows, func(gtx layout.Context) layout.Dimensions {
			return a.drawerSwitchRow(gtx, iconActionDone, "Local read (LRead)", drawerLRead)
		})
		rows = append(rows, func(gtx layout.Context) layout.Dimensions {
			return a.drawerSwitchRow(gtx, iconCommunicationChat, "Send read (SRead)", drawerSRead)
		})
		rows = append(rows, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					return a.drawerSwitchRow(gtx, iconActionGhost, "Ghost mode", drawerGhost)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.IconButton(&drawerGhostCfg, iconNavChevronRight, "Ghost preferences")
					btn.Color = a.ui.p.TextDim
					btn.Size = unit.Dp(16)
					return btn.Layout(gtx)
				}),
			)
		})
	}

	rows = append(rows, a.drawerDividerRow())

	if !drawerRowHidden(f.cfg.DrawerHidden, drawerItemNewGroup) {
		rows = append(rows, a.drawerIconRowAccent(&drawerNewGroup, iconSocialGroup, "New group"))
	}
	if !drawerRowHidden(f.cfg.DrawerHidden, drawerItemNewChan) {
		rows = append(rows, a.drawerIconRowAccent(&drawerNewChan, iconCommunicationChat, "New channel"))
	}

	rows = append(rows, a.drawerDividerRow())

	rows = append(rows, a.drawerIconRow(&drawerSettings, iconActionSettings, "Settings"))

	return rows
}

func (a *App) drawerDividerRow() func(gtx layout.Context) layout.Dimensions {
	return func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx,
			func(gtx layout.Context) layout.Dimensions {
				return a.ui.Divider(gtx)
			})
	}
}

func (a *App) drawerSectionLabel(txt string) func(gtx layout.Context) layout.Dimensions {
	return func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(4), Left: unit.Dp(16), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Label(unit.Sp(12), txt)
			lbl.Color = a.ui.p.Accent
			return lbl.Layout(gtx)
		})
	}
}

func (a *App) drawerIconRow(btn *widget.Clickable, icon *widget.Icon, label string) func(gtx layout.Context) layout.Dimensions {
	return func(gtx layout.Context) layout.Dimensions {
		return drawerMenuRow(gtx, a.ui, btn, icon, label, a.ui.p.Text)
	}
}

func (a *App) drawerIconRowAccent(btn *widget.Clickable, icon *widget.Icon, label string) func(gtx layout.Context) layout.Dimensions {
	return func(gtx layout.Context) layout.Dimensions {
		return drawerMenuRow(gtx, a.ui, btn, icon, label, a.ui.p.Accent)
	}
}

func (a *App) drawerSwitchRow(gtx layout.Context, icon *widget.Icon, label string, sw *widget.Bool) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(8), Right: unit.Dp(8)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return drawerIcon(gtx, icon, a.ui.p.TextDim)
					})
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(14), label)
					return lbl.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					tg := material.Switch(a.ui.Theme, sw, "")
					tg.Color.Enabled = a.ui.p.Accent
					tg.Color.Disabled = a.ui.p.SurfaceHi
					tg.Color.Track = a.ui.p.SurfaceHi
					return tg.Layout(gtx)
				}),
			)
		})
}

func drawerMenuRow(gtx layout.Context, u *UI, btn *widget.Clickable, icon *widget.Icon, label string, iconColor color.NRGBA) layout.Dimensions {
	return layout.Inset{Left: unit.Dp(8), Right: unit.Dp(8), Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return material.ButtonLayout(u.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return drawerIcon(gtx, icon, iconColor)
							})
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := u.Label(unit.Sp(14), label)
							return lbl.Layout(gtx)
						}),
					)
				})
			})
		})
}

func drawerIcon(gtx layout.Context, icon *widget.Icon, c color.NRGBA) layout.Dimensions {
	if icon == nil {
		return layout.Dimensions{}
	}
	return icon.Layout(gtx, c)
}

func drawerAccountRow(gtx layout.Context, u *UI, btn *widget.Clickable, acc engine.AccountInfo, active bool, unread int) layout.Dimensions {
	return layout.Inset{Left: unit.Dp(8), Right: unit.Dp(8), Top: unit.Dp(1), Bottom: unit.Dp(1)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return material.ButtonLayout(u.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return u.Avatar(gtx, accountName(acc), unit.Dp(26), connDotFor(acc))
							})
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := u.Label(unit.Sp(13), accountName(acc))
							if active {
								lbl.Color = u.p.Accent
							}
							return lbl.Layout(gtx)
						}),
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							return layout.Dimensions{}
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							if unread <= 0 {
								return layout.Dimensions{}
							}
							return unreadBadge(gtx, u, unread, false)
						}),
					)
				})
			})
		})
}

func drawerAccountRowLabel(gtx layout.Context, u *UI, btn *widget.Clickable, label string, active bool) layout.Dimensions {
	return layout.Inset{Left: unit.Dp(8), Right: unit.Dp(8), Top: unit.Dp(1), Bottom: unit.Dp(1)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return material.ButtonLayout(u.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := u.Label(unit.Sp(13), label)
					if active {
						lbl.Color = u.p.Accent
					}
					return lbl.Layout(gtx)
				})
			})
		})
}

const (
	drawerItemSaved    = "saved"
	drawerItemContacts = "contacts"
	drawerItemCalls    = "calls"
	drawerItemGhost    = "ghost"
	drawerItemNewGroup = "new_group"
	drawerItemNewChan  = "new_channel"
)

func drawerRowHidden(hidden []string, id string) bool {
	for _, h := range hidden {
		if h == id {
			return true
		}
	}
	return false
}

func drawerCustomItems() []struct{ id, label string } {
	return []struct{ id, label string }{
		{drawerItemSaved, "Saved messages"},
		{drawerItemContacts, "Contacts"},
		{drawerItemCalls, "Calls"},
		{drawerItemGhost, "Ghost mode"},
		{drawerItemNewGroup, "New group"},
		{drawerItemNewChan, "New channel"},
	}
}
