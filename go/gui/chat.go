package gui

import (
	"image"
	"image/color"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"gioui.org/f32"
	"gioui.org/font"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

func (a *App) layoutChatView(gtx layout.Context, f frame, narrow bool) layout.Dimensions {
	if f.selected == nil {
		return a.layoutEmptyState(gtx)
	}
	if len(f.fwd) > 0 {
		return a.layoutForwardDialog(gtx, f)
	}
	chat := findChat(f, *f.selected)

	if f.panelOpen && narrow {
		return a.layoutInfoPanel(gtx, f, chat, true)
	}

	if f.schedPanel {
		return a.layoutSchedPanel(gtx, f, chat)
	}

	if f.adminPanel {
		return a.layoutAdminPanel(gtx, f, chat)
	}

	if f.statsPanel {
		return a.layoutStatsPanel(gtx, f, chat)
	}

	if f.boostPanel {
		return a.layoutBoostPanel(gtx, f, chat)
	}

	a.processPaneEvents(gtx, f)

	chatPane := func(gtx layout.Context) layout.Dimensions {
		return a.chatPaneColumn(gtx, f, chat, narrow)
	}
	if f.savedListOpen && f.selected != nil {
		return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
			layout.Flexed(1, chatPane),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.ui.DividerV(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				gtx.Constraints.Max.X = gtx.Dp(unit.Dp(280))
				gtx.Constraints.Min.X = gtx.Dp(unit.Dp(280))
				return a.layoutSavedListsPane(gtx, f)
			}),
		)
	}
	if f.panelOpen {
		return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
			layout.Flexed(1, chatPane),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.ui.DividerV(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				gtx.Constraints.Max.X = gtx.Dp(unit.Dp(320))
				gtx.Constraints.Min.X = gtx.Dp(unit.Dp(320))
				return a.layoutInfoPanel(gtx, f, chat, false)
			}),
		)
	}
	return chatPane(gtx)
}

func (a *App) chatPaneColumn(gtx layout.Context, f frame, chat *engine.ChatInfo, narrow bool) layout.Dimensions {
	dims := layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			d := a.chatHeader(gtx, f, chat, narrow)
			a.headerH = d.Size.Y
			return d
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			d := a.ui.Divider(gtx)
			a.listTop = a.headerH + d.Size.Y
			return d
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if chat == nil || !chat.IsForum {
				return layout.Dimensions{}
			}
			d := a.layoutTopicTabs(gtx, f, chat)
			a.listTop += d.Size.Y
			return d
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if chat == nil || !chat.IsForum || f.forumTopic == "" {
				return layout.Dimensions{}
			}
			d := a.topicBar(gtx, f)
			a.listTop += d.Size.Y
			return d
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if f.threadScope == nil {
				return layout.Dimensions{}
			}
			d := a.layoutCommentsBar(gtx, f)
			a.listTop += d.Size.Y
			return d
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if f.savedScope == nil {
				return layout.Dimensions{}
			}
			d := a.layoutSavedScopeBar(gtx, f)
			a.listTop += d.Size.Y
			return d
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if chat == nil {
				return layout.Dimensions{}
			}
			if !chat.HasActiveCall && !voiceRoomChat(*chat, f.hdrCaps) {
				return layout.Dimensions{}
			}
			d := a.callBar(gtx, f, chat)
			a.listTop += d.Size.Y
			return d
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if f.selOn {
				d := a.layoutSelBar(gtx, f)
				a.listTop += d.Size.Y
				return d
			}
			d := a.pinnedBar(gtx, f)
			a.listTop += d.Size.Y
			return d
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if !f.inSearch || f.selected == nil {
				return layout.Dimensions{}
			}
			d := a.layoutInChatSearch(gtx, f, *f.selected)
			a.listTop += d.Size.Y
			return d
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if f.selected == nil || !chatTranslateOn(f, f.selected) {
				return layout.Dimensions{}
			}
			d := a.layoutTranslateBar(gtx, f, *f.selected)
			a.listTop += d.Size.Y
			return d
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if chat == nil || !chat.IsBot || len(f.sponsored) == 0 {
				return layout.Dimensions{}
			}
			d := a.layoutSponsoredBar(gtx, f)
			a.listTop += d.Size.Y
			return d
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			if chat != nil && chat.IsForum && f.forumTopic == "" {
				return a.topicListPane(gtx, f, chat)
			}
			return a.messageList(gtx, f, chat)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.ui.Divider(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if chat != nil && chat.IsForum && f.forumTopic == "" {
				return layout.Dimensions{}
			}
			kbd, singleUse, _, src := activeReplyKbd(f.messages)
			a.replyKbdSingleUse = singleUse
			return a.layoutReplyKeyboard(gtx, f, kbd, src)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if chat != nil && chat.IsForum && f.forumTopic == "" {
				return layout.Dimensions{}
			}
			if chat != nil && chat.NotJoined {
				return a.joinBar(gtx, f, chat)
			}
			if chat != nil {
				if on, label := composerRestricted(*chat); on {
					return a.restrictedBar(gtx, label)
				}
			}
			if a.voiceRecActive() {
				return a.voiceRecPanel(gtx, f, chat)
			}
			return a.composerBar(gtx, f, chat)
		}),
	)

	if f.menu != nil {
		a.layoutContextMenu(gtx, f)
	}
	if f.mediaConfirm {
		a.layoutMediaConfirm(gtx)
	}
	if f.forumDlg != nil {
		a.layoutForumDialog(gtx, f)
	}
	if f.headerMenu != nil {
		a.layoutHeaderMenu(gtx, f)
	}
	if f.attachMenuOpen {
		a.layoutAttachMenu(gtx, f)
	}
	if f.emojiOpen {
		a.layoutEmojiPanel(gtx, f)
	}
	if f.botCmdsOn {
		a.layoutBotCmdsPanel(gtx, f)
	}
	a.layoutInlineResults(gtx, f)
	a.layoutEmojiAutocomplete(gtx, f)
	if f.delDlg != nil {
		a.layoutDeleteDialog(gtx, f)
	}
	if f.reportDlg != nil {
		a.layoutReportDialog(gtx, f)
	}
	if f.sponsoredDlg != nil {
		a.layoutSponsoredDialog(gtx, f)
	}
	if f.sendAsDlg {
		a.layoutSendAsDialog(gtx, f)
	}
	if f.paidDlg != nil {
		a.layoutPaidConfirm(gtx, f)
	}
	if f.schedDlg != nil {
		a.layoutScheduleDialog(gtx, f)
	}
	if f.pollDlg != nil {
		a.layoutPollDialog(gtx, f)
	}
	if f.reactors != nil {
		a.layoutReactorsDialog(gtx, f)
	}
	if f.shadowDlg != nil {
		a.layoutShadowDialog(gtx, f)
	}
	if f.editHistDlg != nil {
		a.layoutEditHistDialog(gtx, f)
	}
	if f.deletedDlg != nil {
		a.layoutDeletedDialog(gtx, f)
	}
	if f.seenDlg != nil {
		a.layoutSeenByDialog(gtx, f)
	}
	if f.msgDetailDlg != nil {
		a.layoutMsgDetail(gtx, f)
	}
	if f.stickerSetDlg != nil {
		a.layoutStickerSetDialog(gtx, f)
	}
	return dims
}

