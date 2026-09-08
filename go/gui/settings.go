package gui

import (
	"image"

	"gioui.org/font"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Settings view — the AyuGram settings shell (research/ayugram_parity.md §8):
// a left rail of sections with content pages, every toggle and row backed by
// a real engine call (config, cache accounting, blocked users, sessions,
// ghost flags — §1.10: no dead UI).

// settingsSections is the rail, in AyuGram's order.
var settingsSections = []string{
	"Main", "Notifications", "Privacy & Security", "Data & Storage",
	"Appearance", "Ayu", "About",
}

const (
	setSectionMain = iota
	setSectionNotifications
	setSectionPrivacy
	setSectionData
	setSectionAppearance
	setSectionAyu
	setSectionAbout
)

// sectionIcons maps each rail section to its icon.
var sectionIcons = []*widget.Icon{
	iconActionAccount,
	iconSocialNotif,
	iconActionLock,
	iconActionBackup,
	iconImagePalette,
	iconActionGhost,
	iconActionInfo,
}

// cacheTagLabels mirrors the engine's Local Storage tags (media.go
// mediaTypesForTag) in display order.
var cacheTagLabels = [6]string{"Images", "Stickers", "Voice messages", "Video messages", "Animations", "Media cache"}

func cacheTagLabel(i int) string {
	if i < 0 || i >= len(cacheTagLabels) {
		return ""
	}
	return cacheTagLabels[i]
}

// themeName maps a light/dark boolean to the config string.
func themeName(light bool) string {
	if light {
		return "light"
	}
	return "dark"
}

// configFieldChanges builds the partial engine config update for one field.
// nil for unknown fields.
func configFieldChanges(field string, v bool) *engine.ConfigChanges {
	b := v
	c := &engine.ConfigChanges{}
	switch field {
	case "send_read_receipts":
		c.SendReadReceipts = &b
	case "send_typing":
		c.SendTyping = &b
	case "send_upload_progress":
		c.SendUploadProgress = &b
	case "send_read_stories":
		c.SendReadStories = &b
	case "send_online_packets":
		c.SendOnlinePackets = &b
	case "send_offline_after_online":
		c.SendOfflineAfterOnline = &b
	case "mark_read_after_action":
		c.MarkReadAfterAction = &b
	case "use_scheduled_messages":
		c.UseScheduledMessages = &b
	case "send_without_sound":
		c.SendWithoutSound = &b
	case "notify_dms":
		c.NotifyDMs = &b
	case "notify_groups":
		c.NotifyGroups = &b
	case "notify_mentions_only":
		c.NotifyMentionsOnly = &b
	default:
		return nil
	}
	return c
}

// ghostFlagSet sets one flag on a GhostFlags by config field name; false for
// unknown fields.
func ghostFlagSet(g *engine.GhostFlags, field string, v bool) bool {
	switch field {
	case "send_read_receipts":
		g.SendReadReceipts = v
	case "send_upload_progress":
		g.SendUploadProgress = v
	case "send_read_stories":
		g.SendReadStories = v
	case "send_online_packets":
		g.SendOnlinePackets = v
	case "send_offline_after_online":
		g.SendOfflineAfterOnline = v
	case "mark_read_after_action":
		g.MarkReadAfterAction = v
	case "use_scheduled_messages":
		g.UseScheduledMessages = v
	case "send_without_sound":
		g.SendWithoutSound = v
	default:
		return false
	}
	return true
}

// ── widget pools (frame-loop only) ────────────────────────────────────────

var (
	settingsRailBtns   []widget.Clickable
	settingsSwitches   = map[string]*widget.Bool{}
	settingsSynced     = map[string]bool{}
	settingsRemoveBtns []widget.Clickable
	settingsAddBtn     widget.Clickable
	settingsBackBtn    widget.Clickable
	clearTagBtns       []widget.Clickable
	clearAllBtn        widget.Clickable
	ghostResetBtn      widget.Clickable
	ghostAcctChips     []widget.Clickable
	settingsScroll     widget.List
)

func init() {
	settingsScroll.Axis = layout.Vertical
}

func settingsSwitch(key string) *widget.Bool {
	if s, ok := settingsSwitches[key]; ok {
		return s
	}
	if len(settingsSwitches) > 128 {
		settingsSwitches = make(map[string]*widget.Bool)
		settingsSynced = make(map[string]bool)
	}
	s := new(widget.Bool)
	settingsSwitches[key] = s
	return s
}

// ── shell ─────────────────────────────────────────────────────────────────

// layoutSettings: header (back + title), then rail + content (rail collapses
// to a horizontal chip row on narrow layouts — AyuGram mobile settings).
func (a *App) layoutSettings(gtx layout.Context, f frame, narrow bool) layout.Dimensions {
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.settingsHeader(gtx, f)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.ui.Divider(gtx)
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			if narrow {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.settingsRail(gtx, f, true)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions { return a.ui.Divider(gtx) }),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return a.settingsPage(gtx, f)
					}),
				)
			}
			return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					gtx.Constraints.Max.X = gtx.Dp(unit.Dp(190))
					gtx.Constraints.Min.X = gtx.Dp(unit.Dp(190))
					return a.settingsRail(gtx, f, false)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions { return a.ui.DividerV(gtx) }),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					return a.settingsPage(gtx, f)
				}),
			)
		}),
	)
}

