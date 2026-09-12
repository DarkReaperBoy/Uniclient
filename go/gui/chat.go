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

// Chat view widgets.
var (
	chatBackBtn widget.Clickable
	chatSendBtn widget.Clickable
	composer    widget.Editor
	msgList     widget.List
	joinBarBtn  widget.Clickable // JOIN (not-joined channels, slice 19)
	silentBtn   widget.Clickable // per-message silent (slice 23)
	linkPrevBtn widget.Clickable // link-preview toggle (slice 117)
)

func init() {
	composer.SingleLine = false
	msgList.Axis = layout.Vertical
	msgList.ScrollToEnd = true // stick to bottom, AyuGram-style
}

// layoutChatView: header, message list (scrollable), composer, plus the
// message-action overlay layer (context menu, forward picker swap).
func (a *App) layoutChatView(gtx layout.Context, f frame, narrow bool) layout.Dimensions {
	if f.selected == nil {
		return a.layoutEmptyState(gtx)
	}
	// Forward picker replaces the pane content (AyuGram ChooseRecipientBox;
	// layout swap = no click-through).
	if len(f.fwd) > 0 {
		return a.layoutForwardDialog(gtx, f)
	}
	chat := findChat(f, *f.selected)

	// Right info panel replaces the pane on narrow layouts (AyuGram slide-in).
	if f.panelOpen && narrow {
		return a.layoutInfoPanel(gtx, f, chat, true)
	}

	// Scheduled-messages panel replaces the pane (AyuGram, slice 21).
	if f.schedPanel {
		return a.layoutSchedPanel(gtx, f, chat)
	}

	// Route pane presses (right-click context menu, menu dismissal).
	a.processPaneEvents(gtx, f)

	chatPane := func(gtx layout.Context) layout.Dimensions {
		return a.chatPaneColumn(gtx, f, chat, narrow)
	}
	if f.panelOpen {
		// Desktop: chat column | divider | info panel (AyuGram 3rd pane).
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

// chatPaneColumn renders the chat column (header + messages + composer) plus
// the overlay menu — the non-panel layout of the chat view.
func (a *App) chatPaneColumn(gtx layout.Context, f frame, chat *engine.ChatInfo, narrow bool) layout.Dimensions {
	dims := layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		// Header
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
		// Forum topic bar (slice 118): the open topic's identity strip.
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if chat == nil || !chat.IsForum || f.forumTopic == "" {
				return layout.Dimensions{}
			}
			d := a.topicBar(gtx, f)
			a.listTop += d.Size.Y
			return d
		}),
		// Group-call live bar (slice 70): under the header while the chat
		// has an active call; participant data polled from the engine.
		// Voice-room backends (Mumble/TeamSpeak) show it on every channel —
		// a channel IS a standing voice room, empty or not.
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
		// Selection bar (AyuGram multi-select) replaces the pinned bar.
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
		// In-chat search bar + results (slice 18) under the pinned bar.
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if !f.inSearch || f.selected == nil {
				return layout.Dimensions{}
			}
			d := a.layoutInChatSearch(gtx, f, *f.selected)
			a.listTop += d.Size.Y
			return d
		}),
		// Chat-wide translate bar (slice 150): tdesktop's "Translate to
		// …" strip between the search bar and the message list.
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if f.selected == nil || !chatTranslateOn(f, f.selected) {
				return layout.Dimensions{}
			}
			d := a.layoutTranslateBar(gtx, f, *f.selected)
			a.listTop += d.Size.Y
			return d
		}),
		// Messages — or the forum topic list on a forum's root view (slice 118).
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			if chat != nil && chat.IsForum && f.forumTopic == "" {
				return a.topicListPane(gtx, f, chat)
			}
			return a.messageList(gtx, f, chat)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.ui.Divider(gtx)
		}),
		// Bot reply keyboard (slice 127): the chat's active custom
		// keyboard under the composer area — latest keyboard message
		// wins, a later keyboard_hide clears it, single_use hides it
		// after one tap.
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if chat != nil && chat.IsForum && f.forumTopic == "" {
				return layout.Dimensions{}
			}
			kbd, singleUse, _, src := activeReplyKbd(f.messages)
			replyKbdSingleUse = singleUse
			return a.layoutReplyKeyboard(gtx, f, kbd, src)
		}),
		// Composer (JOIN bar for not-joined previews, restriction bar for
		// write-restricted chats, recording panel while a voice note is
		// captured, input + slow-mode chip otherwise)
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if chat != nil && chat.IsForum && f.forumTopic == "" {
				return layout.Dimensions{} // topic list view: no composer
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

	// Context menu on top of everything in the pane.
	if f.menu != nil {
		a.layoutContextMenu(gtx, f)
	}
	// Forum topic dialog (slice 118): create/edit/actions.
	if f.forumDlg != nil {
		a.layoutForumDialog(gtx, f)
	}
	// Chat-header "..." menu.
	if f.headerMenu != nil {
		a.layoutHeaderMenu(gtx, f)
	}
	// Attach popup above the composer.
	if f.attachMenuOpen {
		a.layoutAttachMenu(gtx, f)
	}
	// Emoji picker above the composer.
	if f.emojiOpen {
		a.layoutEmojiPanel(gtx, f)
	}
	// Bot commands panel above the composer (slice 76).
	if f.botCmdsOn {
		a.layoutBotCmdsPanel(gtx, f)
	}
	// Inline bot results panel (slice 128): "@bot query" live results.
	a.layoutInlineResults(gtx, f)
	// Inline ":shortcode" emoji autocomplete strip (AyuGram composer).
	a.layoutEmojiAutocomplete(gtx, f)
	// Delete confirm (slice 19).
	if f.delDlg != nil {
		a.layoutDeleteDialog(gtx, f)
	}
	// Report flow (slice 19).
	if f.reportDlg != nil {
		a.layoutReportDialog(gtx, f)
	}
	// Schedule dialog (slice 20).
	if f.schedDlg != nil {
		a.layoutScheduleDialog(gtx, f)
	}
	// Poll creation dialog (slice 42).
	if f.pollDlg != nil {
		a.layoutPollDialog(gtx, f)
	}
	// Who-reacted dialog (slice 49).
	if f.reactors != nil {
		a.layoutReactorsDialog(gtx, f)
	}
	// Ayu shadow-ban manager dialog (slice 91).
	if f.shadowDlg != nil {
		a.layoutShadowDialog(gtx, f)
	}
	// Edits-history dialog (slice 96).
	if f.editHistDlg != nil {
		a.layoutEditHistDialog(gtx, f)
	}
	// Deleted-messages browser dialog (slice 97).
	if f.deletedDlg != nil {
		a.layoutDeletedDialog(gtx, f)
	}
	// Seen-by read-receipt dialog (slice 98).
	if f.seenDlg != nil {
		a.layoutSeenByDialog(gtx, f)
	}
	// Message-details dialog (slice 105).
	if f.msgDetailDlg != nil {
		a.layoutMsgDetail(gtx, f)
	}
	// Sticker-pack dialog (slice 108).
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

// chatHeader: back button (narrow), avatar, title, status/typing, platform tag.
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
							// DM peer presence (slice 28): online / last seen.
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
							// presence leaks identity — mask in streamer mode
							if f.cfg.Streamer {
								return a.masked(gtx, lbl.Layout)
							}
							return lbl.Layout(gtx)
						}),
					)
				}),
				// connection indicator for this chat's account
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					acc := accountByID(f, chat.AccountID)
					dot := connDotFor(acc)
					return statusChip(gtx, a.ui, dot)
				}),
				// 1:1 call buttons (slice 101): phone + video for callable DMs,
				// capability-gated (hidden otherwise — never dead UI, §1.10).
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					voice, _ := false, false
					if chat != nil {
						voice, _ = dmCallButtons(*chat, f.hdrCaps)
					}
					if !voice {
						return layout.Dimensions{}
					}
					if headerVoiceCallBtn.Clicked(gtx) {
						c := *chat
						a.startDMCall(c, false)
					}
					return layout.Inset{Left: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.IconButton(&headerVoiceCallBtn, iconCommunicationCall, "Voice call")
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
					if headerVideoCallBtn.Clicked(gtx) {
						c := *chat
						a.startDMCall(c, true)
					}
					return layout.Inset{Left: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.IconButton(&headerVideoCallBtn, iconAVVideocam, "Video call")
						btn.Color = a.ui.p.TextDim
						return btn.Layout(gtx)
					})
				}),
				// search — in-chat search (AyuGram, slice 18)
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if headerSearchBtn.Clicked(gtx) {
						a.toggleInChatSearch()
					}
					btn := a.ui.IconButton(&headerSearchBtn, iconActionSearch, "Search in chat")
					btn.Color = a.ui.p.TextDim
					if f.inSearch {
						btn.Color = a.ui.p.Accent
					}
					return btn.Layout(gtx)
				}),
				// info (ⓘ) — right panel toggle (AyuGram)
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if panelInfoBtn.Clicked(gtx) {
						if f.panelOpen {
							a.closePanel()
						} else {
							a.openPanel()
						}
					}
					btn := a.ui.IconButton(&panelInfoBtn, iconActionInfo, "Chat info")
					btn.Color = a.ui.p.TextDim
					return btn.Layout(gtx)
				}),
				// "..." — peer menu (AyuGram ⋮)
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if headerMoreBtn.Clicked(gtx) {
						if chat != nil {
							c := *chat
							a.openHeaderMenu(c, image.Pt(gtx.Constraints.Max.X, a.headerH))
						}
					}
					return layout.Inset{Left: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.IconButton(&headerMoreBtn, iconNavMoreVert, "Chat menu")
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
	if chatBackBtn.Clicked(gtx) {
		a.mu.Lock()
		prev := a.selected
		a.selected = nil
		a.msgFor = nil
		a.mu.Unlock()
		if prev != nil {
			a.flushDraft(*prev) // slice 20: keep the text for next time
		}
		a.invalidate()
	}
	return layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			btn := a.ui.IconButton(&chatBackBtn, iconNavigationBack, "Back")
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

// statusChip renders a small colored connection dot with label.
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

// messageList: scrolling message bubbles + day dividers + typing row.
// Records per-message row bounds (pane coords) for right-click hit tests and
// triggers scroll-up history pagination (AyuGram loadMessages).
func (a *App) messageList(gtx layout.Context, f frame, chat *engine.ChatInfo) layout.Dimensions {
	// Auto-scroll: AnchorEnd keeps us pinned unless the user scrolls up.
	// While someone is typing we keep the view pinned & animating.
	if a.stillTyping(*f.selected) || f.sending || dlActive(f.downloads) {
		gtx.Execute(op.InvalidateCmd{At: time.Now().Add(200 * time.Millisecond)})
	}

	// Build the row model: day dividers + messages + the unread separator
	// anchored to its boundary message.
	rows := buildChatRows(f.messages, f.unreadSepMsgID)

	if f.loadingMsgs {
		// loading indicator at top
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

	// Empty chat intro (AyuGram "No messages here yet…").
	if len(f.messages) == 0 {
		return a.emptyIntro(gtx, f)
	}

	// Reset this frame's row bounds; refill as visible rows lay out.
	a.rowBounds = make(map[int]image.Rectangle, len(rows))
	paneW := gtx.Constraints.Max.X
	y := -msgList.Position.Offset

	list := material.List(a.ui.Theme, &msgList)
	dims := list.Layout(gtx, len(rows), func(gtx layout.Context, i int) layout.Dimensions {
		r := rows[i]
		var d layout.Dimensions
		switch {
		case r.unread:
			d = a.unreadDivider(gtx)
		case r.day != "":
			d = a.dayDivider(gtx, r.day)
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

	// Rubber-band selection overlay (slice 84): selection-mode drags mark
	// every visible row the rectangle touches.
	if f.selOn {
		a.rubberBandOverlay(gtx, f, dims.Size)
	}

	// Scroll-up pagination: at (or near) the top, load older history once.
	if msgList.Position.First == 0 && msgList.Position.Offset <= 64 &&
		!f.loadingOlder && len(f.messages) > 0 && a.olderExhaustedLocked() == false {
		a.loadOlder()
	}
	return dims
}

// olderExhaustedLocked reports whether the open chat has more history.
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

// messageRow renders one message bubble: outgoing right-aligned accent,
// incoming left-aligned surface.
func (a *App) messageRow(gtx layout.Context, f frame, m *engine.CachedMessage) layout.Dimensions {
	// Service messages render as centered pills (AyuGram: "X joined the
	// group"), not bubbles — no sender, no tail, no reactions.
	if m.IsService {
		return a.serviceRow(gtx, m)
	}
	out := m.IsOutgoing

	// Highlight deleted (anti-recall) messages with the Ayu mark string.
	text := m.ContentText
	deleted := m.IsDeleted
	if deleted {
		text = deletedMarkText(text, f.cfg.AyuDeletedMark)
	}

	// Bubble width (AyuGram "wide multiplier", slice 93): the pane
	// fraction is configurable 0.70..1.00; default 0.75 (the old 3/4).
	maxW := int(float64(gtx.Constraints.Max.X) * a.ui.wideMultiplier())
	pad := gtx.Constraints.Max.X - maxW

	// Stickers render without bubble chrome (AyuGram): bare artwork with
	// a translucent meta pill overlaid bottom-right (slice 123).
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
			bg = a.ui.p.AccentDim
		}
		// Anti-recall (Ayu, slice 80): recalled bubbles fade to half
		// opacity across bg, text and sender name.
		if deleted {
			bg = deletedFade(bg, true)
		}
		return roundedFill(gtx, bg, unit.Dp(a.ui.bubbleRadius()), func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					// Forwarded-from header (AyuGram: "Forwarded from X"),
					// masked in streamer mode (slice 44).
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
					// Poll (AyuGram parity, slice 42): question + tappable
					// options + vote bars, from the message's raw Extra.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.pollBlock(gtx, m)
					}),
					// Link preview card (slice 117): thumb + site + title +
					// description above the text, tap opens the URL.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.webPageBlock(gtx, m)
					}),
					// Media attachment (AyuGram: photo/video/voice/audio/file bubble,
					// driven by the engine download pipeline). A link-preview card
					// owns its message's only media row (the page photo, slice 130)
					// — never double-render it as a photo bubble.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if !m.HasMedia || m.MediaType == 0 || parseWebPage(m) != nil {
							return layout.Dimensions{}
						}
						return a.mediaBlock(gtx, f, m)
					}),
					// Reply quote block (AyuGram quoted bar, click → jump).
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if m.ReplyPreview == "" {
							return layout.Dimensions{}
						}
						return a.replyQuote(gtx, f, *m, *f.msgFor)
					}),
					// sender name in group chats (masked in streamer mode);
					// Telegram name color + admin rank (slice 77).
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if out || m.SenderName == "" || m.IsService {
							return layout.Dimensions{}
						}
						lbl := a.ui.Label(unit.Sp(13), senderTitle(*m))
						senderCol := senderColorFor(m.SenderColorID, m.SenderID)
						if deleted { // anti-recall fade (slice 80)
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
						// Rich text (slice 32): entity formatting + spoiler reveal.
						// Pass the bubble color so hidden spoilers vanish into it.
						body := *m
						body.ContentText = text
						bgCol := a.ui.p.BubbleIn
						if out {
							bgCol = a.ui.p.AccentDim
						}
						if deleted { // anti-recall fade (slice 80)
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
					// Translation block (Ayu translator, slice 46) — shown for
					// per-message toggles AND the chat-wide bar (slice 150),
					// which also lazily fetches every text message's result.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if chatTranslateOn(f, &chatKey{AccountID: m.AccountID, ChatID: m.ChatID}) {
							a.ensureAutoTranslation(m)
						}
						return a.translationBlock(gtx, m)
					}),
					// Inline keyboard (slice 127): bot button rows below the
					// content (callback/url/copy/switch_inline/game/buy —
					// tdesktop HistoryView placement).
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.layoutInlineKeyboard(gtx, m)
					}),
					// Reactions strip (AyuGram parity: emoji + count, own highlighted).
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if len(m.Reactions) == 0 {
							return layout.Dimensions{}
						}
						return a.reactionStrip(gtx, f, m)
					}),
					// meta: time + edited + status ticks
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
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
					// Inline read receipt (slice 152): tdesktop's DM "Seen"
					// row w/ reader avatar under the last own message.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						chat := chatOf(f, *m)
						if !seenInlineGate(*m, chat.Type, m.MsgID == msgFrameLastOwn) {
							return layout.Dimensions{}
						}
						a.ensureSeenInline(m)
						return a.layoutSeenInline(gtx, f, m)
					}),
				)
			})
		})
	}

	// Selection mode: leading check circle outside the bubble (AyuGram).
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
		return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(pad)}.Layout(gtx, bubble)
	}
	return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Right: unit.Dp(pad)}.Layout(gtx, bubble)
}

