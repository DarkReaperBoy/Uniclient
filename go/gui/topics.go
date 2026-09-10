package gui

import (
	"image"
	"image/color"
	"sort"
	"strconv"

	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"

	"uniclient/cores"
	"uniclient/engine"
)

// Forum topics (slice 118, Telegram forum parity): a forum chat opens on
// its topic list (pinned first, then by activity) instead of the raw message
// stream; tapping a topic scopes the view to that topic (topic bar, messages
// filtered by the cached topic_id, composer sends with topicRootID). Topic
// management rides the engine's forum CRUD: create (title + icon color),
// pin/unpin, close/reopen, rename, delete history.

// ── pure helpers (unit-tested) ────────────────────────────────────────────

// sortForumTopics orders topics pinned-first, then by descending top
// message id (activity), General first among equals.
func sortForumTopics(topics []cores.ForumTopic) []cores.ForumTopic {
	out := make([]cores.ForumTopic, len(topics))
	copy(out, topics)
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].IsPinned != out[j].IsPinned {
			return out[i].IsPinned
		}
		ti, _ := strconv.Atoi(out[i].TopMessageID)
		tj, _ := strconv.Atoi(out[j].TopMessageID)
		if ti != tj {
			return ti > tj
		}
		return out[i].ID == "1"
	})
	return out
}

// topicColor maps Telegram's predefined topic icon colors; unknown ids get
// the accent.
func topicColor(colorID int, accent color.NRGBA) color.NRGBA {
	switch colorID {
	case 0x6FB9F0:
		return color.NRGBA{R: 0x6F, G: 0xB9, B: 0xF0, A: 0xFF}
	case 0xFFD67E:
		return color.NRGBA{R: 0xFF, G: 0xD6, B: 0x7E, A: 0xFF}
	case 0xCB86DB:
		return color.NRGBA{R: 0xCB, G: 0x86, B: 0xDB, A: 0xFF}
	case 0x8EEE98:
		return color.NRGBA{R: 0x8E, G: 0xEE, B: 0x98, A: 0xFF}
	case 0xFF93B2:
		return color.NRGBA{R: 0xFF, G: 0x93, B: 0xB2, A: 0xFF}
	case 0xFB6F5F:
		return color.NRGBA{R: 0xFB, G: 0x6F, B: 0x5F, A: 0xFF}
	}
	return accent
}

// topicIsGeneral: id "1" is the forum's General topic.
func topicIsGeneral(id string) bool { return id == "1" }

// topicSubtitle: creator + pinned/closed state summary.
func topicSubtitle(t cores.ForumTopic) string {
	sub := "Topic"
	if t.IsMy {
		sub = "Your topic"
	}
	if t.IsPinned {
		sub += " · pinned"
	}
	return sub
}

// ── state ─────────────────────────────────────────────────────────────────

// forumDlgState drives the topic dialog: mode "create" | "edit" | "actions".
type forumDlgState struct {
	mode    string
	title   string
	colorID int
	topic   *cores.ForumTopic // edit/actions target
	synced  bool              // editor text seeded once
}

// forumDlgColorSel is the create dialog's selected icon color.
var forumDlgColorSel = 0x6FB9F0

var (
	forumTitleEd   widget.Editor
	forumCreateBtn widget.Clickable
	forumCancelBtn widget.Clickable
	forumNewBtn    widget.Clickable
	forumMenuBtn   widget.Clickable
	forumBackBtn   widget.Clickable
	forumActBtns   []widget.Clickable
	forumTopicBtns []widget.Clickable
	forumIconChips []widget.Clickable
)

// loadForumTopics fetches the chat's topic list + default icons (async).
func (a *App) loadForumTopics(k chatKey) {
	go func() {
		topics, err := a.eng.GetForumTopics(k.AccountID, k.ChatID)
		if err != nil {
			return // honest empty list; retry on next open
		}
		icons, _ := a.eng.GetForumTopicDefaultIcons(k.AccountID)
		a.mu.Lock()
		a.forumTopics = topics
		a.forumLoaded = true
		a.forumFor = k.String()
		a.forumIcons = icons
		a.mu.Unlock()
		a.invalidate()
	}()
}