func (a *App) settingsHeader(gtx layout.Context, f frame) layout.Dimensions {
	if settingsBackBtn.Clicked(gtx) {
		a.closeSettings()
	}
	return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(8), Right: unit.Dp(12)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.IconButton(&settingsBackBtn, iconNavigationBack, "Back")
					btn.Color = a.ui.p.TextDim
					return btn.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return a.ui.H2("Settings").Layout(gtx)
					})
				}),
			)
		},
	)
}

// settingsRail renders the section list: vertical on desktop, horizontal chip
// row on narrow layouts.
func (a *App) settingsRail(gtx layout.Context, f frame, narrow bool) layout.Dimensions {
	growClickables(&settingsRailBtns, len(settingsSections))
	axis := layout.Vertical
	if narrow {
		axis = layout.Horizontal
	}
	flex := layout.Flex{Axis: axis}
	children := make([]layout.FlexChild, 0, len(settingsSections))
	for i, title := range settingsSections {
		i, title := i, title
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			btn := &settingsRailBtns[i]
			if btn.Clicked(gtx) {
				a.mu.Lock()
				a.settingsSect = i
				a.mu.Unlock()
				a.invalidate()
			}
			active := f.settingsSect == i
			bg := a.ui.p.Surface
			if active {
				bg = a.ui.p.SurfaceHi
			}
			ic := sectionIcons[i]
			in := layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4), Left: unit.Dp(12), Right: unit.Dp(12)}
			if !narrow {
				in = layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6), Left: unit.Dp(14), Right: unit.Dp(10)}
			}
			return in.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return roundedFill(gtx, bg, 8, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							if ic == nil {
								return layout.Dimensions{}
							}
							gtx.Constraints.Min.X = gtx.Dp(unit.Dp(20))
							col := a.ui.p.TextDim
							if active {
								col = a.ui.p.Accent
							}
							return ic.Layout(gtx, col)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), title)
								if active {
									lbl.Color = a.ui.p.Text
								} else {
									lbl.Color = a.ui.p.TextDim
								}
								return lbl.Layout(gtx)
							})
						}),
					)
				})
			})
		}))
	}
	return flex.Layout(gtx, children...)
}

// settingsPage lays the active section's content in a scrolling list.
func (a *App) settingsPage(gtx layout.Context, f frame) layout.Dimensions {
	list := material.List(a.ui.Theme, &settingsScroll)
	return list.Layout(gtx, 1, func(gtx layout.Context, _ int) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(16), Left: unit.Dp(16), Right: unit.Dp(16)}.Layout(gtx,
			func(gtx layout.Context) layout.Dimensions {
				switch f.settingsSect {
				case setSectionMain:
					return a.setPageMain(gtx, f)
				case setSectionNotifications:
					return a.setPageNotifications(gtx, f)
				case setSectionPrivacy:
					return a.setPagePrivacy(gtx, f)
				case setSectionData:
					return a.setPageData(gtx, f)
				case setSectionAppearance:
					return a.setPageAppearance(gtx, f)
				case setSectionAyu:
					return a.setPageAyu(gtx, f)
				default:
					return a.setPageAbout(gtx, f)
				}
			})
	})
}

// sectionTitle renders a page heading.
func (a *App) sectionTitle(gtx layout.Context, txt string) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(10), Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		lbl := a.ui.Label(unit.Sp(16), txt)
		lbl.Font.Weight = font.SemiBold
		return lbl.Layout(gtx)
	})
}

// settingRow renders a plain label + optional value line.
func (a *App) settingRow(gtx layout.Context, title, sub string) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Label(unit.Sp(14), title)
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
	})
}

// toggleRow renders label + material switch; persists via apply on flip.
func (a *App) toggleRow(gtx layout.Context, key, label string, value bool, apply func(bool)) layout.Dimensions {
	sw := settingsSwitch(key)
	if !settingsSynced[key] {
		sw.Value = value
		settingsSynced[key] = true
	}
	prev := sw.Value
	dims := layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
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
	if sw.Value != prev {
		apply(sw.Value)
	}
	return dims
}

