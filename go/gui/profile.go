package gui

import (
	"image"
	"image/color"
	"io"
	"strings"

	"gioui.org/io/clipboard"
	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Right info panel — the AyuGram third pane (research/ayugram_parity.md §7):
// profile for DMs (username/phone/bio, block, add-contact), member list for
// groups/channels (role badges), shared-media counts + recent photos, and the
// per-chat notifications toggle. Every row reads engine state; every action
// dispatches a real engine call (§1.10).

// panelSwitches pools the panel's toggle (mute) per chat.
var (
	panelSwitches = map[string]*widget.Bool{}
	panelSynced   = map[string]bool{}
	panelInfoBtn  widget.Clickable
	panelCloseBtn widget.Clickable
	panelBlockBtn widget.Clickable
	panelAddBtn   widget.Clickable
	panelScroll   widget.List
)

func init() {
	panelScroll.Axis = layout.Vertical
}

func panelSwitch(key string) *widget.Bool {
	if s, ok := panelSwitches[key]; ok {
		return s
	}
	if len(panelSwitches) > 64 {
		panelSwitches = make(map[string]*widget.Bool)
		panelSynced = make(map[string]bool)
	}
	s := new(widget.Bool)
	panelSwitches[key] = s
	return s
}

// colorNRGBA aliases the color type for tests.
type colorNRGBA = color.NRGBA

// panelSectionsFor reports which sections a chat type shows.
func panelSectionsFor(chatType int) (profile, members bool) {
	switch chatType {
	case engine.ChatTypeDMVal:
		return true, false
	case engine.ChatTypeGroupVal, engine.ChatTypeTopicVal, engine.ChatTypeChanVal:
		return false, true
	}
	return false, false
}

// roleBadgeLabel returns the badge text for a member role ("" = none).
func roleBadgeLabel(role string) string {
	switch role {
	case "owner", "admin", "restricted", "banned":
		return role
	}
	return ""
}

// roleBadgeColor maps a badged role to its color; unbaged roles are zero.
func roleBadgeColor(role string) color.NRGBA {
	switch role {
	case "owner":
		return rgb(0xF5A623)
	case "admin":
		return rgb(0x64B5F6)
	case "restricted":
		return rgb(0xEF5350)
	case "banned":
		return rgb(0xEF5350)
	}
	return color.NRGBA{}
}

// lastSeenLabel renders a presence label from a LastSeenKind.
func lastSeenLabel(kind string) string {
	switch kind {
	case "online":
		return "online"
	case "recently":
		return "last seen recently"
	case "within_week":
		return "last seen within a week"
	case "within_month":
		return "last seen within a month"
	case "long_ago":
		return "last seen a long time ago"
	case "exact":
		return "last seen"
	case "hidden":
		return "last seen hidden"
	}
	return "offline"
}

// ── state actions ─────────────────────────────────────────────────────────

// openPanel slides the info panel in for the selected chat and loads its data.
func (a *App) openPanel() {
	a.mu.Lock()
	k := a.selected
	a.panelOpen = true
	if k != nil {
		a.panelLoaded = false
		a.panelChat = *k
	}
	a.mu.Unlock()
	if k != nil {
		go a.loadPanel(*k)
	}
	a.invalidate()
}

// closePanel slides the panel out.
func (a *App) closePanel() {
	a.mu.Lock()
	a.panelOpen = false
	a.mu.Unlock()
	a.invalidate()
}

// loadPanel fetches profile / members / shared-media for the panel (async).
func (a *App) loadPanel(k chatKey) {
	var chatType int
	var muted bool
	a.mu.Lock()
	for i := range a.chats {
		if a.chats[i].AccountID == k.AccountID && a.chats[i].ChatID == k.ChatID {
			chatType = a.chats[i].Type
			muted = a.chats[i].IsMuted
			break
		}
	}
	a.mu.Unlock()

	var prof *engine.CachedUser
	var members []engine.MemberInfo
	if showProfile, showMembers := panelSectionsFor(chatType); showProfile {
		if p, err := a.eng.GetUserProfile(k.AccountID, k.ChatID); err == nil {
			prof = p
		}
	} else if showMembers {
		if m, err := a.eng.GetChatMembers(k.AccountID, k.ChatID, 200, 0); err == nil {
			members = m
		}
	}

	counts, _ := a.eng.GetSharedMediaCounts(k.AccountID, k.ChatID)
	recent, _ := a.eng.GetSharedMedia(k.AccountID, k.ChatID, "image", 12, 0, "")

	a.mu.Lock()
	a.profile = prof
	// Fresh profile fetch doubles as the header presence refresh (slice 28).
	if prof != nil && a.selected != nil && a.selected.AccountID == k.AccountID && a.selected.ChatID == k.ChatID {
		a.hdrPresence = prof
	}
	a.members = members
	a.mediaCounts = counts
	a.panelRecent = recent
	a.panelMuted = muted
	a.panelLoaded = true
	a.mu.Unlock()
	a.invalidate()
}

// setChatMuted applies the notifications toggle for the open chat.
func (a *App) setChatMuted(k chatKey, muted bool) {
	go func() {
		if err := a.eng.MuteChat(k.AccountID, k.ChatID, muted, 0); err != nil {
			a.setToast("Notifications: " + err.Error())
		}
	}()
}

// panelBlockUser blocks/unblocks the DM peer.
func (a *App) panelBlockUser(k chatKey, block bool) {
	go func() {
		var err error
		if block {
			err = a.eng.BlockUser(k.AccountID, k.ChatID)
		} else {
			err = a.eng.UnblockUser(k.AccountID, k.ChatID)
		}
		if err != nil {
			a.setToast("Block: " + err.Error())
		}
		a.loadPanel(k)
	}()
}

// panelAddContact adds the DM peer to contacts.
func (a *App) panelAddContact(k chatKey, u engine.CachedUser) {
	go func() {
		if _, err := a.eng.AddContactByUser(k.AccountID, u.UserID, u.DisplayName, "", "", "", false); err != nil {
			a.setToast("Add contact: " + err.Error())
		}
		a.loadPanel(k)
	}()
}

// ── layout ────────────────────────────────────────────────────────────────

// layoutInfoPanel renders the panel as a full pane (narrow) or inside the
// caller-provided column (desktop side pane).
func (a *App) layoutInfoPanel(gtx layout.Context, f frame, chat *engine.ChatInfo, narrow bool) layout.Dimensions {
	if panelCloseBtn.Clicked(gtx) {
		a.closePanel()
	}

	title, sub := "Info", ""
	if chat != nil {
		title = chat.Title
		sub = a.panelSub(f, chat)
	}

	list := material.List(a.ui.Theme, &panelScroll)
	body := list.Layout(gtx, 1, func(gtx layout.Context, _ int) layout.Dimensions {
		return layout.Inset{Left: unit.Dp(14), Right: unit.Dp(14), Top: unit.Dp(8), Bottom: unit.Dp(16)}.Layout(gtx,
			func(gtx layout.Context) layout.Dimensions {
				return a.panelBody(gtx, f, chat)
			})
	})

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		// header: back (narrow) + big avatar + title + sub + close
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(8), Right: unit.Dp(8)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							if !narrow {
								return layout.Dimensions{}
							}
							btn := a.ui.IconButton(&panelCloseBtn, iconNavigationBack, "Back")
							btn.Color = a.ui.p.TextDim
							return btn.Layout(gtx)
						}),
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
										if f.cfg.Streamer {
											return a.personAvatar(gtx, unit.Dp(46))
										}
										return a.ui.Avatar(gtx, title, unit.Dp(46), dotNone)
									})
								}),
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											lbl := a.ui.H3(title)
											if f.cfg.Streamer {
												return a.masked(gtx, lbl.Layout)
											}
											return lbl.Layout(gtx)
										}),
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											if sub == "" {
												return layout.Dimensions{}
											}
											lbl := a.ui.Dim(unit.Sp(12), sub)
											return lbl.Layout(gtx)
										}),
									)
								}),
							)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							if narrow {
								return layout.Dimensions{}
							}
							btn := a.ui.IconButton(&panelCloseBtn, iconContentClear, "Close")
							btn.Color = a.ui.p.TextDim
							return btn.Layout(gtx)
						}),
					)
				})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions { return a.ui.Divider(gtx) }),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			if !f.panelLoaded {
				return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					ld := material.Loader(a.ui.Theme)
					ld.Color = a.ui.p.Accent
					return ld.Layout(gtx)
				})
			}
			return body
		}),
	)
}