// openForumTopic switches the chat pane into the topic view.
func (a *App) openForumTopic(topicID string) {
	a.mu.Lock()
	k := a.selected
	a.forumTopic = topicID
	a.messages = nil
	a.loadingMsgs = true
	a.olderDone = false
	a.loadingOlder = false
	a.mu.Unlock()
	a.invalidate()
	if k == nil {
		return
	}
	go func() {
		msgs, err := a.eng.GetTopicMessages(k.AccountID, k.ChatID, topicID, 0, 100)
		if err != nil {
			return
		}
		for i, j := 0, len(msgs)-1; i < j; i, j = i+1, j-1 {
			msgs[i], msgs[j] = msgs[j], msgs[i]
		}
		a.mu.Lock()
		a.messages = msgs
		a.loadingMsgs = false
		a.mu.Unlock()
		a.invalidate()
	}()
}

// backToForumTopics returns from the topic view to the topic list.
func (a *App) backToForumTopics() {
	a.mu.Lock()
	k := a.selected
	a.forumTopic = ""
	a.mu.Unlock()
	a.invalidate()
	if k != nil {
		a.refreshMessages()
	}
}

// createForumTopic commits the create dialog (engine CreateForumTopic).
func (a *App) createForumTopic(k chatKey) {
	title := forumTitleEd.Text()
	if title == "" {
		a.setToast("Topic title required")
		return
	}
	go func() {
		if _, err := a.eng.CreateForumTopic(k.AccountID, k.ChatID, title, forumDlgColorSel, 0); err != nil {
			a.setToast("Create topic failed: " + err.Error())
			return
		}
		a.setToast("Topic created")
		a.mu.Lock()
		a.forumDlg = nil
		a.mu.Unlock()
		a.loadForumTopics(k)
		a.invalidate()
	}()
}

// renameForumTopic commits the edit dialog (engine EditForumTopic).
func (a *App) renameForumTopic(k chatKey, t cores.ForumTopic) {
	title := forumTitleEd.Text()
	if title == "" {
		a.setToast("Topic title required")
		return
	}
	go func() {
		tid, _ := strconv.Atoi(t.ID)
		if err := a.eng.EditForumTopic(k.AccountID, k.ChatID, tid, title, 0); err != nil {
			a.setToast("Rename failed: " + err.Error())
			return
		}
		a.mu.Lock()
		a.forumDlg = nil
		a.mu.Unlock()
		a.loadForumTopics(k)
		a.invalidate()
	}()
}

// applyForumAction runs one topic management action from the actions dialog.
func (a *App) applyForumAction(k chatKey, t cores.ForumTopic, action string) {
	go func() {
		var err error
		tid, _ := strconv.Atoi(t.ID)
		switch action {
		case "pin":
			err = a.eng.PinForumTopic(k.AccountID, k.ChatID, tid, !t.IsPinned)
		case "close":
			err = a.eng.ToggleForumTopicClosed(k.AccountID, k.ChatID, tid, !t.IsClosed)
		case "rename":
			a.mu.Lock()
			a.forumDlg = &forumDlgState{mode: "edit", title: t.Title, colorID: t.ColorID, topic: &t}
			a.mu.Unlock()
			a.invalidate()
			return
		case "delete":
			err = a.eng.DeleteForumTopicHistory(k.AccountID, k.ChatID, tid)
		}
		if err != nil {
			a.setToast("Topic action failed: " + err.Error())
			return
		}
		a.mu.Lock()
		a.forumDlg = nil
		a.mu.Unlock()
		a.loadForumTopics(k)
		a.invalidate()
	}()
}

// ── rendering ─────────────────────────────────────────────────────────────