// ── pages ─────────────────────────────────────────────────────────────────

// setPageMain: account cards (add / remove / state) — multi-backend "one
// frontend, many accounts" (AGENTS.md §7).
func (a *App) setPageMain(gtx layout.Context, f frame) layout.Dimensions {
	growClickables(&settingsRemoveBtns, len(f.accounts))
	var children []layout.FlexChild
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Accounts")
	}))
	for i, acc := range f.accounts {
		i, acc := i, acc
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return a.ui.Avatar(gtx, accountName(acc), unit.Dp(40), connDotFor(acc))
								})
							}),
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								sub := platformTitle(acc.Platform)
								if acc.Username != "" {
									sub += " · @" + acc.Username
								}
								return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										lbl := a.ui.Label(unit.Sp(15), accountName(acc))
										return lbl.Layout(gtx)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										lbl := a.ui.Dim(unit.Sp(11), sub)
										return lbl.Layout(gtx)
									}),
								)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								if settingsRemoveBtns[i].Clicked(gtx) {
									id := acc.ID
									a.removeAccount(id)
								}
								btn := a.ui.TextButton(&settingsRemoveBtns[i], "Remove")
								btn.Color = a.ui.p.Error
								btn.TextSize = unit.Sp(13)
								return btn.Layout(gtx)
							}),
						)
					})
				})
			})
		}))
	}
	if len(f.accounts) == 0 {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(13), "No accounts")
			return lbl.Layout(gtx)
		}))
	}
	if settingsAddBtn.Clicked(gtx) {
		a.mu.Lock()
		a.showPicker = true
		a.mu.Unlock()
		a.invalidate()
	}
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			btn := a.ui.SurfaceButton(&settingsAddBtn, "Add account")
			return btn.Layout(gtx)
		})
	}))
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// setPageNotifications: global config toggles + per-account notification
// behavior (contact sign-up notifications, calls-disabled-here).
func (a *App) setPageNotifications(gtx layout.Context, f frame) layout.Dimensions {
	var children []layout.FlexChild
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Notifications")
	}))
	c := f.cfg
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.toggleRow(gtx, "cfg:notify_dms", "Private chats", c.NotifyDMs, func(v bool) {
			a.applyConfigBool("notify_dms", v)
		})
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.toggleRow(gtx, "cfg:notify_groups", "Groups", c.NotifyGroups, func(v bool) {
			a.applyConfigBool("notify_groups", v)
		})
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.toggleRow(gtx, "cfg:notify_mentions_only", "Mentions only", c.NotifyMentionsOnly, func(v bool) {
			a.applyConfigBool("notify_mentions_only", v)
		})
	}))
	if !f.notifyLoaded {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.loadingNote(gtx)
		}))
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
	}
	for _, acc := range f.accounts {
		acc := acc
		st := f.notifyAccts[acc.ID]
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.subHeader(gtx, accountName(acc)+" ("+platformTitle(acc.Platform)+")")
		}))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.toggleRow(gtx, "notify:signup:"+acc.ID, "Contact sign-up notifications", st.contact, func(v bool) {
				go func() {
					if err := a.eng.SetContactSignUpNotification(acc.ID, v); err != nil {
						a.setToast("Notifications: " + err.Error())
					}
				}()
			})
		}))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.toggleRow(gtx, "notify:calls:"+acc.ID, "Disable calls on this account", st.calls, func(v bool) {
				go func() {
					if err := a.eng.SetCallsDisabledHere(acc.ID, v); err != nil {
						a.setToast("Calls: " + err.Error())
					}
				}()
			})
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// setPagePrivacy: blocked users + active sessions per account.
func (a *App) setPagePrivacy(gtx layout.Context, f frame) layout.Dimensions {
	var children []layout.FlexChild
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Privacy & Security")
	}))
	if !f.privacyLoaded {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.loadingNote(gtx)
		}))
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
	}
	for _, acc := range f.accounts {
		acc := acc
		blocked := f.blockedUsers[acc.ID]
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.subHeader(gtx, accountName(acc)+" ("+platformTitle(acc.Platform)+")")
		}))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			n := itoa(len(blocked))
			return a.settingRow(gtx, "Blocked users ("+n+")", "")
		}))
		for _, u := range blocked {
			u := u
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				sub := u.DisplayName
				if u.Username != "" {
					sub = "@" + u.Username
				}
				return a.bulletedRow(gtx, u.DisplayName, sub)
			}))
		}
		sessions := f.sessionsList[acc.ID]
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			n := itoa(len(sessions))
			return a.settingRow(gtx, "Active sessions ("+n+")", "")
		}))
		for _, s := range sessions {
			s := s
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				title := s.Device
				if s.Platform != "" {
					title += " · " + s.Platform
				}
				sub := s.Location
				if s.IsCurrent {
					sub = "This device"
				} else if s.System != "" && s.Location != "" {
					sub = s.System + " · " + s.Location
				}
				return a.bulletedRow(gtx, title, sub)
			}))
		}
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// setPageData: cache accounting + per-tag and total clears (engine media
// pipeline's Local Storage view).
func (a *App) setPageData(gtx layout.Context, f frame) layout.Dimensions {
	growClickables(&clearTagBtns, len(cacheTagLabels))
	var children []layout.FlexChild
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Data & Storage")
	}))
	if !f.cacheLoaded {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.loadingNote(gtx)
		}))
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
	}
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Total cache used", fmtBytes(f.cacheTotal))
	}))
	for i, label := range cacheTagLabels {
		i, label := i, label
		size := f.cacheTags[i]
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					return a.settingRow(gtx, label, fmtBytes(size))
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if clearTagBtns[i].Clicked(gtx) {
						tag := i
						go func() {
							if err := a.eng.ClearCacheByTag("", tag); err != nil {
								a.setToast("Clear cache: " + err.Error())
							}
							a.loadStorage()
						}()
					}
					if size == 0 {
						return layout.Dimensions{}
					}
					btn := a.ui.TextButton(&clearTagBtns[i], "Clear")
					btn.TextSize = unit.Sp(12)
					return btn.Layout(gtx)
				}),
			)
		}))
	}
	if clearAllBtn.Clicked(gtx) {
		go func() {
			if err := a.eng.ClearCache(""); err != nil {
				a.setToast("Clear cache: " + err.Error())
			}
			a.loadStorage()
		}()
	}
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			btn := a.ui.SurfaceButton(&clearAllBtn, "Clear all cached media")
			return btn.Layout(gtx)
		})
	}))
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// setPageAppearance: theme (dark/light) persisted in the config.
func (a *App) setPageAppearance(gtx layout.Context, f frame) layout.Dimensions {
	var children []layout.FlexChild
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Appearance")
	}))
	isLight := f.cfg.Theme == "light"
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.toggleRow(gtx, "appearance:light", "Light theme", isLight, func(v bool) {
			a.applyTheme(v)
		})
	}))
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// setPageAyu: ghost-mode flags — global (config) + per-account overrides
// (engine ghost override store). The AyuGram differentiator (§10).
func (a *App) setPageAyu(gtx layout.Context, f frame) layout.Dimensions {
	growClickables(&ghostAcctChips, len(f.accounts))
	ghostRows := []struct {
		field, label string
	}{
		{"send_read_receipts", "Send read receipts"},
		{"send_upload_progress", "Send upload progress"},
		{"send_read_stories", "Send read stories"},
		{"send_online_packets", "Send online status"},
		{"send_offline_after_online", "Send offline after going online"},
		{"mark_read_after_action", "Mark read after reacting"},
		{"use_scheduled_messages", "Use scheduled messages"},
		{"send_without_sound", "Send without sound"},
	}
	var children []layout.FlexChild
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Ayu · Ghost mode")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Global defaults", "Applies to every account without an override")
	}))
	c := f.cfg
	globalVals := map[string]bool{
		"send_read_receipts":        c.SendReadReceipts,
		"send_typing":               c.SendTyping,
		"send_upload_progress":      c.SendUploadProgress,
		"send_read_stories":         c.SendReadStories,
		"send_online_packets":       c.SendOnlinePackets,
		"send_offline_after_online": c.SendOfflineAfterOnline,
		"mark_read_after_action":    c.MarkReadAfterAction,
		"use_scheduled_messages":    c.UseScheduledMessages,
		"send_without_sound":        c.SendWithoutSound,
	}
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.toggleRow(gtx, "cfg:send_read_receipts", "Send read receipts", globalVals["send_read_receipts"], func(v bool) {
			a.applyConfigBool("send_read_receipts", v)
		})
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.toggleRow(gtx, "cfg:send_typing", "Send typing activity", globalVals["send_typing"], func(v bool) {
			a.applyConfigBool("send_typing", v)
		})
	}))
	for _, r := range ghostRows {
		if r.field == "send_read_receipts" {
			continue // rendered above with typing
		}
		r := r
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.toggleRow(gtx, "cfg:"+r.field, r.label, globalVals[r.field], func(v bool) {
				a.applyConfigBool(r.field, v)
			})
		}))
	}

	if len(f.accounts) == 0 {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
	}
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.subHeader(gtx, "Per-account overrides")
	}))
	// account chips
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, a.chips(gtx, f)...)
	}))
	sel := f.ghostSel
	if sel == "" {
		sel = f.accounts[0].ID
	}
	if !f.ghostLoaded {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.loadingNote(gtx)
		}))
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
	}
	g := f.ghostFlags[sel]
	ghostVals := map[string]bool{
		"send_read_receipts":        g.SendReadReceipts,
		"send_upload_progress":      g.SendUploadProgress,
		"send_read_stories":         g.SendReadStories,
		"send_online_packets":       g.SendOnlinePackets,
		"send_offline_after_online": g.SendOfflineAfterOnline,
		"mark_read_after_action":    g.MarkReadAfterAction,
		"use_scheduled_messages":    g.UseScheduledMessages,
		"send_without_sound":        g.SendWithoutSound,
	}
	for _, r := range ghostRows {
		r := r
		key := "ghost:" + sel + ":" + r.field
		val := ghostVals[r.field]
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.toggleRow(gtx, key, r.label, val, func(v bool) {
				a.applyGhostFlag(sel, r.field, v)
			})
		}))
	}
	if ghostResetBtn.Clicked(gtx) {
		go func() {
			a.eng.ClearAccountGhostOverrides()
			a.loadGhost()
		}()
	}
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			btn := a.ui.SurfaceButton(&ghostResetBtn, "Reset all overrides to global")
			return btn.Layout(gtx)
		})
	}))
	// Drawer customization (Ayu "drawer" menu parity): hide drawer rows.
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Ayu · Drawer")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Show drawer items", "Hide rows you never use; Settings always stays")
	}))
	for _, item := range drawerCustomItems() {
		item := item
		visible := !drawerRowHidden(f.cfg.DrawerHidden, item.id)
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.toggleRow(gtx, "drawer:"+item.id, item.label, visible, func(v bool) {
				a.applyDrawerHidden(item.id, v)
			})
		}))
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// chips renders the account selector chips for the ghost page and records
// the selection (App.ghostSel).
func (a *App) chips(gtx layout.Context, f frame) []layout.FlexChild {
	out := make([]layout.FlexChild, 0, len(f.accounts))
	sel := f.ghostSel
	if sel == "" && len(f.accounts) > 0 {
		sel = f.accounts[0].ID
	}
	for i, acc := range f.accounts {
		i, acc := i, acc
		out = append(out, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			btn := &ghostAcctChips[i]
			if btn.Clicked(gtx) {
				a.mu.Lock()
				a.ghostSel = acc.ID
				a.mu.Unlock()
				a.invalidate()
			}
			return layout.Inset{Right: unit.Dp(6), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					bg := a.ui.p.Surface
					if acc.ID == sel {
						bg = a.ui.p.AccentDim
					}
					return roundedFill(gtx, bg, 8, func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4), Left: unit.Dp(8), Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(12), accountName(acc))
							return lbl.Layout(gtx)
						})
					})
				})
			})
		}))
	}
	return out
}

