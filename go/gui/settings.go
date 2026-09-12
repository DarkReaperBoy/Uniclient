package gui

import (
	"runtime"

	"image"
	"math"
	"strings"

	"gioui.org/font"
	"gioui.org/io/key"
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

// settingsSections is the rail, in AyuGram's order (Language between
// Calls and Ayu, tdesktop's position).
var settingsSections = []string{
	"Main", "Notifications", "Privacy & Security", "Data & Storage",
	"Appearance", "Calls", "Language", "Ayu", "About",
}

const (
	setSectionMain = iota
	setSectionNotifications
	setSectionPrivacy
	setSectionData
	setSectionAppearance
	setSectionCalls
	setSectionLanguage
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
	iconHardwareHeadset, // Calls (slice 103)
	iconActionSchedule,  // Language (slice 140)
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
	case "local_read_mark":
		c.LocalReadMark = &b
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
	case "notify_previews":
		c.NotifyPreviews = &b
	case "ayu_save_deleted":
		c.AyuSaveDeleted = &b
	case "ayu_save_history":
		c.AyuSaveHistory = &b
	case "ayu_save_for_bots":
		c.AyuSaveForBots = &b
	case "ayu_improve_link_previews":
		c.AyuImproveLinkPreviews = &b
	case "bubble_corners":
		c.BubbleCorners = &b
	case "hide_all_chats":
		c.HideAllChats = &b
	case "system_tray":
		c.SystemTray = &b
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
	settingsRailBtns    []widget.Clickable
	settingsSwitches    = map[string]*widget.Bool{}
	settingsSynced      = map[string]bool{}
	settingsRemoveBtns  []widget.Clickable
	settingsProfileBtns []widget.Clickable
	settingsAddBtn      widget.Clickable
	settingsBackBtn     widget.Clickable
	settingsKeyTag      struct{} // Escape-close key listener tag
	clearTagBtns        []widget.Clickable
	clearAllBtn         widget.Clickable
	exportDataBtn       widget.Clickable
	ghostResetBtn       widget.Clickable
	ghostAcctChips      []widget.Clickable
	settingsScroll      widget.List

	// Ayu mark-string editors (settings_ayu, slice 47).
	ayuDeletedEd   widget.Editor
	ayuEditedEd    widget.Editor
	ayuMarksSave   widget.Clickable
	ayuMarksSynced bool
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
	// Escape closes (self-handled, per escTarget's contract). Pointer-
	// transparent via keyLayer so the sidebar stays interactive.
	keyLayer(gtx, settingsKeyTag)
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeSettings()
		}
	}
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
	labels := settingsRailLabels(f.langStrings)
	children := make([]layout.FlexChild, 0, len(settingsSections))
	for i := range settingsSections {
		i := i
		title := labels[i]
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
				if f.profileEdit != nil {
					return a.layoutProfileEdit(gtx, f, f.profileEdit)
				}
				if f.stickerMgr != nil {
					return a.layoutStickerMgr(gtx, f)
				}
				if f.folderMgr != nil {
					return a.layoutFolderMgr(gtx, f)
				}
				if f.premiumPage != nil {
					return a.layoutPremiumPage(gtx, f)
				}
				if f.starsPage != nil {
					return a.layoutStarsPage(gtx, f)
				}
				if f.businessPage != nil {
					return a.layoutBusinessPage(gtx, f)
				}
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
				case setSectionCalls:
					return a.setPageCalls(gtx, f)
				case setSectionLanguage:
					return a.setPageLanguage(gtx, f)
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
	growClickables(&settingsProfileBtns, len(f.accounts))
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
								if settingsProfileBtns[i].Clicked(gtx) {
									a.openProfileEdit(acc.ID)
								}
								btn := a.ui.TextButton(&settingsProfileBtns[i], "Edit profile")
								btn.Color = a.ui.p.Accent
								btn.TextSize = unit.Sp(13)
								return btn.Layout(gtx)
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
	// Chat folders (AyuGram folder settings, slice 85): hide the All tab.
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Chat folders")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.toggleRow(gtx, "cfg:hide_all_chats", `Hide "All chats" tab`, f.cfg.HideAllChats, func(v bool) {
			a.applyConfigBool("hide_all_chats", v)
		})
	}))

	// Stickers and Emoji manager entry (slice 139, tdesktop "Stickers
	// and Emoji"): per-account set manager. Hidden without accounts
	// (nothing to manage — §1.10 honest states).
	if len(f.accounts) > 0 {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.stickerMgrEntryRow(gtx, f)
		}))
	}

	// Chat-folders manager entry (slice 142, tdesktop's "Filter chats"
	// box): folder CRUD + reorder + server-suggested folders. Hidden
	// without accounts (same honest-state rule).
	if len(f.accounts) > 0 {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.folderMgrEntryRow(gtx, f)
		}))
	}

	// Telegram Premium entry (slice 143, tdesktop's Premium box):
	// subscription status, plans, limits. Telegram-platform accounts only
	// (premium is a Telegram surface — no dead UI for other platforms).
	if premiumEntryVisible(f.accounts) {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.premiumEntryRow(gtx, f)
		}))
	}

	// Telegram Stars entry (slice 144, tdesktop's Stars box): balance
	// + transaction history. Telegram-platform accounts only.
	if premiumEntryVisible(f.accounts) {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.starsEntryRow(gtx, f)
		}))
	}

	// Telegram Business entry (slice 148, tdesktop's Business box):
	// opening hours, location, greeting/away messages, quick replies,
	// intro. Telegram-platform accounts only (§1.10).
	if premiumEntryVisible(f.accounts) {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.businessEntryRow(gtx, f)
		}))
	}

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
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.toggleRow(gtx, "cfg:notify_previews", "Message previews", c.NotifyPreviews, func(v bool) {
			a.applyConfigBool("notify_previews", v)
		})
	}))
	// System tray icon (slice 137): live start/stop; only on platforms
	// that have a tray (web/Android render no dead toggle, §1.10).
	if traySupportedOn {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.toggleRow(gtx, "cfg:system_tray", "System tray icon", c.SystemTray, a.applySystemTray)
		}))
	}
	// Notification sound picker (slice 121): synthesized chimes with
	// preview; per-chat overrides live in the chat header menu.
	growClickables(&notifySoundRowBtn, 1)
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		btn := &notifySoundRowBtn[0]
		if btn.Clicked(gtx) {
			a.openSoundPickerGlobal()
		}
		bl := material.ButtonLayout(a.ui.Theme, btn)
		bl.Background = a.ui.p.Surface
		bl.CornerRadius = 10
		return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							return a.ui.Label(unit.Sp(14), "Notification sound").Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(12), notifySoundLabel(c.NotifySound))
							lbl.Color = a.ui.p.TextFaint
							return lbl.Layout(gtx)
						}),
					)
				})
			})
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
		// Reactions / poll-votes notifications (AyuGram, slice 61).
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.toggleRow(gtx, "notify:react:"+acc.ID, "Reaction notifications", st.reactOn, func(v bool) {
				a.mu.Lock()
				cur := a.notifyAccts[acc.ID]
				cur.reactOn = v
				a.notifyAccts[acc.ID] = cur
				a.mu.Unlock()
				a.applyReactionsNotify(acc.ID, cur)
			})
		}))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.toggleRow(gtx, "notify:reactfrom:"+acc.ID, "Reactions from contacts only", st.reactFrom == "contacts", func(v bool) {
				a.mu.Lock()
				cur := a.notifyAccts[acc.ID]
				if v {
					cur.reactFrom = "contacts"
				} else {
					cur.reactFrom = "everyone"
				}
				a.notifyAccts[acc.ID] = cur
				a.mu.Unlock()
				a.applyReactionsNotify(acc.ID, cur)
			})
		}))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.toggleRow(gtx, "notify:polls:"+acc.ID, "Poll-vote notifications", st.pollsOn, func(v bool) {
				a.mu.Lock()
				cur := a.notifyAccts[acc.ID]
				cur.pollsOn = v
				a.notifyAccts[acc.ID] = cur
				a.mu.Unlock()
				a.applyReactionsNotify(acc.ID, cur)
			})
		}))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.toggleRow(gtx, "notify:pollsfrom:"+acc.ID, "Poll votes from contacts only", st.pollsFrom == "contacts", func(v bool) {
				a.mu.Lock()
				cur := a.notifyAccts[acc.ID]
				if v {
					cur.pollsFrom = "contacts"
				} else {
					cur.pollsFrom = "everyone"
				}
				a.notifyAccts[acc.ID] = cur
				a.mu.Unlock()
				a.applyReactionsNotify(acc.ID, cur)
			})
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// setPagePrivacy: privacy scopes (slice 62), blocked users, and active
// sessions per account.
var privacyRowBtns []widget.Clickable
var lockRowBtns []widget.Clickable // passcode row (slice 87)