func findChat(f frame, k chatKey) *engine.ChatInfo {
	for i := range f.chats {
		if f.chats[i].AccountID == k.AccountID && f.chats[i].ChatID == k.ChatID {
			c := f.chats[i]
			return &c
		}
	}
	return nil
}

func (a *App) chatHeader(gtx layout.Context, f frame, chat *engine.ChatInfo, narrow bool) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6), Left: unit.Dp(8), Right: unit.Dp(12)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				backIf(narrow, gtx, a),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					title := "Chat"
					if chat != nil {
						title = chat.Title
					}
					return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						if chat != nil {
							return a.streamerAvatar(gtx, f, *chat, unit.Dp(40), dotNone)
						}
						return a.ui.Avatar(gtx, title, unit.Dp(40), dotNone)
					})
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					title, sub := "Chat", ""
					online := false
					var badges []hdrBadge
					if chat != nil {
						title = chat.Title
						badges = headerBadges(*chat)
						if a.stillTyping(*f.selected) {
							sub = "typing…"
						} else if chat.Type == engine.ChatTypeDMVal && f.hdrPresence != nil {
							sub, online = presenceSubtitle(f.hdrPresence)
						} else if chat.MemberCount > 0 {
							sub = memberCountLabel(chat)
						} else if chat.Type == engine.ChatTypeChanVal {
							sub = "channel"
						} else {
							sub = platformTitle(platformOf(f, chat.AccountID))
						}
					}
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.H3(title)
									if f.cfg.Streamer {
										return a.masked(gtx, lbl.Layout)
									}
									return lbl.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return a.layoutHeaderBadges(gtx, badges)
								}),
							)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(12), sub)
							if online || sub == "typing…" {
								lbl.Color = a.ui.p.Accent
								return lbl.Layout(gtx)
							}
							if f.cfg.Streamer {
								return a.masked(gtx, lbl.Layout)
							}
							return lbl.Layout(gtx)
						}),
					)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					acc := accountByID(f, chat.AccountID)
					dot := connDotFor(acc)
					return statusChip(gtx, a.ui, dot)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					voice, _ := false, false
					if chat != nil {
						voice, _ = dmCallButtons(*chat, f.hdrCaps)
					}
					if !voice {
						return layout.Dimensions{}
					}
					if a.wid.headerVoiceCallBtn.Clicked(gtx) {
						c := *chat
						a.startDMCall(c, false)
					}
					return layout.Inset{Left: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.IconButton(&a.wid.headerVoiceCallBtn, iconCommunicationCall, "Voice call")
						btn.Color = a.ui.p.TextDim
						return btn.Layout(gtx)
					})
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					video := false
					if chat != nil {
						_, video = dmCallButtons(*chat, f.hdrCaps)
					}
					if !video {
						return layout.Dimensions{}
					}
					if a.wid.headerVideoCallBtn.Clicked(gtx) {
						c := *chat
						a.startDMCall(c, true)
					}
					return layout.Inset{Left: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.IconButton(&a.wid.headerVideoCallBtn, iconAVVideocam, "Video call")
						btn.Color = a.ui.p.TextDim
						return btn.Layout(gtx)
					})
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if chat == nil || f.selected == nil || !isSavedMessagesChat(chat.AccountID, chat.ChatID, f.savedMsgChats) {
						return layout.Dimensions{}
					}
					return a.savedHeaderBtn(gtx, f, *f.selected)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if a.wid.headerSearchBtn.Clicked(gtx) {
						a.toggleInChatSearch()
					}
					btn := a.ui.IconButton(&a.wid.headerSearchBtn, iconActionSearch, "Search in chat")
					btn.Color = a.ui.p.TextDim
					if f.inSearch {
						btn.Color = a.ui.p.Accent
					}
					return btn.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if a.wid.panelInfoBtn.Clicked(gtx) {
						if f.panelOpen {
							a.closePanel()
						} else {
							a.openPanel()
						}
					}
					btn := a.ui.IconButton(&a.wid.panelInfoBtn, iconActionInfo, "Chat info")
					btn.Color = a.ui.p.TextDim
					return btn.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if a.wid.headerMoreBtn.Clicked(gtx) {
						if chat != nil {
							c := *chat
							a.openHeaderMenu(c, image.Pt(gtx.Constraints.Max.X, a.headerH))
						}
					}
					return layout.Inset{Left: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.IconButton(&a.wid.headerMoreBtn, iconNavMoreVert, "Chat menu")
						btn.Color = a.ui.p.TextDim
						return btn.Layout(gtx)
					})
				}),
			)
		},
	)
}