// replyQuote renders the quoted reply block inside a bubble. The cached
// preview is "sender\ntext" or plain "text" (AyuGram quoted bar).
func (a *App) replyQuote(gtx layout.Context, f frame, m engine.CachedMessage, k chatKey) layout.Dimensions {
	sender, body := m.ReplyPreview, m.ReplyPreview
	if i := strings.IndexByte(m.ReplyPreview, '\n'); i >= 0 {
		sender, body = m.ReplyPreview[:i], m.ReplyPreview[i+1:]
	}
	btn := replyQuoteClickable(k.String() + "/" + m.MsgID)
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

// replyQuoteClicks: per-message clickables for the reply-quote
// click-to-jump (AyuGram quote navigation, slice 25).
var replyQuoteClicks = map[string]*widget.Clickable{}

func replyQuoteClickable(msgID string) *widget.Clickable {
	if c, ok := replyQuoteClicks[msgID]; ok {
		return c
	}
	if len(replyQuoteClicks) > 512 {
		replyQuoteClicks = make(map[string]*widget.Clickable)
	}
	c := new(widget.Clickable)
	replyQuoteClicks[msgID] = c
	return c
}

// reactionClicks holds per-(message,emoji) pill clickables, pruned when the
// map outgrows the open chat (rows scroll out and never come back).
var reactionClicks = map[string]*widget.Clickable{}

func reactionClickable(key string) *widget.Clickable {
	if c, ok := reactionClicks[key]; ok {
		return c
	}
	if len(reactionClicks) > 512 {
		reactionClicks = make(map[string]*widget.Clickable)
	}
	c := new(widget.Clickable)
	reactionClicks[key] = c
	return c
}

// reactionStrip renders the reactions under a bubble: emoji + count pills,
// the user's own reaction highlighted with the accent. Clicking a pill
// toggles the own reaction (engine ReactToMessage; optimistic cache update).
func (a *App) reactionStrip(gtx layout.Context, f frame, m *engine.CachedMessage) layout.Dimensions {
	canReact := actionsFor(m, f.menuCaps).React
	// Register the message's custom-emoji document ids so the first pill
	// below batches one engine fetch for the whole strip.
	if want := customWantDocs(m.Reactions); len(want) > 0 {
		a.noteCustomThumbs(m.AccountID, want)
	}
	children := make([]layout.FlexChild, 0, len(m.Reactions))
	for i := range m.Reactions {
		r := m.Reactions[i]
		if r.Emoji == "" && r.DocumentID == 0 {
			continue // reaction without identity (e.g. paid placeholder)
		}
		emoji, docID, count, byMe := r.Emoji, r.DocumentID, r.Count, r.ByMe
		react := emoji
		if emoji == "" {
			react = customReactionKey(docID)
		}
		key := m.MsgID + "|" + react
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			btn := reactionClickable(key)
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

// statusTicks: sending (clock spinner), sent (single check),
// delivered (double check), read (double check, accent).
func (a *App) statusTicks(gtx layout.Context, status int, f frame) layout.Dimensions {
	_ = f
	c := color.NRGBA(a.ui.p.TextFaint)
	switch status {
	case 3: // read
		c = a.ui.p.Accent
	case 1, 2: // sent / delivered
		c = a.ui.p.TextDim
	}
	d := gtx.Dp(unit.Dp(12))
	switch status {
	case 0: // sending
		ld := material.Loader(a.ui.Theme)
		ld.Color = c
		gtx.Constraints.Max = image.Pt(gtx.Dp(unit.Dp(14)), gtx.Dp(unit.Dp(14)))
		return ld.Layout(gtx)
	case 1:
		return check(gtx, c, d, 0)
	default:
		return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions { return check(gtx, c, d, 0) }),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions { return check(gtx, c, d, -gtx.Dp(unit.Dp(5))) }),
		)
	}
}