func (a *App) setPagePrivacy(gtx layout.Context, f frame) layout.Dimensions {
	growClickables(&privacyRowBtns, len(f.accounts)*len(privacyKeyLabels))
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
	// Security (slice 87): app-level local passcode lock — not per-account.
	growClickables(&lockRowBtns, 1)
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.subHeader(gtx, "Security")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		btn := &lockRowBtns[0]
		if btn.Clicked(gtx) {
			a.openLockDialog()
		}
		bl := material.ButtonLayout(a.ui.Theme, btn)
		bl.Background = a.ui.p.Surface
		bl.CornerRadius = 10
		return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					value := "Off"
					if f.lock != nil {
						value = "On · " + itoa(f.lock.digits) + " digits"
						if f.lock.autolockMin > 0 {
							value += " · auto-lock " + autolockLabel(f.lock.autolockMin)
						}
					}
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								gtx.Constraints.Min.X = gtx.Dp(unit.Dp(22))
								return iconActionLock.Layout(gtx, a.ui.p.TextDim)
							})
						}),
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							return a.ui.Label(unit.Sp(14), "Passcode Lock").Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(12), value)
							lbl.Color = a.ui.p.TextFaint
							return lbl.Layout(gtx)
						}),
					)
				})
			})
		})
	}))
	row := 0
	twofaRow := 0 // separate index: twofaRowBtns is its own pool (slice 120)
	for _, acc := range f.accounts {
		acc := acc
		blocked := f.blockedUsers[acc.ID]
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.subHeader(gtx, accountName(acc)+" ("+platformTitle(acc.Platform)+")")
		}))
		// Two-Step Verification (slice 120): cloud-password editor,
		// capability-gated — cores without the surface get no row.
		growClickables(&twofaRowBtns, len(f.accounts))
		if twofaSupportedFor(a, acc.ID) {
			btn := &twofaRowBtns[twofaRow]
			twofaRow++
			st := f.twofaStates[acc.ID]
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if btn.Clicked(gtx) {
					a.openTwoFADialog(acc.ID)
				}
				bl := material.ButtonLayout(a.ui.Theme, btn)
				bl.Background = a.ui.p.Surface
				bl.CornerRadius = 10
				return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									return a.ui.Label(unit.Sp(14), "Two-Step Verification").Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Dim(unit.Sp(12), twofaRowValue(st))
									lbl.Color = a.ui.p.TextFaint
									return lbl.Layout(gtx)
								}),
							)
						})
					})
				})
			}))
		}
		// Privacy scope rows (slice 62): live server-side scope per key;
		// tapping opens the picker dialog (gui/privacy.go).
		accScopes := f.privacyScopes[acc.ID]
		supported := len(accScopes) > 0
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.subHeader(gtx, "Privacy")
		}))
		for _, r := range privacyKeyLabels {
			r := r
			scope := accScopes[r.key]
			btn := &privacyRowBtns[row]
			row++
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if !supported {
					return a.settingRow(gtx, r.label, "—")
				}
				if btn.Clicked(gtx) {
					a.openPrivacyDialog(acc.ID, r.key)
				}
				bl := material.ButtonLayout(a.ui.Theme, btn)
				bl.Background = a.ui.p.Surface
				bl.CornerRadius = 10
				return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Label(unit.Sp(14), r.label)
									return lbl.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Dim(unit.Sp(12), privacyScopeLabel(scope))
									lbl.Color = a.ui.p.TextFaint
									return lbl.Layout(gtx)
								}),
							)
						})
					})
				})
			}))
		}
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
	// Proxy + download path (slice 85).
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.layoutProxySection(gtx, f)
	}))
	// Automatic media download rows (slice 63): one per source, value
	// summarizes the live rules; tap opens the editor dialog.
	growClickables(&autodlRowBtns, len(autodlSourceLabels))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.subHeader(gtx, "Automatic media download")
	}))
	for i, r := range autodlSourceLabels {
		i, r := i, r
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			btn := &autodlRowBtns[i]
			if btn.Clicked(gtx) {
				a.openAutodlDialog(r.source)
			}
			bl := material.ButtonLayout(a.ui.Theme, btn)
			bl.Background = a.ui.p.Surface
			bl.CornerRadius = 10
			return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), r.label)
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								sub := autodlRowSummaryFor(f, r.source)
								if sub == "" {
									return layout.Dimensions{}
								}
								lbl := a.ui.Dim(unit.Sp(11), sub)
								lbl.Color = a.ui.p.TextFaint
								return lbl.Layout(gtx)
							}),
						)
					})
				})
			})
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
	// Export data wizard (slice 100, matrix row 208): takeout export for
	// the first takeout-capable connected account (capability-gated — no
	// dead rows on cores without takeout).
	if exportDataBtn.Clicked(gtx) {
		if acct := firstTakeoutAccount(f.takeoutAccts); acct != "" {
			a.openExportDialog(acct)
		}
	}
	if acct := firstTakeoutAccount(f.takeoutAccts); acct != "" {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.SurfaceButton(&exportDataBtn, "Export data")
				return btn.Layout(gtx)
			})
		}))
	}
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			btn := a.ui.SurfaceButton(&clearAllBtn, "Clear all cached media")
			return btn.Layout(gtx)
		})
	}))
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// accentPresets are the selectable accent colors (AyuGram appearance).
type accentPreset struct {
	hex  string
	name string
}