func backIf(narrow bool, gtx layout.Context, a *App) layout.FlexChild {
	if !narrow {
		return layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Dimensions{}
		})
	}
	if a.wid.chatBackBtn.Clicked(gtx) {
		a.mu.Lock()
		prev := a.selected
		a.selected = nil
		a.msgFor = nil
		a.mu.Unlock()
		if prev != nil {
			a.flushDraft(*prev)
		}
		a.invalidate()
	}
	return layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			btn := a.ui.IconButton(&a.wid.chatBackBtn, iconNavigationBack, "Back")
			btn.Color = a.ui.p.TextDim
			return btn.Layout(gtx)
		})
	})
}

func memberCountLabel(c *engine.ChatInfo) string {
	n := c.MemberCount
	suffix := " members"
	if c.Type == engine.ChatTypeChanVal {
		suffix = " subscribers"
	}
	if n == 1 {
		suffix = strings.TrimSuffix(suffix, "s")
	}
	return itoa(n) + suffix
}

func platformOf(f frame, accountID string) string {
	for _, acc := range f.accounts {
		if acc.ID == accountID {
			return acc.Platform
		}
	}
	return ""
}

func accountByID(f frame, id string) engine.AccountInfo {
	for _, acc := range f.accounts {
		if acc.ID == id {
			return acc
		}
	}
	return engine.AccountInfo{}
}

func statusChip(gtx layout.Context, u *UI, dot connDot) layout.Dimensions {
	return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		d := gtx.Dp(unit.Dp(10))
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				paint.FillShape(gtx.Ops, dot.color(),
					clip.Ellipse{Min: image.Pt(0, 0), Max: image.Pt(d, d)}.Op(gtx.Ops))
				return layout.Dimensions{Size: image.Pt(d, d)}
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := u.Dim(unit.Sp(11), dotLabel(dot))
					return lbl.Layout(gtx)
				})
			}),
		)
	})
}

func dotLabel(d connDot) string {
	switch d {
	case dotOnline:
		return "online"
	case dotConnecting:
		return "connecting"
	case dotError:
		return "error"
	default:
		return "offline"
	}
}