// check draws a simple check mark path.
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

// joinBar: the JOIN action shown instead of the composer for not-joined
// channel previews (AyuGram preview behavior, slice 19). Joins via
// engine.JoinChannel; the engine re-sync flips the chat to joined.
func (a *App) joinBar(gtx layout.Context, f frame, chat *engine.ChatInfo) layout.Dimensions {
	if joinBarBtn.Clicked(gtx) {
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
					btn := a.ui.PrimaryButton(&joinBarBtn, "JOIN")
					return btn.Layout(gtx)
				}),
			)
		})
}

// composerBar: input + send, disabled state shows progress. When a reply or
// edit mode is active (AyuGram input field), a header chip with the quoted
// message sits above the input row. Slow-mode chats carry a countdown chip
// that gates sending (slice 69).
// composerSubmitKeyTag listens for Ctrl+Enter submits (slice 155).
var composerSubmitKeyTag = new(struct{})

// trySubmitComposer sends the composer's current text through the shared
// gate — length limit, slow-mode wait, in-flight guard — shared by the
// Enter SubmitEvent, the send button, and the Ctrl+Enter shortcut
// (slice 155). Returns true when a send started.
func (a *App) trySubmitComposer(f frame, chat *engine.ChatInfo) bool {
	txt := strings.TrimSpace(composer.Text())
	if txt == "" || f.sending {
		return false
	}
	if composerOverLimit(composer.Text()) {
		a.setToast("Message is too long (" + itoa(composerCharLimit) + " char limit)")
		return false
	}
	if chat != nil {
		if remain := slowmodeRemain(*chat, f.now); remain > 0 {
			a.slowmodeToast(chat)
			return false
		}
	}
	composer.SetText("")
	a.sendText(txt)
	return true
}