// setPageAbout: static about page.
func (a *App) setPageAbout(gtx layout.Context, f frame) layout.Dimensions {
	var children []layout.FlexChild
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "About")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Uniclient", "One frontend, every messenger backend")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Backends", "Telegram · IRC · Matrix · GitHub · XMPP · Delta Chat")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "UI", "Gio · pure Go · single binary")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Source", "github.com/DarkReaperBoy/Uniclient")
	}))
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// ── small helpers ─────────────────────────────────────────────────────────

func (a *App) subHeader(gtx layout.Context, txt string) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(12), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		lbl := a.ui.Label(unit.Sp(13), txt)
		lbl.Color = a.ui.p.Accent
		lbl.Font.Weight = font.SemiBold
		return lbl.Layout(gtx)
	})
}

func (a *App) bulletedRow(gtx layout.Context, title, sub string) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				d := gtx.Dp(unit.Dp(5))
				paint.FillShape(gtx.Ops, a.ui.p.TextFaint, clip.Ellipse{Min: image.Pt(0, 0), Max: image.Pt(d, d)}.Op(gtx.Ops))
				return layout.Dimensions{Size: image.Pt(d, d)}
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(13), title)
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
				})
			}),
		)
	})
}

func (a *App) loadingNote(gtx layout.Context) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				ld := material.Loader(a.ui.Theme)
				ld.Color = a.ui.p.Accent
				return ld.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(13), "Loading…")
					return lbl.Layout(gtx)
				})
			}),
		)
	})
}