func (a *App) messageList(gtx layout.Context, f frame, chat *engine.ChatInfo) layout.Dimensions {
	a.msgFrameLastOwn = lastOwnMsgID(f.messages)

	if chat != nil {
		if !a.wallpaperBackground(gtx, *chat, f) {
			a.chatThemeBackground(gtx, *chat, f)
		}
	}

	if a.stillTyping(*f.selected) || f.sending || dlActive(f.downloads) {
		gtx.Execute(op.InvalidateCmd{At: time.Now().Add(200 * time.Millisecond)})
	}

	rows := appendSponsoredRows(buildChatRows(f.messages, f.unreadSepMsgID), chat, f.forumTopic, f.sponsored)
	simKey := ""
	if f.selected != nil {
		simKey = f.selected.AccountID + "|" + f.selected.ChatID
	}
	simCollapsed := !similarEffectiveExpanded(a.similarExpanded, simKey, similarExpandedDefault(f.cfg.AyuCollapseSimilar))
	rows = appendSimilarRow(rows, chat, f.forumTopic, len(f.similar), f.cfg.AyuHideSimilar, simCollapsed)

	if f.loadingMsgs {
		return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					ld := material.Loader(a.ui.Theme)
					ld.Color = a.ui.p.Accent
					return ld.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(13), "Loading messages…")
						return lbl.Layout(gtx)
					})
				}),
			)
		})
	}

	if len(f.messages) == 0 {
		return a.emptyIntro(gtx, f)
	}

	a.rowBounds = make(map[int]image.Rectangle, len(rows))
	paneW := gtx.Constraints.Max.X
	y := -a.wid.msgList.Position.Offset

	list := material.List(a.ui.Theme, &a.wid.msgList)
	dims := list.Layout(gtx, len(rows), func(gtx layout.Context, i int) layout.Dimensions {
		r := rows[i]
		var d layout.Dimensions
		switch {
		case r.unread:
			d = a.unreadDivider(gtx)
		case r.day != "":
			d = a.dayDivider(gtx, r.day)
		case r.spHead:
			d = a.sponsoredHeaderRow(gtx, f)
		case r.spIdx > 0:
			d = a.sponsoredAdRow(gtx, f, r.spIdx)
		case r.simBlock:
			d = a.layoutSimilarBlock(gtx, f)
		case r.simCollapsed:
			d = a.layoutSimilarCollapsed(gtx, f)
		case r.album != nil:
			d = a.albumRow(gtx, f, f.messages, r.album)
		default:
			d = a.messageRow(gtx, f, &f.messages[r.msgIdx])
		}
		if r.msgIdx >= 0 {
			a.rowBounds[r.msgIdx] = image.Rectangle{Min: image.Pt(0, a.listTop+y), Max: image.Pt(paneW, a.listTop+y+d.Size.Y)}
		}
		y += d.Size.Y
		return d
	})

	if f.selOn {
		a.rubberBandOverlay(gtx, f, dims.Size)
	}

	if a.wid.msgList.Position.First == 0 && a.wid.msgList.Position.Offset <= 64 &&
		!f.loadingOlder && len(f.messages) > 0 && a.olderExhaustedLocked() == false {
		a.loadOlder()
	}
	return dims
}

func (a *App) olderExhaustedLocked() bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.olderDone
}

func (a *App) dayDivider(gtx layout.Context, day string) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(10), Bottom: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3), Left: unit.Dp(10), Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(11), day)
					return lbl.Layout(gtx)
				})
			})
		})
	})
}