var accents = []accentPreset{
	{"#4f6ef7", "Blue"},
	{"#8774e1", "Purple"},
	{"#40a358", "Green"},
	{"#e0851e", "Orange"},
	{"#e1425c", "Pink"},
	{"#df4549", "Red"},
}

// fontScaleChoices are the text-scale segments (Small/Default/Large).
var fontScaleChoices = []struct {
	label string
	v     float64
}{
	{"Small", 0.9},
	{"Default", 1.0},
	{"Large", 1.2},
}

var appearanceAccentBtns []widget.Clickable
var appearanceScaleBtns []widget.Clickable

// setPageAppearance: theme (dark/light), accent color, and font scale —
// all persisted in the config (AyuGram appearance).
func (a *App) setPageAppearance(gtx layout.Context, f frame) layout.Dimensions {
	growClickables(&appearanceAccentBtns, len(accents))
	growClickables(&appearanceScaleBtns, len(fontScaleChoices))
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
	// Power saving (slice 135, tdesktop parity): master toggle — blocks
	// chat animation loops (stickers, dice, inline custom emoji render
	// their first frame, no re-arm). Persisted through AppConfig.
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.toggleRow(gtx, "appearance:powersave", "Power saving", powerSaving.forceAll, func(v bool) {
			a.psSet(powerSaving.flags, v)
		})
	}))

	// Layout tweak sliders (AyuGram appearance, slice 93): bubble corner
	// radius replaces the legacy rounded/square toggle (radius 12 = the
	// old rounded default, 2 = near-square); bubble width is the "wide
	// multiplier" (0.70..1.00 of the chat pane, default 0.75).
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Layout")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layoutSliderRow(a, gtx, f, &appearanceRadiusSlider,
			"Bubble corners", "Message-bubble corner radius",
			bubbleRadiusSliderLabel,
			func(v float32) int { return int(v*float32(18) + 0.5) },
			func(dp int) { a.applyLayoutTweaksUI(dp, -1) })
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layoutSliderRow(a, gtx, f, &appearanceWideSlider,
			"Bubble width", "How wide bubbles may stretch across the pane",
			wideSliderLabel,
			func(v float32) float64 { return 0.70 + float64(v)*0.30 },
			func(w float64) { a.applyLayoutTweaksUI(-1, w) })
	}))
	// Messages section (tdesktop Chat settings, slice 155): the
	// composer submit mode (Send with Enter / Ctrl+Enter).
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.layoutMessagesSection(gtx, f)
	}))
	// Accent swatches (AyuGram "Choose accent color").
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Accent color")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(8), Left: unit.Dp(16), Right: unit.Dp(16)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			children := make([]layout.FlexChild, 0, len(accents))
			for i, preset := range accents {
				i, preset := i, preset
				children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := &appearanceAccentBtns[i]
					if btn.Clicked(gtx) {
						a.applyAccent(preset.hex)
					}
					active := strings.EqualFold(strings.TrimSpace(f.cfg.Accent), preset.hex)
					sz := gtx.Dp(unit.Dp(34))
					c, ok := parseAccentHex(preset.hex)
					if !ok {
						c = a.ui.p.Accent
					}
					gtx.Constraints.Max = image.Pt(sz, sz)
					gtx.Constraints.Min = image.Pt(sz, sz)
					cl := clip.UniformRRect(image.Rectangle{Max: image.Pt(sz, sz)}, sz/2).Push(gtx.Ops)
					paint.FillShape(gtx.Ops, c, clip.Ellipse{Min: image.Pt(0, 0), Max: image.Pt(sz, sz)}.Op(gtx.Ops))
					cl.Pop()
					if active {
						// selection ring
						ring := clip.Stroke{Width: float32(gtx.Dp(unit.Dp(2))), Path: clip.Ellipse{
							Min: image.Pt(-gtx.Dp(unit.Dp(3)), -gtx.Dp(unit.Dp(3))),
							Max: image.Pt(sz+gtx.Dp(unit.Dp(3)), sz+gtx.Dp(unit.Dp(3))),
						}.Path(gtx.Ops)}.Op()
						paint.FillShape(gtx.Ops, a.ui.p.Text, ring)
					}
					return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Dimensions{Size: image.Pt(sz, sz)}
					})
				}))
			}
			return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, children...)
		})
	}))
	// Font scale segments (AyuGram "Choose font size").
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Font size")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(8), Left: unit.Dp(16), Right: unit.Dp(16)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			children := make([]layout.FlexChild, 0, len(fontScaleChoices))
			for i, ch := range fontScaleChoices {
				i, ch := i, ch
				children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := &appearanceScaleBtns[i]
					if btn.Clicked(gtx) {
						a.applyFontScale(ch.v)
					}
					cur := math.Abs(f.cfg.FontScale-ch.v) < 0.05
					b := material.Button(a.ui.Theme, btn, ch.label)
					b.Background = a.ui.p.SurfaceHi
					b.Color = a.ui.p.TextDim
					b.TextSize = unit.Sp(13)
					b.CornerRadius = 10
					b.Inset = layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6), Left: unit.Dp(12), Right: unit.Dp(12)}
					if cur {
						b.Background = a.ui.p.AccentDim
						b.Color = a.ui.p.Text
					}
					return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, b.Layout)
				}))
			}
			return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, children...)
		})
	}))
	// Custom fonts (slice 146, tdesktop's font box): pick .ttf/.otf
	// for the UI (+ optional mono), applied at runtime and persisted.
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Fonts")
	}))
	fontRows := a.fontSettingsRows(gtx, f)
	for _, r := range fontRows {
		r := r
		children = append(children, r)
	}
	// Cloud themes (slice 66): server-side theme list + install flow.
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.layoutCloudThemeSection(gtx, f)
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
	// Ayu · General (AyuGram settings_general, slice 155): improve link
	// previews — outgoing links of big platforms are rewritten to their
	// preview-friendly mirrors.
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Ayu · General")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Improve link previews", "Send links via preview-friendly mirrors (X, TikTok, Reddit, Instagram, Pixiv)")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.toggleRow(gtx, "cfg:ayu_improve_link_previews", "Improve previews", f.cfg.AyuImproveLinkPreviews, func(v bool) {
			a.applyConfigBool("ayu_improve_link_previews", v)
		})
	}))
	// Ayu mark strings (AyuGram settings_ayu: deleted/edited marks, slice 47).
	if !ayuMarksSynced {
		ayuDeletedEd.SetText(f.cfg.AyuDeletedMark)
		ayuEditedEd.SetText(f.cfg.AyuEditedMark)
		ayuMarksSynced = true
	}
	if ayuMarksSave.Clicked(gtx) {
		dm := strings.TrimSpace(ayuDeletedEd.Text())
		em := strings.TrimSpace(ayuEditedEd.Text())
		go func() {
			c := engine.ConfigChanges{AyuDeletedMark: &dm, AyuEditedMark: &em}
			if err := a.eng.UpdateConfigFromBridge(&c); err != nil {
				a.setToast("Ayu marks: " + err.Error())
				return
			}
			a.refreshConfig()
		}()
	}
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Ayu · Message marks")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Deleted mark", "Shown on anti-recall messages (empty = "+defaultDeletedMark+")")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.markEditorRow(gtx, &ayuDeletedEd, "Deleted mark")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Edited mark", "Prefix before the edit time (empty = "+defaultEditedMark+")")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.markEditorRow(gtx, &ayuEditedEd, "Edited mark")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(12), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			btn := a.ui.TextButton(&ayuMarksSave, "Apply marks")
			btn.Color = a.ui.p.Accent
			return btn.Layout(gtx)
		})
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Ayu · Anti-recall")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Save deleted messages", "Keep anti-recall copies of deleted messages")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.toggleRow(gtx, "cfg:ayu_save_deleted", "Save deleted", f.cfg.AyuSaveDeleted, func(v bool) {
			a.applyConfigBool("ayu_save_deleted", v)
		})
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.toggleRow(gtx, "cfg:ayu_save_history", "Save history", f.cfg.AyuSaveHistory, func(v bool) {
			a.applyConfigBool("ayu_save_history", v)
		})
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.toggleRow(gtx, "cfg:ayu_save_for_bots", "Save for bots", f.cfg.AyuSaveForBots, func(v bool) {
			a.applyConfigBool("ayu_save_for_bots", v)
		})
	}))
	// Message filters (slice 90, matrix row 238): local regex hide-rules.
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Ayu · Message filters")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.layoutAyuFilterRow(gtx, f)
	}))
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