// topicListPane replaces the message list on a forum's root view.
func (a *App) topicListPane(gtx layout.Context, f frame, chat *engine.ChatInfo) layout.Dimensions {
	topics := sortForumTopics(f.forumTopics)
	for len(forumTopicBtns) < len(topics) {
		forumTopicBtns = append(forumTopicBtns, widget.Clickable{})
	}
	rows := make([]layout.FlexChild, 0, len(topics)+2)

	// New topic row.
	rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		if forumNewBtn.Clicked(gtx) {
			forumDlgColorSel = 0x6FB9F0
			a.mu.Lock()
			a.forumDlg = &forumDlgState{mode: "create", colorID: 0x6FB9F0}
			a.mu.Unlock()
			forumTitleEd.SetText("")
			a.invalidate()
		}
		return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(4), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			btn := a.ui.TextButton(&forumNewBtn, "+ New topic")
			btn.Color = a.ui.p.Accent
			return btn.Layout(gtx)
		})
	}))

	if !f.forumLoaded {
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(16)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(13), "Loading topics…")
					return lbl.Layout(gtx)
				})
			})
		}))
	} else if len(topics) == 0 {
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(16)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Dim(unit.Sp(13), "No topics yet")
					return lbl.Layout(gtx)
				})
			})
		}))
	}

	for i := range topics {
		i := i
		tp := topics[i]
		rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			btn := &forumTopicBtns[i]
			if btn.Clicked(gtx) {
				a.openForumTopic(tp.ID)
			}
			return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12), Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return drawTopicIcon(gtx, a.ui, tp)
								})
							}),
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										title := tp.Title
										if topicIsGeneral(tp.ID) {
											title = "General"
										}
										if tp.IsClosed {
											title += " · closed"
										}
										lbl := a.ui.Label(unit.Sp(14), title)
										lbl.MaxLines = 1
										return lbl.Layout(gtx)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
											lbl := a.ui.Dim(unit.Sp(11), topicSubtitle(tp))
											lbl.MaxLines = 1
											return lbl.Layout(gtx)
										})
									}),
								)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								if tp.UnreadCount <= 0 {
									return layout.Dimensions{}
								}
								return unreadBadge(gtx, a.ui, tp.UnreadCount, false)
							}),
						)
					})
				})
			})
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
}

// topicBar renders the open topic's identity strip under the chat header.
func (a *App) topicBar(gtx layout.Context, f frame) layout.Dimensions {
	var tp *cores.ForumTopic
	for i := range f.forumTopics {
		if f.forumTopics[i].ID == f.forumTopic {
			t := f.forumTopics[i]
			tp = &t
			break
		}
	}
	if forumBackBtn.Clicked(gtx) {
		a.backToForumTopics()
	}
	if forumMenuBtn.Clicked(gtx) && tp != nil {
		a.mu.Lock()
		a.forumDlg = &forumDlgState{mode: "actions", topic: tp}
		a.mu.Unlock()
		a.invalidate()
	}
	return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4), Left: unit.Dp(8), Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.IconButton(&forumBackBtn, iconNavigationBack, "Back to topics")
				btn.Color = a.ui.p.TextDim
				return btn.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if tp == nil {
					return layout.Dimensions{}
				}
				return layout.Inset{Left: unit.Dp(4), Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return drawTopicIcon(gtx, a.ui, *tp)
				})
			}),
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				title := "Topic"
				if tp != nil {
					title = tp.Title
					if topicIsGeneral(tp.ID) {
						title = "General"
					}
				}
				lbl := a.ui.Label(unit.Sp(14), title)
				lbl.MaxLines = 1
				return lbl.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if tp == nil {
					return layout.Dimensions{}
				}
				btn := a.ui.IconButton(&forumMenuBtn, iconNavMoreVert, "Topic actions")
				btn.Color = a.ui.p.TextDim
				return btn.Layout(gtx)
			}),
		)
	})
}