func (a *App) messageRow(gtx layout.Context, f frame, m *engine.CachedMessage) layout.Dimensions {
	if m.IsService {
		if g := parseGift(m); giftBubbleVisible(g) {
			return a.layoutGiftBubble(gtx, m, g)
		}
		return a.serviceRow(gtx, m)
	}
	out := m.IsOutgoing

	text := m.ContentText
	if f.cfg.AyuFilterZalgo {
		text = ayuFilterText(text, true)
	}
	deleted := m.IsDeleted
	if deleted {
		text = deletedMarkText(text, f.cfg.AyuDeletedMark)
	}

	maxW := int(float64(gtx.Constraints.Max.X) * a.ui.wideMultiplier())
	pad := gtx.Constraints.Max.X - maxW

	if isBareStickerMsg(m) {
		bubble := func(gtx layout.Context) layout.Dimensions {
			return a.bareStickerBubble(gtx, f, m, out, deleted)
		}
		if out {
			return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(pad)}.Layout(gtx, bubble)
		}
		return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Right: unit.Dp(pad)}.Layout(gtx, bubble)
	}

	bubble := func(gtx layout.Context) layout.Dimensions {
		bg := a.ui.p.BubbleIn
		if out {
			bg = a.chatOutgoingBubble(chatOf(f, *m), f)
		}
		if deleted {
			bg = deletedFade(bg, true)
		}
		return roundedFill(gtx, bg, unit.Dp(a.ui.bubbleRadius()), func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if m.ForwardFrom == "" {
							return layout.Dimensions{}
						}
						lbl := a.ui.Dim(unit.Sp(12), "Forwarded from "+m.ForwardFrom)
						if f.cfg.Streamer {
							return a.masked(gtx, lbl.Layout)
						}
						return layout.Inset{Bottom: unit.Dp(3)}.Layout(gtx, lbl.Layout)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.pollBlock(gtx, m)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.webPageBlock(gtx, m)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if p, ok := paidBubbleWall(m); ok {
							return a.layoutPaidMediaWall(gtx, m, p)
						}
						if !m.HasMedia || m.MediaType == 0 || parseWebPage(m) != nil {
							return layout.Dimensions{}
						}
						return a.mediaBlock(gtx, f, m)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if m.ReplyPreview == "" {
							return layout.Dimensions{}
						}
						return a.replyQuote(gtx, f, *m, *f.msgFor)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if out || m.SenderName == "" || m.IsService {
							return layout.Dimensions{}
						}
						lbl := a.ui.Label(unit.Sp(13), ayuFilterText(senderTitle(*m), f.cfg.AyuFilterZalgo))
						senderCol := senderColorFor(m.SenderColorID, m.SenderID)
						if deleted {
							senderCol = deletedFade(senderCol, true)
						}
						lbl.Color = senderCol
						lbl.Font.Weight = font.SemiBold
						if f.cfg.Streamer {
							return a.masked(gtx, lbl.Layout)
						}
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if text == "" || pollIsBody(m) {
							return layout.Dimensions{}
						}
						body := *m
						body.ContentText = text
						bgCol := a.ui.p.BubbleIn
						if out {
							bgCol = a.chatOutgoingBubble(chatOf(f, *m), f)
						}
						if deleted {
							bgCol = deletedFade(bgCol, true)
						}
						baseCol := a.ui.p.TextDim
						if out {
							baseCol = a.ui.p.Text
						}
						if deleted {
							baseCol = deletedFade(baseCol, true)
						}
						return a.richTextLabel(gtx, body, unit.Sp(15), baseCol, bgCol, true)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if chatTranslateOn(f, &chatKey{AccountID: m.AccountID, ChatID: m.ChatID}) {
							a.ensureAutoTranslation(m)
						}
						return a.translationBlock(gtx, m)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.layoutInlineKeyboard(gtx, m)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if len(m.Reactions) == 0 {
							return layout.Dimensions{}
						}
						if chat := chatOf(f, *m); !reactionsVisible(chat, f.cfg) {
							return layout.Dimensions{}
						}
						return a.reactionStrip(gtx, f, m)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						msgTTL, _ := parseTTLExtras(m)
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return a.layoutTTLTimer(gtx, msgTTL)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return a.commentsChip(gtx, f, *m)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								if m.Views <= 0 {
									return layout.Dimensions{}
								}
								return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											return iconActionViews.Layout(gtx, a.ui.p.TextFaint)
										}),
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											lbl := a.ui.Dim(unit.Sp(10), viewsCountLabel(m.Views))
											return layout.Inset{Left: unit.Dp(2)}.Layout(gtx, lbl.Layout)
										}),
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											if m.Forwards <= 0 {
												return layout.Dimensions{}
											}
											lbl := a.ui.Dim(unit.Sp(10), viewsCountLabel(m.Forwards))
											return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, lbl.Layout)
										}),
									)
								})
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								meta := messageMetaLabel(*m, f.cfg.AyuEditedMark)
								lbl := a.ui.Dim(unit.Sp(10), meta)
								lbl.Color = a.ui.p.TextFaint
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								if !out {
									return layout.Dimensions{}
								}
								return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return a.statusTicks(gtx, m.Status, f)
								})
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						chat := chatOf(f, *m)
						if !seenInlineGate(*m, chat.Type, m.MsgID == a.msgFrameLastOwn) {
							return layout.Dimensions{}
						}
						a.ensureSeenInline(m)
						return a.layoutSeenInline(gtx, f, m)
					}),
				)
			})
		})
	}

	if f.selOn {
		circle := func(gtx layout.Context) layout.Dimensions {
			return a.selectionCircle(gtx, f.sel[m.MsgID])
		}
		align := layout.Start
		row := func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: align}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(8), Right: unit.Dp(6)}.Layout(gtx, circle)
				}),
				layout.Rigid(bubble),
			)
		}
		if out {
			return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(pad)}.Layout(gtx, row)
		}
		return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Right: unit.Dp(pad)}.Layout(gtx, row)
	}
	if out {
		a.loadFavoriteReaction(m.AccountID)
		return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(pad)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return a.cornerButtonsOverlay(gtx, f, m, false, bubble)
		})
	}
	canReply := cornerReplyCanSend(f, m)
	a.loadFavoriteReaction(m.AccountID)
	row := func(gtx layout.Context) layout.Dimensions {
		return a.cornerButtonsOverlay(gtx, f, m, canReply, bubble)
	}
	return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Right: unit.Dp(pad)}.Layout(gtx, row)
}

func (a *App) replyQuote(gtx layout.Context, f frame, m engine.CachedMessage, k chatKey) layout.Dimensions {
	sender, body := m.ReplyPreview, m.ReplyPreview
	if i := strings.IndexByte(m.ReplyPreview, '\n'); i >= 0 {
		sender, body = m.ReplyPreview[:i], m.ReplyPreview[i+1:]
	}
	btn := a.replyQuoteClickable(k.String() + "/" + m.MsgID)
	if btn.Clicked(gtx) && m.ReplyToID != "" {
		a.jumpToMessageAt(m.ReplyToID, m.Timestamp)
	}
	return layout.Inset{Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return material.ButtonLayout(a.ui.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return roundedFill(gtx, a.ui.p.SurfaceHi, 8, func(gtx layout.Context) layout.Dimensions {
				gtx.Constraints.Max.X = gtx.Dp(unit.Dp(240))
				return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4), Left: unit.Dp(8), Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					var children []layout.FlexChild
					if sender != "" {
						children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(12), sender)
							lbl.Color = a.ui.p.Accent
							lbl.MaxLines = 1
							if f.cfg.Streamer {
								return a.masked(gtx, lbl.Layout)
							}
							return lbl.Layout(gtx)
						}))
					}
					children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(12), quotePreview(body, 80))
						lbl.MaxLines = 1
						return lbl.Layout(gtx)
					}))
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
				})
			})
		})
	})
}