// appVersion is the Uniclient version shown on the About page (bumped at
// release time; the release pipeline tags the same number).
const appVersion = "0.7.0"

// aboutRow is one key/description line on the About page.
type aboutRow struct {
	key, desc string
}

// shortcutRows lists the global keyboard shortcuts (AyuGram About page
// style). Pure — kept in sync with gui/shortcuts.go by tests.
func shortcutRows() []aboutRow {
	return []aboutRow{
		{"Esc", "close the topmost surface (menu, panel, search…)"},
		{"Ctrl+F", "search in the open chat, or filter the chat list"},
		{"Ctrl+↑ / Ctrl+↓", "previous / next chat"},
		{"Ctrl+PgUp / Ctrl+PgDn", "previous / next chat"},
		{"Right-click", "context menu (chat row, bubble, header, folder tab)"},
		{"/", "bot commands menu (chats with commands)"},
	}
}

// setPageAbout: about page — version, backends, and the shortcut list.
func (a *App) setPageAbout(gtx layout.Context, f frame) layout.Dimensions {
	var children []layout.FlexChild
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "About")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Uniclient "+appVersion, "One frontend, every messenger backend")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Go runtime", runtime.Version())
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
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Keyboard shortcuts")
	}))
	for _, r := range shortcutRows() {
		r := r
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.bulletedRow(gtx, r.key, r.desc)
		}))
	}
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

// applyBubbleCornersUI swaps the corner style and persists it (appearance,
// slice 82).
func (a *App) applyBubbleCornersUI(round bool) {
	a.ui.applyBubbleCorners(round)
	a.applyConfigBool("bubble_corners", round)
}