func (a *App) composerBar(gtx layout.Context, f frame, chat *engine.ChatInfo) layout.Dimensions {
	// Composer submit mode (tdesktop Messages setting, slice 155): Enter
	// submits by default; "ctrl-enter" moves submission to Ctrl+Enter and
	// makes Enter a newline.
	composer.Submit = composerSubmitSends(f.cfg.ComposerSubmit)
	// Ctrl+Enter submits (both modes — tdesktop behavior); only while the
	// composer holds focus so other editors (search, dialogs) keep it.
	keyLayer(gtx, composerSubmitKeyTag)
	for _, name := range []key.Name{key.NameReturn, key.NameEnter} {
		for {
			ev, ok := gtx.Source.Event(key.Filter{Name: name, Required: key.ModCtrl})
			if !ok {
				break
			}
			if ke, is := ev.(key.Event); is && ke.State == key.Press && gtx.Source.Focused(&composer) {
				a.trySubmitComposer(f, chat)
			}
		}
	}

	// Slow-mode wait active → the shared gate blocks submission; keep
	// the countdown ticker armed while the wait runs.
	if chat != nil {
		if remain := slowmodeRemain(*chat, f.now); remain > 0 {
			a.scheduleSlowTick(remain)
		} else {
			slowmodeSendBlocked = false
		}
	}
	// Submit on Enter (Shift+Enter = newline) unless mobile-wide.
	for {
		ev, ok := composer.Update(gtx)
		if !ok {
			break
		}
		if se, isSubmit := ev.(widget.SubmitEvent); isSubmit {
			if txt := strings.TrimSpace(se.Text); txt != "" {
				a.trySubmitComposer(f, chat)
			}
		}
	}
	if chatSendBtn.Clicked(gtx) {
		a.trySubmitComposer(f, chat)
	}

	return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			var children []layout.FlexChild
			if f.cMode.active() {
				children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.composerChip(gtx, f)
				}))
			}
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.End}.Layout(gtx,
					// attach (📎) — file/photo picker menu (AyuGram)
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if attachBtn.Clicked(gtx) {
							a.toggleAttachMenu()
						}
						return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.IconButton(&attachBtn, iconFileAttach, "Attach")
							btn.Color = a.ui.p.TextDim
							return btn.Layout(gtx)
						})
					}),
					// emoji (😊) — picker panel (AyuGram)
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if emojiBtn.Clicked(gtx) {
							a.toggleEmojiPanel()
						}
						return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.IconButton(&emojiBtn, iconEmojiSmile, "Emoji")
							btn.Color = a.ui.p.TextDim
							if f.emojiOpen {
								btn.Color = a.ui.p.Accent
							}
							return btn.Layout(gtx)
						})
					}),
					// bot-commands button (slice 76): renders only when the
					// open chat has commands (engine-loaded; never dead).
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if !botCmdPanelNeeded(f.botCmds) {
							return layout.Dimensions{}
						}
						if botCmdBtn.Clicked(gtx) {
							a.toggleBotCmds()
						}
						return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.IconButton(&botCmdBtn, iconNavMoreVert, "Bot commands")
							btn.Color = a.ui.p.TextDim
							if f.botCmdsOn {
								btn.Color = a.ui.p.Accent
							}
							return btn.Layout(gtx)
						})
					}),
					// hold-to-record mic (slice 114): only when the composer
					// is empty and the account's core sends voice notes.
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
								ed := a.ui.Editor(&composer, botKbdComposerHint(f))
								return ed.Layout(gtx)
							})
						})
					}),
					// slow-mode countdown pill (slice 69) — blocks sending
					// while the server's wait is active.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if chat == nil {
							return layout.Dimensions{}
						}
						return a.slowmodeChip(gtx, f, chat)
					}),
					// silent (🔕) — send without sound (AyuGram
					// per-message mute, slice 23).
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if silentBtn.Clicked(gtx) {
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
							btn := a.ui.IconButton(&silentBtn, iconSocialNotif, "Send without sound")
							btn.Color = a.ui.p.TextDim
							if on {
								btn.Color = a.ui.p.Accent
							}
							return btn.Layout(gtx)
						})
					}),
					// link preview toggle — visible only while the text contains a
					// link (AyuGram/Telegram preview toggle, slice 117): off sends
					// with no_webpage.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if !composedHasLink(composer.Text()) || f.msgFor == nil {
							return layout.Dimensions{}
						}
						k := f.msgFor
						if linkPrevBtn.Clicked(gtx) {
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
							btn := a.ui.IconButton(&linkPrevBtn, iconContentLink, "Toggle link preview")
							btn.Color = a.ui.p.TextDim
							if off {
								btn.Color = a.ui.p.Error
							}
							return btn.Layout(gtx)
						})
					}),
					// schedule (⏰) — schedule the composed
					// message (AyuGram, slice 20).
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if composerSchedBtn.Clicked(gtx) {
							a.openScheduleDialog()
						}
						return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.IconButton(&composerSchedBtn, iconActionSchedule, "Schedule message")
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
							btn := material.IconButton(a.ui.Theme, &chatSendBtn, iconContentSend, "Send")
							btn.Background = a.ui.p.Accent
							btn.Color = rgb(0x0D1821)
							btn.Size = unit.Dp(22)
							btn.Inset = layout.UniformInset(unit.Dp(11))
							return btn.Layout(gtx)
						})
					}),
				)
			}))
			// Char counter (slice 88, AyuGram row 124): remaining
			// characters near the limit, red past it. The send
			// gates above stay honest — over-limit text never
			// leaves the composer.
			if lbl, visible, over := charCounterState(composer.Text(), composerCharLimit); visible {
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

// composerCharLimit is Telegram's per-message text limit (chars).
const composerCharLimit = 4096

// charCounterState returns the remaining-chars caption and whether it
// shows (AyuGram: only near the limit). Pure — locked by tests.
func charCounterState(text string, limit int) (string, bool, bool) {
	n := utf8.RuneCountInString(text)
	remain := limit - n
	if remain > 128 {
		return "", false, false
	}
	return strconv.Itoa(remain), true, remain < 0
}

// composerOverLimit reports whether the draft exceeds the limit.
func composerOverLimit(text string) bool {
	_, _, over := charCounterState(text, composerCharLimit)
	return over
}

// composerChip renders the reply/edit header above the input: title, quoted
// preview, and a close (cancel) button — AyuGram's InputField header bar.
func (a *App) composerChip(gtx layout.Context, f frame) layout.Dimensions {
	if chipCancelBtn.Clicked(gtx) {
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
						btn := a.ui.IconButton(&chipCancelBtn, iconContentClear, "Cancel")
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

// deletedFade halves a color's alpha for anti-recall bubbles (AyuGram
// renders recalled messages semi-transparent). Pure.
func deletedFade(c color.NRGBA, deleted bool) color.NRGBA {
	if !deleted {
		return c
	}
	return withAlpha(c, 0x80)
}
