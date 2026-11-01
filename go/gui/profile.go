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

func (a *App) panelSwitch(key string) *widget.Bool {
	if a.wid.panelSwitches == nil {
		a.wid.panelSwitches = make(map[string]*widget.Bool)
		a.wid.panelSynced = make(map[string]bool)
	}
	if s, ok := a.wid.panelSwitches[key]; ok {
		return s
	}
	if len(a.wid.panelSwitches) > 64 {
		a.wid.panelSwitches = make(map[string]*widget.Bool)
		a.wid.panelSynced = make(map[string]bool)
	}
	s := new(widget.Bool)
	a.wid.panelSwitches[key] = s
	return s
}

func (a *App) panelSyncedFor(key string) bool {
	return a.wid.panelSynced[key]
}

type colorNRGBA = color.NRGBA

func panelSectionsFor(chatType int) (profile, members bool) {
	switch chatType {
	case engine.ChatTypeDMVal:
		return true, false
	case engine.ChatTypeGroupVal, engine.ChatTypeTopicVal, engine.ChatTypeChanVal:
		return false, true
	}
	return false, false
}

func roleBadgeLabel(role string) string {
	switch role {
	case "owner", "admin", "restricted", "banned":
		return role
	}
	return ""
}

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

func (a *App) closePanel() {
	a.mu.Lock()
	a.panelOpen = false
	a.mu.Unlock()
	a.invalidate()
}

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
	showProfile, showMembers := panelSectionsFor(chatType)
	if showProfile {
		if p, err := a.eng.GetUserProfile(k.AccountID, k.ChatID); err == nil {
			prof = p
		}
	} else if showMembers {
		if m, err := a.eng.GetChatMembers(k.AccountID, k.ChatID, 200, 0); err == nil {
			members = m
		}
	}

	if chatType == engine.ChatTypeDMVal {
		go a.loadCommonChats(k)
	}

	var botCmds []engine.BotCommandInfo
	if prof != nil && prof.IsBot {
		if cmds, err := a.eng.GetChatBotCommands(k.AccountID, k.ChatID); err == nil {
			botCmds = cmds
		}
	}

	var music []engine.MusicTrack
	if showProfile && (prof == nil || !prof.IsBot) && a.eng.ProfileMusicSupported(k.AccountID) {
		if tracks, err := a.eng.GetProfileMusic(k.AccountID, k.ChatID); err == nil {
			music = tracks
		}
	}

	counts, _ := a.eng.GetSharedMediaCounts(k.AccountID, k.ChatID)
	photos, _ := a.eng.GetSharedMedia(k.AccountID, k.ChatID, "image", 60, 0, "")

	a.mu.Lock()
	a.profile = prof
	if prof != nil && a.selected != nil && a.selected.AccountID == k.AccountID && a.selected.ChatID == k.ChatID {
		a.hdrPresence = prof
	}
	a.members = members
	a.panelBotCmds = botCmds
	a.panelMusic = music
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

func (a *App) setChatMuted(k chatKey, muted bool) {
	go func() {
		if err := a.eng.MuteChat(k.AccountID, k.ChatID, muted, 0); err != nil {
			a.setToast("Notifications: " + err.Error())
		}
	}()
}

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

func (a *App) panelShareContact(f frame, u engine.CachedUser) {
	a.copyTextSoon(vcardFor(u))
}

func (a *App) panelAddContact(k chatKey, u engine.CachedUser) {
	go func() {
		if _, err := a.eng.AddContactByUser(k.AccountID, u.UserID, u.DisplayName, "", "", "", false); err != nil {
			a.setToast("Add contact: " + err.Error())
		}
		a.loadPanel(k)
	}()
}

func isPanelSubCount(sub string) bool {
	if sub == "channel" || sub == "online" || sub == "members" {
		return true
	}
	return strings.Contains(sub, "member") || strings.Contains(sub, "online")
}

func (a *App) layoutInfoPanel(gtx layout.Context, f frame, chat *engine.ChatInfo, narrow bool) layout.Dimensions {
	if a.wid.panelCloseBtn.Clicked(gtx) {
		a.closePanel()
	}

	title, sub := "Info", ""
	if chat != nil {
		title = chat.Title
		sub = a.panelSub(f, chat)
	}

	list := material.List(a.ui.Theme, &a.wid.panelScroll)
	body := list.Layout(gtx, 1, func(gtx layout.Context, _ int) layout.Dimensions {
		return layout.Inset{Left: unit.Dp(14), Right: unit.Dp(14), Top: unit.Dp(8), Bottom: unit.Dp(16)}.Layout(gtx,
			func(gtx layout.Context) layout.Dimensions {
				return a.panelBody(gtx, f, chat, narrow)
			})
	})

	if f.memberMenu != nil {
		a.layoutMemberMenu(gtx, f)
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(8), Right: unit.Dp(8)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									if !narrow {
										return layout.Dimensions{}
									}
									btn := a.ui.IconButton(&a.wid.panelCloseBtn, iconNavigationBack, "Back")
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
									btn := a.ui.IconButton(&a.wid.panelCloseBtn, iconContentClear, "Close")
									btn.Color = a.ui.p.TextDim
									return btn.Layout(gtx)
								}),
							)
						}),
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