func (a *App) replyQuoteClickable(msgID string) *widget.Clickable {
	if c, ok := a.wid.replyQuoteClicks[msgID]; ok {
		return c
	}
	if len(a.wid.replyQuoteClicks) > 512 {
		a.wid.replyQuoteClicks = make(map[string]*widget.Clickable)
	}
	c := new(widget.Clickable)
	a.wid.replyQuoteClicks[msgID] = c
	return c
}

func (a *App) reactionClickable(key string) *widget.Clickable {
	if c, ok := a.wid.reactionClicks[key]; ok {
		return c
	}
	if len(a.wid.reactionClicks) > 512 {
		a.wid.reactionClicks = make(map[string]*widget.Clickable)
	}
	c := new(widget.Clickable)
	a.wid.reactionClicks[key] = c
	return c
}

func (a *App) reactionStrip(gtx layout.Context, f frame, m *engine.CachedMessage) layout.Dimensions {
	canReact := actionsFor(m, f.menuCaps).React
	if want := customWantDocs(m.Reactions); len(want) > 0 {
		a.noteCustomThumbs(m.AccountID, want)
	}
	children := make([]layout.FlexChild, 0, len(m.Reactions))
	for i := range m.Reactions {
		r := m.Reactions[i]
		if r.Emoji == "" && r.DocumentID == 0 {
			continue
		}
		emoji, docID, count, byMe := r.Emoji, r.DocumentID, r.Count, r.ByMe
		react := emoji
		if emoji == "" {
			react = customReactionKey(docID)
		}
		key := m.MsgID + "|" + react
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			btn := a.reactionClickable(key)
			if canReact && btn.Clicked(gtx) {
				msg := *m
				go func() {
					if err := a.eng.ReactToMessage(msg.AccountID, msg.ChatID, msg.MsgID, react); err != nil {
						a.setToast("React failed: " + err.Error())
					}
				}()
			}
			bg := a.ui.p.SurfaceHi
			fg := a.ui.p.TextDim
			if byMe {
				bg = a.ui.p.AccentDim
				fg = a.ui.p.Text
			}
			return layout.Inset{Top: unit.Dp(4), Right: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return roundedFill(gtx, bg, 10, func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(6), Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								if emoji != "" {
									lbl := a.ui.Label(unit.Sp(13), emoji)
									return lbl.Layout(gtx)
								}
								return a.customReactionGlyph(gtx, m.AccountID, docID)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), itoa(count))
								lbl.Color = fg
								return layout.Inset{Left: unit.Dp(3)}.Layout(gtx, lbl.Layout)
							}),
						)
					})
				})
			})
		}))
	}
	if len(children) == 0 {
		return layout.Dimensions{}
	}
	return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, children...)
}

type tickKind int

const (
	tickSending tickKind = iota
	tickSent
	tickDelivered
	tickRead
	tickFailed
)

func statusTickKind(s int) tickKind {
	switch s {
	case engine.MsgStatusSending:
		return tickSending
	case engine.MsgStatusSent:
		return tickSent
	case engine.MsgStatusDelivered:
		return tickDelivered
	case engine.MsgStatusRead:
		return tickRead
	case engine.MsgStatusFailed:
		return tickFailed
	default:
		return tickSending
	}
}

func (a *App) statusTicks(gtx layout.Context, status int, f frame) layout.Dimensions {
	_ = f
	d := gtx.Dp(unit.Dp(12))
	switch statusTickKind(status) {
	case tickSending:
		ld := material.Loader(a.ui.Theme)
		ld.Color = a.ui.p.TextFaint
		gtx.Constraints.Max = image.Pt(gtx.Dp(unit.Dp(14)), gtx.Dp(unit.Dp(14)))
		return ld.Layout(gtx)
	case tickSent:
		return check(gtx, a.ui.p.TextDim, d, 0)
	case tickDelivered:
		return doubleCheck(gtx, a.ui.p.TextDim, d)
	case tickRead:
		return doubleCheck(gtx, a.ui.p.Accent, d)
	case tickFailed:
		return alertMark(gtx, a.ui.p.Error, d)
	}
	return layout.Dimensions{}
}

func doubleCheck(gtx layout.Context, c color.NRGBA, d int) layout.Dimensions {
	return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions { return check(gtx, c, d, 0) }),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions { return check(gtx, c, d, -gtx.Dp(unit.Dp(5))) }),
	)
}

func alertMark(gtx layout.Context, c color.NRGBA, d int) layout.Dimensions {
	s := float32(d)
	var p clip.Path
	p.Begin(gtx.Ops)
	p.MoveTo(f32.Pt(s/2, s*0.12))
	p.LineTo(f32.Pt(s/2, s*0.62))
	bar := clip.Stroke{Path: p.End(), Width: float32(gtx.Dp(unit.Dp(2)))}.Op().Push(gtx.Ops)
	paint.Fill(gtx.Ops, c)
	bar.Pop()
	r := gtx.Dp(unit.Dp(1.5))
	cx, cy := int(s/2), int(s*0.82)
	dot := clip.Ellipse(image.Rect(cx-r, cy-r, cx+r, cy+r)).Push(gtx.Ops)
	paint.Fill(gtx.Ops, c)
	dot.Pop()
	return layout.Dimensions{Size: image.Pt(d, d)}
}