// panelSub derives the header sub-line.
func (a *App) panelSub(f frame, chat *engine.ChatInfo) string {
	if f.profile != nil && chat.Type == engine.ChatTypeDMVal {
		if f.profile.IsOnline {
			return "online"
		}
		return lastSeenLabel(f.profile.LastSeenKind)
	}
	if chat.MemberCount > 0 {
		return memberCountLabel(chat)
	}
	if chat.Type == engine.ChatTypeChanVal {
		return "channel"
	}
	return platformTitle(platformOf(f, chat.AccountID))
}

// panelBody renders the panel sections.
func (a *App) panelBody(gtx layout.Context, f frame, chat *engine.ChatInfo) layout.Dimensions {
	k := *f.selected
	showProfile, showMembers := panelSectionsFor(chat.Type)
	var children []layout.FlexChild

	// Notifications toggle.
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		key := "panel:mute:" + k.ChatID
		sw := panelSwitch(key)
		if !panelSynced[key] {
			sw.Value = !f.panelMuted
			panelSynced[key] = true
		}
		prev := sw.Value
		d := a.muteRow(gtx, sw)
		if sw.Value != prev {
			a.setChatMuted(k, !sw.Value)
		}
		return d
	}))

	// Profile rows (DM).
	if showProfile && f.profile != nil {
		p := *f.profile
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.sectionTitle(gtx, "Info")
		}))
		if p.Username != "" {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.panelValueRow(gtx, iconSocialPerson, "Username", "@"+p.Username)
			}))
		}
		if p.Phone != "" {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.panelValueRow(gtx, iconCommunicationCall, "Phone", p.Phone)
			}))
		}
		if p.Bio != "" {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.panelValueRow(gtx, iconActionInfo, "Bio", p.Bio)
			}))
		}
		// Block / unblock + add contact actions.
		if panelBlockBtn.Clicked(gtx) {
			a.panelBlockUser(k, !p.IsBlocked)
		}
		if !p.IsBlocked {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.TextButton(&panelBlockBtn, "Block user")
				btn.Color = a.ui.p.Error
				return btn.Layout(gtx)
			}))
		} else {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.TextButton(&panelBlockBtn, "Unblock user")
				btn.Color = a.ui.p.Accent
				return btn.Layout(gtx)
			}))
		}
		if !p.IsContact {
			if panelAddBtn.Clicked(gtx) {
				a.panelAddContact(k, p)
			}
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.TextButton(&panelAddBtn, "Add to contacts")
				btn.Color = a.ui.p.Accent
				return btn.Layout(gtx)
			}))
		}
	}

	// Members (groups/channels), with search (AyuGram, slice 40).
	if showMembers {
		shown := filterMembers(f.members, memberSearchEd.Text())
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			n := itoa(len(f.members))
			return a.sectionTitle(gtx, "Members ("+n+")")
		}))
		if len(f.members) > 8 {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					for {
						ev, ok := memberSearchEd.Update(gtx)
						if !ok {
							break
						}
						if _, is := ev.(widget.ChangeEvent); is {
							a.invalidate()
						}
					}
					ed := a.ui.Editor(&memberSearchEd, "Search members")
					return roundedFill(gtx, a.ui.p.SurfaceHi, 8, func(gtx layout.Context) layout.Dimensions {
						return layout.UniformInset(unit.Dp(6)).Layout(gtx, ed.Layout)
					})
				})
			}))
		}
		for i := range shown {
			m := shown[i]
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.memberRow(gtx, m)
			}))
		}
		if len(shown) == 0 {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(13), "No members match")
				return lbl.Layout(gtx)
			}))
		}
	}

	// Shared media counts + recent photos.
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Shared media")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.mediaCountRow(gtx, f)
	}))
	if len(f.panelRecent) > 0 {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.recentPhotosGrid(gtx, f, chat)
		}))
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// muteRow renders the notifications toggle row.
func (a *App) muteRow(gtx layout.Context, sw *widget.Bool) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return iconSocialNotif.Layout(gtx, a.ui.p.TextDim)
			}),
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(14), "Notifications")
					return lbl.Layout(gtx)
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				sw2 := material.Switch(a.ui.Theme, sw, "")
				sw2.Color.Enabled = a.ui.p.Accent
				sw2.Color.Disabled = a.ui.p.SurfaceHi
				sw2.Color.Track = a.ui.p.SurfaceHi
				return sw2.Layout(gtx)
			}),
		)
	})
}