func (a *App) panelBody(gtx layout.Context, f frame, chat *engine.ChatInfo, narrow bool) layout.Dimensions {
	k := *f.selected
	showProfile, showMembers := panelSectionsFor(chat.Type)
	var children []layout.FlexChild

	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		key := "panel:mute:" + k.ChatID
		sw := a.panelSwitch(key)
		if !a.wid.panelSynced[key] {
			sw.Value = !f.panelMuted
			a.wid.panelSynced[key] = true
		}
		prev := sw.Value
		d := a.muteRowWithPicker(gtx, f, k, sw)
		if sw.Value != prev {
			a.setChatMuted(k, !sw.Value)
		}
		return d
	}))

	if chat.TtlPeriod > 0 {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.panelValueRow(gtx, iconActionSchedule, "Auto-delete", ttlLabel(chat.TtlPeriod))
		}))
	}

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
		if p.IsBot {
			children = append(children, a.botPanelSections(gtx, f, p)...)
		}
		if a.wid.panelBlockBtn.Clicked(gtx) {
			a.panelBlockUser(k, !p.IsBlocked)
		}
		if !p.IsBlocked {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.TextButton(&a.wid.panelBlockBtn, "Block user")
				btn.Color = a.ui.p.Error
				return btn.Layout(gtx)
			}))
		} else {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.TextButton(&a.wid.panelBlockBtn, "Unblock user")
				btn.Color = a.ui.p.Accent
				return btn.Layout(gtx)
			}))
		}
		if a.wid.panelShareBtn.Clicked(gtx) {
			a.panelShareContact(f, p)
		}
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			btn := a.ui.TextButton(&a.wid.panelShareBtn, "Share contact")
			btn.Color = a.ui.p.Accent
			return btn.Layout(gtx)
		}))
		if !p.IsContact {
			if a.wid.panelAddBtn.Clicked(gtx) {
				a.panelAddContact(k, p)
			}
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.TextButton(&a.wid.panelAddBtn, "Add to contacts")
				btn.Color = a.ui.p.Accent
				return btn.Layout(gtx)
			}))
		}
	}

	children = append(children, a.panelMusicSection(gtx, f)...)

	if showProfile {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.layoutCommonGroups(gtx, f, k)
		}))
	}

	if showMembers {
		shown := filterMembers(f.members, a.wid.memberSearchEd.Text())
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			n := itoa(len(f.members))
			return a.sectionTitle(gtx, "Members ("+n+")")
		}))
		if len(f.members) > 8 {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					for {
						ev, ok := a.wid.memberSearchEd.Update(gtx)
						if !ok {
							break
						}
						if _, is := ev.(widget.ChangeEvent); is {
							a.invalidate()
						}
					}
					ed := a.ui.Editor(&a.wid.memberSearchEd, "Search members")
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

	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Shared media")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sharedMediaTabs(gtx, f, chat, narrow)
	}))

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func (a *App) panelValueRow(gtx layout.Context, ic *widget.Icon, label, value string) layout.Dimensions {
	btn := a.panelRowClickable(label)
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

func (a *App) panelRowClickable(label string) *widget.Clickable {
	if c, ok := a.wid.panelRowClickables[label]; ok {
		return c
	}
	if len(a.wid.panelRowClickables) > 32 {
		a.wid.panelRowClickables = make(map[string]*widget.Clickable)
	}
	c := new(widget.Clickable)
	a.wid.panelRowClickables[label] = c
	return c
}

func (a *App) memberRow(gtx layout.Context, f frame, m engine.MemberInfo) layout.Dimensions {
	if chat, ok := panelChatOf(f); ok {
		if btn := a.memberRowBtn(m.UserID); btn.Clicked(gtx) {
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

func badgeChip(gtx layout.Context, u *UI, txt string, c color.NRGBA) layout.Dimensions {
	return roundedFill(gtx, withAlpha(c, 0x30), 6, func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(1), Bottom: unit.Dp(1), Left: unit.Dp(6), Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			lbl := u.Label(unit.Sp(10), txt)
			lbl.Color = c
			return lbl.Layout(gtx)
		})
	})
}

func withAlpha(c color.NRGBA, alpha uint8) color.NRGBA {
	c.A = uint8(uint32(c.A) * uint32(alpha) / 0xFF)
	return c
}

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
		growClickables(&a.wid.botPanelCmdBtns, len(cmds))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.sectionTitle(gtx, "Commands ("+itoa(len(cmds))+")")
		}))
		for i := range cmds {
			c := cmds[i]
			cl := &a.wid.botPanelCmdBtns[i]
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
		if a.wid.botPrivacyBtn.Clicked(gtx) {
			openExternalAsync(p.BotPrivacyURL, func(err error) {
				if err != nil {
					a.setToast("Open privacy policy failed: " + err.Error())
				}
			})
		}
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.TextButton(&a.wid.botPrivacyBtn, "Privacy policy")
				btn.Color = a.ui.p.Accent
				return btn.Layout(gtx)
			})
		}))
	}
	return children
}