func check(gtx layout.Context, c color.NRGBA, size int, dx int) layout.Dimensions {
	s := float32(size)
	x1 := float32(size)/4 + float32(dx)
	y1 := s * 0.55
	x2 := float32(size)/2 + float32(dx)
	y2 := s * 0.8
	x3 := s*0.85 + float32(dx)
	y3 := s * 0.25
	var p clip.Path
	p.Begin(gtx.Ops)
	p.MoveTo(f32.Pt(x1, y1))
	p.LineTo(f32.Pt(x2, y2))
	p.LineTo(f32.Pt(x3, y3))
	stroke := clip.Stroke{Path: p.End(), Width: float32(gtx.Dp(unit.Dp(1)))}
	stack := stroke.Op().Push(gtx.Ops)
	paint.Fill(gtx.Ops, c)
	stack.Pop()
	return layout.Dimensions{Size: image.Pt(size, size)}
}

func (a *App) joinBar(gtx layout.Context, f frame, chat *engine.ChatInfo) layout.Dimensions {
	if a.wid.joinBarBtn.Clicked(gtx) {
		acc, id := chat.AccountID, chat.ChatID
		title := chat.Title
		go func() {
			if err := a.eng.JoinChannel(acc, id); err != nil {
				a.setToast("Join failed: " + err.Error())
				return
			}
			a.setToast("Joined " + title)
			a.refreshChats()
		}()
	}
	return layout.Inset{Top: unit.Dp(10), Bottom: unit.Dp(10), Left: unit.Dp(16), Right: unit.Dp(16)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(13), "You are previewing this channel")
					return lbl.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.PrimaryButton(&a.wid.joinBarBtn, "JOIN")
					return btn.Layout(gtx)
				}),
			)
		})
}

var composerSubmitKeyTag = new(struct{})

func (a *App) trySubmitComposer(f frame, chat *engine.ChatInfo) bool {
	txt := strings.TrimSpace(a.wid.composer.Text())
	if txt == "" || f.sending {
		return false
	}
	if composerOverLimit(a.wid.composer.Text()) {
		a.setToast("Message is too long (" + itoa(composerCharLimit) + " char limit)")
		return false
	}
	if chat != nil {
		if remain := slowmodeRemain(*chat, f.now); remain > 0 {
			a.slowmodeToast(chat)
			return false
		}
	}
	a.wid.composer.SetText("")
	a.sendText(txt)
	return true
}