// panelValueRow renders an icon + label + value row.
func (a *App) panelValueRow(gtx layout.Context, ic *widget.Icon, label, value string) layout.Dimensions {
	// Copy on click (AyuGram info rows, slice 26).
	btn := panelRowClickable(label)
	if btn.Clicked(gtx) {
		if value != "" {
			gtx.Execute(clipboard.WriteCmd{
				Type: "text/plain",
				Data: io.NopCloser(strings.NewReader(value)),
			})
			a.setToast(label + " copied")
		}
	}
	return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return material.ButtonLayout(a.ui.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					gtx.Constraints.Min.X = gtx.Dp(unit.Dp(20))
					if ic == nil {
						return layout.Dimensions{Size: image.Pt(gtx.Dp(unit.Dp(20)), gtx.Dp(unit.Dp(20)))}
					}
					return ic.Layout(gtx, a.ui.p.TextDim)
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), label)
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), value)
								return lbl.Layout(gtx)
							}),
						)
					})
				}),
			)
		})
	})
}

// panelRowClickables: per-label copy clickables for info rows.
var panelRowClickables = map[string]*widget.Clickable{}

func panelRowClickable(label string) *widget.Clickable {
	if c, ok := panelRowClickables[label]; ok {
		return c
	}
	if len(panelRowClickables) > 32 {
		panelRowClickables = make(map[string]*widget.Clickable)
	}
	c := new(widget.Clickable)
	panelRowClickables[label] = c
	return c
}

