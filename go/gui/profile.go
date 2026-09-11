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
	panelShareBtn widget.Clickable // Share contact (slice 83)
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

	// Groups in common (slice 107): DM peers only.
	if chatType == engine.ChatTypeDMVal {
		go a.loadCommonChats(k)
	}

	// Bot info panel (slice 133): the bot's chat commands.
	var botCmds []engine.BotCommandInfo
	if prof != nil && prof.IsBot {
		if cmds, err := a.eng.GetChatBotCommands(k.AccountID, k.ChatID); err == nil {
			botCmds = cmds
		}
	}

	counts, _ := a.eng.GetSharedMediaCounts(k.AccountID, k.ChatID)
	// Photos tab is prefetched (60 cells); other tabs lazy-load on
	// first activation (slice 78).
	photos, _ := a.eng.GetSharedMedia(k.AccountID, k.ChatID, "image", 60, 0, "")

	a.mu.Lock()
	a.profile = prof
	// Fresh profile fetch doubles as the header presence refresh (slice 28).
	if prof != nil && a.selected != nil && a.selected.AccountID == k.AccountID && a.selected.ChatID == k.ChatID {
		a.hdrPresence = prof
	}
	a.members = members
	a.panelBotCmds = botCmds
	a.mediaCounts = counts
	a.panelTab = "image"
	a.panelTabItems = map[string][]engine.SharedMediaItem{"image": photos}
	a.panelTabLoaded = map[string]bool{"image": true}
	a.panelTabPending = nil
	a.panelLinks = nil
	a.panelLinksLoaded = false
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

// vcardFor builds a minimal vCard for a contact (pure, tested) —
// AyuGram's Share copies contact data as text.
func vcardFor(u engine.CachedUser) string {
	var b strings.Builder
	b.WriteString("BEGIN:VCARD\nVERSION:3.0\n")
	if u.DisplayName != "" {
		b.WriteString("FN:" + u.DisplayName + "\n")
	}
	if u.Phone != "" {
		b.WriteString("TEL;TYPE=CELL:" + u.Phone + "\n")
	}
	if u.Username != "" {
		b.WriteString("NICKNAME:" + u.Username + "\n")
	}
	b.WriteString("END:VCARD")
	return b.String()
}

// panelShareContact copies the peer's vCard to the clipboard.
func (a *App) panelShareContact(f frame, u engine.CachedUser) {
	a.copyTextSoon(vcardFor(u))
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

// isPanelSubCount reports whether a panel subtitle is a count/channel
// label (safe under streamer mode) rather than identity info.
func isPanelSubCount(sub string) bool {
	if sub == "channel" || sub == "online" || sub == "members" {
		return true
	}
	return strings.Contains(sub, "member") || strings.Contains(sub, "online")
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
				return a.panelBody(gtx, f, chat, narrow)
			})
	})

	// Member admin menu (slice 106) renders over the panel on tap.
	if f.memberMenu != nil {
		a.layoutMemberMenu(gtx, f)
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		// header (AyuGram profile cover): back/close row, then a big centered
		// photo (96dp; real userpic via the engine avatar pipeline, letter
		// fallback), name and status below it.
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(8), Right: unit.Dp(8)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
						// back (narrow) | spacer | close (desktop)
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
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
									return layout.Dimensions{}
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
						}),
						// big cover avatar.
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									if f.cfg.Streamer {
										return a.personAvatar(gtx, unit.Dp(96))
									}
									if chat != nil && chat.AvatarPath != "" {
										return a.streamerAvatar(gtx, f, *chat, unit.Dp(96), dotNone)
									}
									return a.ui.Avatar(gtx, title, unit.Dp(96), dotNone)
								})
							})
						}),
						// name + status, centered.
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.H3(title)
								if f.cfg.Streamer {
									return a.masked(gtx, lbl.Layout)
								}
								return lbl.Layout(gtx)
							})
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							if sub == "" {
								return layout.Dimensions{}
							}
							return layout.Inset{Top: unit.Dp(1)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Dim(unit.Sp(12), sub)
									if f.cfg.Streamer && !isPanelSubCount(sub) {
										return a.masked(gtx, lbl.Layout)
									}
									return lbl.Layout(gtx)
								})
							})
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
func (a *App) panelBody(gtx layout.Context, f frame, chat *engine.ChatInfo, narrow bool) layout.Dimensions {
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

	// Auto-delete period (AyuGram profile info, slice 60).
	if chat.TtlPeriod > 0 {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.panelValueRow(gtx, iconActionSchedule, "Auto-delete", ttlLabel(chat.TtlPeriod))
		}))
	}

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
		// Bot info sections (slice 133, tdesktop bot profile): description,
		// commands (tap inserts into the composer), privacy-policy link.
		if p.IsBot {
			children = append(children, a.botPanelSections(gtx, f, p)...)
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
		if panelShareBtn.Clicked(gtx) {
			a.panelShareContact(f, p)
		}
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			btn := a.ui.TextButton(&panelShareBtn, "Share contact")
			btn.Color = a.ui.p.Accent
			return btn.Layout(gtx)
		}))
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

	// Groups in common (slice 107): DM profiles, hidden when empty.
	if showProfile {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.layoutCommonGroups(gtx, f, k)
		}))
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
				return a.memberRow(gtx, f, m)
			}))
		}
		if len(shown) == 0 {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(13), "No members match")
				return lbl.Layout(gtx)
			}))
		}
	}

	// Shared media tabs (slice 78): chip bar + tabbed grids / lists.
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Shared media")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sharedMediaTabs(gtx, f, chat, narrow)
	}))

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