// layoutForumDialog renders the create/edit/actions dialog over the pane.
func (a *App) layoutForumDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.forumDlg
	if d == nil || f.msgFor == nil {
		return layout.Dimensions{}
	}
	k := *f.msgFor

	// Actions mode: action rows.
	if d.mode == "actions" && d.topic != nil {
		type actRow struct{ key, label string }
		actions := []actRow{
			{"pin", "Pin topic"},
			{"close", "Close topic"},
			{"rename", "Rename topic"},
			{"delete", "Delete history"},
		}
		if d.topic.IsPinned {
			actions[0].label = "Unpin topic"
		}
		if d.topic.IsClosed {
			actions[1].label = "Reopen topic"
		}
		for len(forumActBtns) < len(actions) {
			forumActBtns = append(forumActBtns, widget.Clickable{})
		}
		paintScrimRect(gtx)
		return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			gtx.Constraints.Max.X = gtx.Dp(unit.Dp(300))
			return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(14)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					children := []layout.FlexChild{
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.H3(d.topic.Title)
							return layout.Inset{Bottom: unit.Dp(6)}.Layout(gtx, lbl.Layout)
						}),
					}
					for i, act := range actions {
						i, act := i, act
						children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							btn := &forumActBtns[i]
							if btn.Clicked(gtx) {
								a.applyForumAction(k, *d.topic, act.key)
							}
							return btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), act.label)
								if act.key == "delete" {
									lbl.Color = a.ui.p.Error
								}
								return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8)}.Layout(gtx, lbl.Layout)
							})
						}))
					}
					children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if forumCancelBtn.Clicked(gtx) {
							a.mu.Lock()
							a.forumDlg = nil
							a.mu.Unlock()
							a.invalidate()
						}
						btn := a.ui.TextButton(&forumCancelBtn, "Cancel")
						return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, btn.Layout)
					}))
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
				})
			})
		})
	}

	// Create / edit mode: title editor + color chips + commit.
	if !d.synced {
		forumTitleEd.SetText(d.title)
		d.synced = true
	}
	if forumCreateBtn.Clicked(gtx) {
		if d.mode == "edit" && d.topic != nil {
			a.renameForumTopic(k, *d.topic)
		} else {
			a.createForumTopic(k)
		}
	}
	if forumCancelBtn.Clicked(gtx) {
		a.mu.Lock()
		a.forumDlg = nil
		a.mu.Unlock()
		a.invalidate()
	}
	colors := []int{0x6FB9F0, 0xFFD67E, 0xCB86DB, 0x8EEE98, 0xFF93B2, 0xFB6F5F}
	for len(forumIconChips) < len(colors) {
		forumIconChips = append(forumIconChips, widget.Clickable{})
	}
	paintScrimRect(gtx)
	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(320))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						title := "New topic"
						if d.mode == "edit" {
							title = "Rename topic"
						}
						lbl := a.ui.H3(title)
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.ui.Editor(&forumTitleEd, "Topic title").Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							chips := make([]layout.FlexChild, 0, len(colors))
							for i, cid := range colors {
								i, cid := i, cid
								chips = append(chips, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									btn := &forumIconChips[i]
									if btn.Clicked(gtx) {
										forumDlgColorSel = cid
										a.invalidate()
									}
									return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
										return btn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
											d := gtx.Dp(unit.Dp(28))
											shape := clip.UniformRRect(image.Rect(0, 0, d, d), d/2).Push(gtx.Ops)
											paint.Fill(gtx.Ops, topicColor(cid, a.ui.p.Accent))
											shape.Pop()
											if forumDlgColorSel == cid {
												ring := clip.UniformRRect(image.Rect(0, 0, d, d), d/2).Push(gtx.Ops)
												paint.FillShape(gtx.Ops, a.ui.p.Accent, clip.Stroke{Width: float32(gtx.Dp(unit.Dp(2)))}.Op())
												ring.Pop()
											}
											return layout.Dimensions{Size: image.Pt(d, d)}
										})
									})
								}))
							}
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, chips...)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.TextButton(&forumCancelBtn, "Cancel")
									return btn.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.PrimaryButton(&forumCreateBtn, "Save")
									return btn.Layout(gtx)
								}),
							)
						})
					}),
				)
			})
		})
	})
}

// ── small drawing helpers ─────────────────────────────────────────────────

// drawTopicIcon: the colored circle with the topic initial.
func drawTopicIcon(gtx layout.Context, u *UI, t cores.ForumTopic) layout.Dimensions {
	d := gtx.Dp(unit.Dp(34))
	c := topicColor(t.ColorID, u.p.Accent)
	defer clip.Ellipse{Min: image.Pt(0, 0), Max: image.Pt(d, d)}.Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, c)
	title := t.Title
	if topicIsGeneral(t.ID) {
		title = "General"
	}
	if title != "" {
		r := []rune(title)
		lbl := u.Label(unit.Sp(13), string(r[:1]))
		lbl.Color = color.NRGBA{R: 0xFF, G: 0xFF, B: 0xFF, A: 0xFF}
		layout.Center.Layout(gtx, lbl.Layout)
	}
	return layout.Dimensions{Size: image.Pt(d, d)}
}