// memberRow renders one member with an optional role badge.
func (a *App) memberRow(gtx layout.Context, m engine.MemberInfo) layout.Dimensions {
	name := m.DisplayName
	if name == "" {
		name = m.Username
	}
	sub := ""
	if m.IsOnline {
		sub = "online"
	} else if m.LastSeenKind != "" {
		sub = lastSeenLabel(m.LastSeenKind)
	}
	badge := roleBadgeLabel(m.CustomRank)
	if badge == "" {
		badge = roleBadgeLabel(m.Role)
	}
	badgeCol := roleBadgeColor(m.Role)
	if m.CustomRank != "" {
		badgeCol = rgb(0xF5A623)
	}
	return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return a.ui.Avatar(gtx, name, unit.Dp(32), dotNone)
				})
			}),
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(14), name)
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
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if badge == "" {
					return layout.Dimensions{}
				}
				return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return badgeChip(gtx, a.ui, badge, badgeCol)
				})
			}),
		)
	})
}

// badgeChip renders a small colored text chip (role badges).
func badgeChip(gtx layout.Context, u *UI, txt string, c color.NRGBA) layout.Dimensions {
	return roundedFill(gtx, withAlpha(c, 0x30), 6, func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(1), Bottom: unit.Dp(1), Left: unit.Dp(6), Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := u.Label(unit.Sp(10), txt)
			lbl.Color = c
			return lbl.Layout(gtx)
		})
	})
}

// withAlpha scales a color's alpha channel.
func withAlpha(c color.NRGBA, alpha uint8) color.NRGBA {
	c.A = uint8(uint32(c.A) * uint32(alpha) / 0xFF)
	return c
}