// memberRow renders one member with an optional role badge. Tapping opens
// the member admin menu (slice 106) when the viewer has admin rights.
func (a *App) memberRow(gtx layout.Context, f frame, m engine.MemberInfo) layout.Dimensions {
	if chat, ok := panelChatOf(f); ok {
		if btn := memberRowBtn(m.UserID); btn.Clicked(gtx) {
			a.openMemberMenu(chat, m, image.Pt(gtx.Constraints.Max.X, 0))
		}
	}
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

// photoGridClicks pools the info-panel gallery cell clickables.
var photoGridClicks []widget.Clickable

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

// botPanelCmdClickables pools the command-row clickables.
var botPanelCmdBtns []widget.Clickable

// botPrivacyBtn opens the bot's privacy policy.
var botPrivacyBtn widget.Clickable

// botPanelSections builds the bot-only profile sections: "What can this
// bot do?" description, the command list (tap → composer insert, the
// slice-76 wire), and the privacy-policy row (browser handoff).
func (a *App) botPanelSections(gtx layout.Context, f frame, p engine.CachedUser) []layout.FlexChild {
	var children []layout.FlexChild
	if p.BotDescription != "" {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.sectionTitle(gtx, "What can this bot do?")
		}))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(13), p.BotDescription)
				lbl.Color = a.ui.p.Text
				return lbl.Layout(gtx)
			})
		}))
	}
	cmds := f.panelBotCmds
	if len(cmds) > 0 {
		growClickables(&botPanelCmdBtns, len(cmds))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.sectionTitle(gtx, "Commands ("+itoa(len(cmds))+")")
		}))
		for i := range cmds {
			c := cmds[i]
			cl := &botPanelCmdBtns[i]
			if cl.Clicked(gtx) {
				a.insertBotCommand(c.Command)
				a.closePanel()
				return nil
			}
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					btn := material.Button(a.ui.Theme, cl, botCmdTitle(c))
					btn.CornerRadius = 8
					btn.Inset = layout.UniformInset(unit.Dp(7))
					btn.TextSize = unit.Sp(13)
					btn.Background = a.ui.p.SurfaceHi
					btn.Color = a.ui.p.Accent
					return btn.Layout(gtx)
				})
			}))
		}
	}
	if p.BotPrivacyURL != "" {
		if botPrivacyBtn.Clicked(gtx) {
			openExternalAsync(p.BotPrivacyURL, func(err error) {
				if err != nil {
					a.setToast("Open privacy policy failed: " + err.Error())
				}
			})
		}
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.TextButton(&botPrivacyBtn, "Privacy policy")
				btn.Color = a.ui.p.Accent
				return btn.Layout(gtx)
			})
		}))
	}
	return children
}