func (a *App) composerBar(gtx layout.Context, f frame, chat *engine.ChatInfo) layout.Dimensions {
	a.wid.composer.Submit = composerSubmitSends(f.cfg.ComposerSubmit)
	keyLayer(gtx, composerSubmitKeyTag)
	for _, name := range []key.Name{key.NameReturn, key.NameEnter} {
		for {
			ev, ok := gtx.Source.Event(key.Filter{Name: name, Required: key.ModCtrl})
			if !ok {
				break
			}
			if ke, is := ev.(key.Event); is && ke.State == key.Press && gtx.Source.Focused(&a.wid.composer) {
				a.trySubmitComposer(f, chat)
			}
		}
	}

	if chat != nil {
		if remain := slowmodeRemain(*chat, f.now); remain > 0 {
			a.scheduleSlowTick(remain)
		}
	}
	for {
		ev, ok := a.wid.composer.Update(gtx)
		if !ok {
			break
		}
		if se, isSubmit := ev.(widget.SubmitEvent); isSubmit {
			if txt := strings.TrimSpace(se.Text); txt != "" {
				a.trySubmitComposer(f, chat)
			}
		}
	}
	if a.wid.chatSendBtn.Clicked(gtx) {
		a.trySubmitComposer(f, chat)
	}

	a.ensureSendAs(f)

	return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			var children []layout.FlexChild
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.sendAsRow(gtx, f)
			}))
			if f.cMode.active() {
				children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.composerChip(gtx, f)
				}))
			}
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.End}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if a.wid.attachBtn.Clicked(gtx) {
							a.toggleAttachMenu()
						}
						return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.IconButton(&a.wid.attachBtn, iconFileAttach, "Attach")
							btn.Color = a.ui.p.TextDim
							return btn.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if a.wid.emojiBtn.Clicked(gtx) {
							a.toggleEmojiPanel()
						}
						return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.IconButton(&a.wid.emojiBtn, iconEmojiSmile, "Emoji")
							btn.Color = a.ui.p.TextDim
							if f.emojiOpen {
								btn.Color = a.ui.p.Accent
							}
							return btn.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if !botCmdPanelNeeded(f.botCmds) {
							return layout.Dimensions{}
						}
						if a.wid.botCmdBtn.Clicked(gtx) {
							a.toggleBotCmds()
						}
						return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.IconButton(&a.wid.botCmdBtn, iconNavMoreVert, "Bot commands")
							btn.Color = a.ui.p.TextDim
							if f.botCmdsOn {
								btn.Color = a.ui.p.Accent
							}
							return btn.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if !a.voiceRecWanted(f) {
							return layout.Dimensions{}
						}
						return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.voiceRecMicButton(gtx, f)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return roundedFill(gtx, a.ui.p.SurfaceHi, 14, func(gtx layout.Context) layout.Dimensions {
							gtx.Constraints.Min.Y = gtx.Dp(unit.Dp(44))
							return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								ed := a.ui.Editor(&a.wid.composer, botKbdComposerHint(f))
								return ed.Layout(gtx)
							})
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if chat == nil {
							return layout.Dimensions{}
						}
						return a.slowmodeChip(gtx, f, chat)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if a.wid.silentBtn.Clicked(gtx) {
							a.mu.Lock()
							a.silentNext = !a.silentNext
							on := a.silentNext
							a.mu.Unlock()
							if on {
								a.setToast("Next messages send without sound")
							} else {
								a.setToast("Sound on")
							}
						}
						a.mu.Lock()
						on := a.silentNext
						a.mu.Unlock()
						return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.IconButton(&a.wid.silentBtn, iconSocialNotif, "Send without sound")
							btn.Color = a.ui.p.TextDim
							if on {
								btn.Color = a.ui.p.Accent
							}
							return btn.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if !composedHasLink(a.wid.composer.Text()) || f.msgFor == nil {
							return layout.Dimensions{}
						}
						k := f.msgFor
						if a.wid.linkPrevBtn.Clicked(gtx) {
							linkPreviewMu.Lock()
							linkPreview[k.String()] = !linkPreview[k.String()]
							off := linkPreview[k.String()]
							linkPreviewMu.Unlock()
							if off {
								a.setToast("Link preview off")
							} else {
								a.setToast("Link preview on")
							}
							a.invalidate()
						}
						linkPreviewMu.Lock()
						off := linkPreview[k.String()]
						linkPreviewMu.Unlock()
						return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.IconButton(&a.wid.linkPrevBtn, iconContentLink, "Toggle link preview")
							btn.Color = a.ui.p.TextDim
							if off {
								btn.Color = a.ui.p.Error
							}
							return btn.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if a.wid.composerSchedBtn.Clicked(gtx) {
							a.openScheduleDialog()
						}
						return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.IconButton(&a.wid.composerSchedBtn, iconActionSchedule, "Schedule message")
							btn.Color = a.ui.p.TextDim
							if f.schedDlg != nil {
								btn.Color = a.ui.p.Accent
							}
							return btn.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							if f.sending {
								ld := material.Loader(a.ui.Theme)
								ld.Color = a.ui.p.Accent
								return layout.Inset{Bottom: unit.Dp(10)}.Layout(gtx, ld.Layout)
							}
							btn := material.IconButton(a.ui.Theme, &a.wid.chatSendBtn, iconContentSend, "Send")
							btn.Background = a.ui.p.Accent
							btn.Color = rgb(0x0D1821)
							btn.Size = unit.Dp(22)
							btn.Inset = layout.UniformInset(unit.Dp(11))
							return btn.Layout(gtx)
						})
					}),
				)
			}))
			if lbl, visible, over := charCounterState(a.wid.composer.Text(), composerCharLimit); visible {
				lbl, over := lbl, over
				children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(2), Right: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						c := a.ui.Dim(unit.Sp(10), lbl)
						if over {
							c.Color = a.ui.p.Error
						}
						gtx.Constraints.Min.X = 0
						return layout.E.Layout(gtx, c.Layout)
					})
				}))
			}
			return layout.Flex{Axis: layout.Vertical, Alignment: layout.End}.Layout(gtx, children...)
		},
	)
}

const composerCharLimit = 4096

func charCounterState(text string, limit int) (string, bool, bool) {
	n := utf8.RuneCountInString(text)
	remain := limit - n
	if remain > 128 {
		return "", false, false
	}
	return strconv.Itoa(remain), true, remain < 0
}

func composerOverLimit(text string) bool {
	_, _, over := charCounterState(text, composerCharLimit)
	return over
}

func (a *App) composerChip(gtx layout.Context, f frame) layout.Dimensions {
	if a.wid.chipCancelBtn.Clicked(gtx) {
		a.cancelComposerMode()
	}
	title, preview := f.cMode.header()
	return layout.Inset{Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(6), Bottom: unit.Dp(6), Left: unit.Dp(10), Right: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(12), title)
								lbl.Color = a.ui.p.Accent
								lbl.Font.Weight = font.SemiBold
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								if preview == "" {
									return layout.Dimensions{}
								}
								lbl := a.ui.Dim(unit.Sp(12), preview)
								lbl.MaxLines = 1
								return lbl.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.IconButton(&a.wid.chipCancelBtn, iconContentClear, "Cancel")
						btn.Color = a.ui.p.TextDim
						btn.Size = unit.Dp(18)
						btn.Inset = layout.UniformInset(unit.Dp(6))
						return btn.Layout(gtx)
					}),
				)
			})
		})
	})
}

func deletedFade(c color.NRGBA, deleted bool) color.NRGBA {
	if !deleted {
		return c
	}
	return withAlpha(c, 0x80)
}