// mediaCountRow renders the shared-media count pills.
func (a *App) mediaCountRow(gtx layout.Context, f frame) layout.Dimensions {
	if len(f.mediaCounts) == 0 {
		lbl := a.ui.Dim(unit.Sp(13), "No shared media yet")
		return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, lbl.Layout)
	}
	children := make([]layout.FlexChild, 0, len(f.mediaCounts)*2)
	for i, mc := range f.mediaCounts {
		mc := mc
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if i > 0 {
				return layout.Inset{Right: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Dimensions{}
				})
			}
			return layout.Dimensions{}
		}))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Right: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return roundedFill(gtx, a.ui.p.SurfaceHi, 8, func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(8), Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(11), sharedMediaLabel(mc.MediaType)+" "+itoa(mc.Count))
						lbl.Color = a.ui.p.TextDim
						return lbl.Layout(gtx)
					})
				})
			})
		}))
	}
	return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, children...)
}

// sharedMediaLabel pluralizes a media count type for display.
func sharedMediaLabel(t string) string {
	switch t {
	case "photo":
		return "photos"
	case "video":
		return "videos"
	case "voice":
		return "voice"
	case "videonote":
		return "video messages"
	case "sticker":
		return "stickers"
	case "gif":
		return "GIFs"
	case "audio":
		return "audio"
	case "file":
		return "files"
	}
	return t
}

// photoGridClicks pools the info-panel gallery cell clickables.
var photoGridClicks []widget.Clickable

// recentPhotosGrid renders the latest shared photos as a thumbnail grid,
// reusing the media-image cache (stripped thumbs decode to valid JPEG).
// Tapping a cell opens the fullscreen media viewer at that photo (§12).
func (a *App) recentPhotosGrid(gtx layout.Context, f frame, chat *engine.ChatInfo) layout.Dimensions {
	const cols = 3
	cell := gtx.Dp(unit.Dp(84))
	growClickables(&photoGridClicks, len(f.panelRecent))
	var rows []layout.FlexChild
	for i := 0; i+0 < len(f.panelRecent); i += cols {
		end := i + cols
		if end > len(f.panelRecent) {
			end = len(f.panelRecent)
		}
		items := f.panelRecent[i:end]
		base := i
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			cells := make([]layout.FlexChild, 0, len(items))
			for j, it := range items {
				it := it
				idx := base + j
				cells = append(cells, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Right: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						gtx.Constraints.Max.X = cell
						gtx.Constraints.Max.Y = cell
						gtx.Constraints.Min = image.Pt(cell, cell)
						if btn := &photoGridClicks[idx]; btn.Clicked(gtx) {
							title := ""
							if chat != nil {
								title = chat.Title
							}
							a.openViewerAt(f.panelChat, title, "image", it.MsgID)
						}
						bl := material.ButtonLayout(a.ui.Theme, &photoGridClicks[idx])
						bl.Background = a.ui.p.Surface
						bl.CornerRadius = 4
						return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							var img *image.RGBA
							if it.ThumbB64 != "" {
								key := "thumb:" + it.ThumbB64
								if img = mediaImgs.get(key); img == nil {
									a.decodeThumbAsync(key, it.ThumbB64)
								}
							}
							if img != nil {
								return drawImageScaled(gtx, img, cell, cell, 4)
							}
							return roundedFill(gtx, a.ui.p.SurfaceHi, 4, func(gtx layout.Context) layout.Dimensions {
								return layout.Dimensions{Size: image.Pt(cell, cell)}
							})
						})
					})
				}))
			}
			return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, cells...)
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
}

// filterMembers narrows the member list by a case-insensitive substring
// match on display name, username, or id (AyuGram member search).
func filterMembers(members []engine.MemberInfo, q string) []engine.MemberInfo {
	q = strings.TrimSpace(strings.ToLower(q))
	if q == "" {
		return members
	}
	var out []engine.MemberInfo
	for _, m := range members {
		if strings.Contains(strings.ToLower(m.DisplayName), q) ||
			strings.Contains(strings.ToLower(m.Username), q) ||
			strings.Contains(m.UserID, q) {
			out = append(out, m)
		}
	}
	return out
}

// memberSearchEd filters the info panel's member list (slice 40).
var memberSearchEd widget.Editor
