package gui

// profilemusic.go — slice 206: profile music ("saved music", tdesktop Aug
// 2026). Songs pinned on user profiles: the profile panel gains a Music
// section (first track + count, tap → the full playlist view); the
// playlist view plays tracks through the shared in-app player, manages the
// OWN playlist (move up/down, remove — account.saveMusic after_id/unsave)
// and offers add-to-my-profile on other users' tracks; audio bubbles gain
// the Add/Remove-from-profile-music context item gated on the real
// own-ID state.

import (
	"fmt"
	"image"

	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

var (
	musicRows    []widget.Clickable // playlist row taps (play/pause)
	musicActBtns []widget.Clickable // per-row action: own ⋮ menu, other ＋ add
	musicBackBtn widget.Clickable
	musicList    widget.List

	// row-menu action rows (Move up / Move down / Remove)
	musicRowMenuBtns []widget.Clickable
)

func init() {
	musicList.Axis = layout.Vertical
}

// musicDlgState is the open playlist view (nil when closed).
type musicDlgState struct {
	accountID string
	peerID    string
	title     string // peer display name for the header sub-line
	own       bool   // peerID == the account's self user → manage mode
	tracks    []engine.MusicTrack
	loaded    bool
}

// musicRowMenuState is the open per-row action menu (own playlists).
type musicRowMenuState struct {
	docID string
	pos   image.Point
}

// musicDurationLabel (pure, testable): 257 → "4:17", 61 → "1:01".
func musicDurationLabel(secs int) string {
	if secs <= 0 {
		return ""
	}
	return fmt.Sprintf("%d:%02d", secs/60, secs%60)
}

// profileMusicMenuGate (pure, testable): which messages offer the
// Add-to-profile-music item — audio documents (songs, never voice notes)
// on platforms that expose the surface.
func profileMusicMenuGate(m engine.CachedMessage) bool {
	return m.HasMedia && m.MediaType == engine.MediaAudio
}

// openProfileMusic opens the playlist view for a user peer and kicks the
// engine load (cold cache fetches from the server first).
func (a *App) openProfileMusic(k chatKey, title, selfID string) {
	st := &musicDlgState{
		accountID: k.AccountID,
		peerID:    k.ChatID,
		title:     title,
		own:       selfID != "" && selfID == k.ChatID,
	}
	a.mu.Lock()
	a.musicDlg = st
	a.mu.Unlock()
	a.invalidate()
	go func() {
		tracks, err := a.eng.GetProfileMusic(k.AccountID, k.ChatID)
		if err != nil {
			a.setToast("Music: " + err.Error())
			tracks = nil
		}
		a.mu.Lock()
		if a.musicDlg != nil && a.musicDlg.accountID == k.AccountID && a.musicDlg.peerID == k.ChatID {
			a.musicDlg.tracks = tracks
			a.musicDlg.loaded = true
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// closeProfileMusic dismisses the playlist view.
func (a *App) closeProfileMusic() {
	a.mu.Lock()
	a.musicDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// toggleProfileMusicTrack plays/pauses one track through the shared
// in-app player (download-once on first play).
func (a *App) toggleProfileMusicTrack(accountID, docID string) {
	st := a.eng.MediaState()
	mine := (st.Playing || st.Paused) && st.AccountID == accountID && st.ChatID == "profilemusic" && st.MsgID == docID
	if mine {
		a.eng.TogglePauseMedia()
		a.invalidate()
		return
	}
	go func() {
		if err := a.eng.PlayProfileMusicTrack(accountID, docID); err != nil {
			a.setToast("Playback failed: " + err.Error())
			return
		}
		a.startPlaybackTickerIfNeeded()
	}()
	a.invalidate()
}

// saveProfileMusicTrack adds a track from another user's profile to the
// OWN playlist (account.saveMusic) with the tdesktop toast.
func (a *App) saveProfileMusicTrack(accountID string, track engine.MusicTrack) {
	go func() {
		if err := a.eng.SaveToProfileMusic(accountID, track); err != nil {
			a.setToast("Save failed: " + err.Error())
			return
		}
		a.setToast("Added to your profile music")
	}()
}

// applyProfileMusicRowMenu dispatches one own-playlist row action.
func (a *App) applyProfileMusicRowMenu(st *musicDlgState, docID, action string) {
	switch action {
	case "up":
		go a.reorderProfileMusic(st, docID, "")
	case "down":
		go func() {
			a.mu.Lock()
			var after string
			for i, t := range a.musicDlg.tracks {
				if t.DocID == docID && i+1 < len(a.musicDlg.tracks) {
					after = a.musicDlg.tracks[i+1].DocID
				}
			}
			dlg := a.musicDlg
			a.mu.Unlock()
			if dlg == nil || after == "" {
				return
			}
			if err := a.eng.ReorderProfileMusic(dlg.accountID, docID, after); err != nil {
				a.setToast("Move failed: " + err.Error())
				return
			}
			a.reloadProfileMusic(dlg)
		}()
	case "remove":
		go func() {
			if err := a.eng.RemoveProfileMusic(st.accountID, docID); err != nil {
				a.setToast("Remove failed: " + err.Error())
				return
			}
			a.setToast("Removed from your profile music")
			a.reloadProfileMusic(st)
		}()
	}
}

// reorderProfileMusic moves one track to the top (Move up on the first
// row is a genuine move-to-top per tdesktop's plain-save semantics).
func (a *App) reorderProfileMusic(st *musicDlgState, docID, after string) {
	if err := a.eng.ReorderProfileMusic(st.accountID, docID, after); err != nil {
		a.setToast("Move failed: " + err.Error())
		return
	}
	a.reloadProfileMusic(st)
}

// reloadProfileMusic re-reads the playlist after a mutation.
func (a *App) reloadProfileMusic(st *musicDlgState) {
	tracks, err := a.eng.GetProfileMusic(st.accountID, st.peerID)
	if err != nil {
		tracks = nil
	}
	a.mu.Lock()
	if a.musicDlg != nil && a.musicDlg.accountID == st.accountID && a.musicDlg.peerID == st.peerID {
		a.musicDlg.tracks = tracks
		a.musicDlg.loaded = true
	}
	// The panel's Music section follows (same peer).
	if a.panelChat.AccountID == st.accountID && a.panelChat.ChatID == st.peerID {
		a.panelMusic = tracks
	}
	a.mu.Unlock()
	a.invalidate()
}

// layoutProfileMusic renders the playlist view (content-pane surface).
func (a *App) layoutProfileMusic(gtx layout.Context, f frame) layout.Dimensions {
	st := f.musicDlg
	if st == nil {
		return layout.Dimensions{}
	}
	if musicBackBtn.Clicked(gtx) {
		a.closeProfileMusic()
	}
	tracks := st.tracks
	growClickables(&musicRows, len(tracks))
	growClickables(&musicActBtns, len(tracks))

	// Row taps toggle playback; action buttons open the row menu (own) or
	// save-to-my-profile (other).
	for i, tr := range tracks {
		i, tr := i, tr
		if musicRows[i].Clicked(gtx) {
			a.toggleProfileMusicTrack(st.accountID, tr.DocID)
		}
		if musicActBtns[i].Clicked(gtx) {
			if st.own {
				a.openMusicRowMenu(tr.DocID, i, gtx)
			} else {
				a.saveProfileMusicTrack(st.accountID, tr)
			}
		}
	}

	body := material.List(a.ui.Theme, &musicList).Layout(gtx, len(tracks), func(gtx layout.Context, idx int) layout.Dimensions {
		return a.musicRow(gtx, f, tracks[idx], idx, st.own)
	})

	return layout.Stack{}.Layout(gtx,
		layout.Stacked(func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
				// header: back + title + sub.
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(8), Right: unit.Dp(12)}.Layout(gtx,
						func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.IconButton(&musicBackBtn, iconNavigationBack, "Back")
									btn.Color = a.ui.p.TextDim
									return btn.Layout(gtx)
								}),
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
										return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
											layout.Rigid(func(gtx layout.Context) layout.Dimensions {
												return a.ui.H2("Music").Layout(gtx)
											}),
											layout.Rigid(func(gtx layout.Context) layout.Dimensions {
												if st.title == "" {
													return layout.Dimensions{}
												}
												return a.ui.Dim(unit.Sp(12), st.title).Layout(gtx)
											}),
										)
									})
								}),
							)
						})
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions { return a.ui.Divider(gtx) }),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					if !st.loaded {
						return a.centerLoader(gtx)
					}
					if len(tracks) == 0 {
						// Honest empty state (§1.10): a user with no pinned songs.
						return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Top: unit.Dp(24), Bottom: unit.Dp(24)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return a.ui.Dim(unit.Sp(13), "No music on this profile").Layout(gtx)
							})
						})
					}
					return body
				}),
			)
		}),
		// Own-playlist row action menu (positioned popup).
		layout.Expanded(func(gtx layout.Context) layout.Dimensions {
			if f.musicRowMenu == nil {
				return layout.Dimensions{}
			}
			return a.layoutMusicRowMenu(gtx, f)
		}),
	)

}

// musicRow renders one playlist row: play/pause glyph, title (file-name
// fallback, §1.10), performer, duration; the trailing action button (⋮ own
// / ＋ other). The active track tints.
func (a *App) musicRow(gtx layout.Context, f frame, tr engine.MusicTrack, idx int, own bool) layout.Dimensions {
	st := a.eng.MediaState()
	active := (st.Playing || st.Paused) && st.AccountID == f.musicDlg.accountID && st.ChatID == "profilemusic" && st.MsgID == tr.DocID
	title := tr.Title
	if title == "" {
		title = tr.FileName
	}
	if title == "" {
		title = "Untitled track"
	}
	return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(8), Top: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return material.ButtonLayout(a.ui.Theme, &musicRows[idx]).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						gtx.Constraints.Min.X = gtx.Dp(unit.Dp(28))
						ic := iconAVNote
						color := a.ui.p.TextDim
						if active {
							if st.Playing {
								ic = iconAVPlayCircle
							}
							color = a.ui.p.Accent
						}
						return ic.Layout(gtx, color)
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Label(unit.Sp(14), title)
									if active {
										lbl.Color = a.ui.p.Accent
									}
									return lbl.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									if tr.Performer == "" && !active {
										return layout.Dimensions{}
									}
									sub := tr.Performer
									if active && st.Playing {
										if sub != "" {
											sub += " · "
										}
										sub += "playing"
									}
									return a.ui.Dim(unit.Sp(12), sub).Layout(gtx)
								}),
							)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if dur := musicDurationLabel(tr.Duration); dur != "" {
							return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return a.ui.Dim(unit.Sp(12), dur).Layout(gtx)
							})
						}
						return layout.Dimensions{}
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.IconButton(&musicActBtns[idx], iconNavMoreVert, "Track actions")
						if !own {
							btn = a.ui.IconButton(&musicActBtns[idx], iconContentAdd, "Add to my profile music")
						}
						btn.Color = a.ui.p.TextDim
						return btn.Layout(gtx)
					}),
				)
			})
		})
}

// openMusicRowMenu opens the own-playlist row menu anchored at the row's
// action button (right edge, row Y estimate minus the list scroll — the
// popup clamps to the pane either way).
func (a *App) openMusicRowMenu(docID string, idx int, gtx layout.Context) {
	rowY := gtx.Dp(unit.Dp(64)) + idx*gtx.Dp(unit.Dp(58)) - musicList.Position.Offset
	pos := image.Pt(gtx.Constraints.Max.X-gtx.Dp(unit.Dp(210)), rowY)
	a.mu.Lock()
	a.musicRowMenu = &musicRowMenuState{docID: docID, pos: pos}
	a.mu.Unlock()
	a.invalidate()
}

// layoutMusicRowMenu draws the own-playlist row action popup.
func (a *App) layoutMusicRowMenu(gtx layout.Context, f frame) layout.Dimensions {
	m := f.musicRowMenu
	if m == nil || f.musicDlg == nil {
		return layout.Dimensions{}
	}
	items := []chatMenuAction{
		{label: "Move up", id: "up"},
		{label: "Move down", id: "down"},
		{label: "Remove", id: "remove"},
	}
	growClickables(&musicRowMenuBtns, len(items))

	menuW := gtx.Dp(unit.Dp(200))
	rowH := gtx.Dp(unit.Dp(36))
	h := gtx.Dp(unit.Dp(8)) + len(items)*rowH + gtx.Dp(unit.Dp(8))

	pos := m.pos
	if pos.X+menuW > gtx.Constraints.Max.X {
		pos.X = gtx.Constraints.Max.X - menuW
	}
	if pos.X < 0 {
		pos.X = 0
	}
	if pos.Y+h > gtx.Constraints.Max.Y {
		pos.Y = gtx.Constraints.Max.Y - h
	}
	if pos.Y < 0 {
		pos.Y = 0
	}

	var dims layout.Dimensions
	func() {
		defer op.Offset(pos).Push(gtx.Ops).Pop()
		gtx.Constraints = layout.Constraints{Max: image.Pt(menuW, h), Min: image.Pt(menuW, h)}
		dims = roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
			children := make([]layout.FlexChild, 0, len(items)+2)
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Dimensions{Size: image.Pt(menuW, gtx.Dp(unit.Dp(4)))}
			}))
			for i := range items {
				i := i
				children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := &musicRowMenuBtns[i]
					if btn.Clicked(gtx) {
						st := *f.musicDlg
						docID := m.docID
						a.closeMusicRowMenu()
						a.applyProfileMusicRowMenu(&st, docID, items[i].id)
					}
					gtx.Constraints.Min.Y = rowH
					return musicRowMenuRow(gtx, a, btn, items[i], rowH)
				}))
			}
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Dimensions{Size: image.Pt(menuW, gtx.Dp(unit.Dp(4)))}
			}))
			layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
			return layout.Dimensions{Size: image.Pt(menuW, h)}
		})
	}()
	return dims
}

// musicRowMenuRow renders one menu row (destructive rows tinted).
func musicRowMenuRow(gtx layout.Context, a *App, btn *widget.Clickable, item chatMenuAction, rowH int) layout.Dimensions {
	bl := material.ButtonLayout(a.ui.Theme, btn)
	bl.Background = a.ui.p.Surface
	bl.CornerRadius = 8
	return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			color := a.ui.p.Text
			if item.id == "remove" {
				color = a.ui.p.Error
			}
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					ic := iconMgrUp
					switch item.id {
					case "down":
						ic = iconMgrDown
					case "remove":
						ic = iconActionDelete
					}
					return ic.Layout(gtx, color)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := material.Body2(a.ui.Theme, item.label)
						lbl.Color = color
						return lbl.Layout(gtx)
					})
				}),
			)
		})
	})
}

// closeMusicRowMenu dismisses the row menu.
func (a *App) closeMusicRowMenu() {
	a.mu.Lock()
	a.musicRowMenu = nil
	a.mu.Unlock()
	a.invalidate()
}

// onProfileMusicChanged reloads the affected surfaces after an
// own-playlist mutation (engine event): the open playlist view (if it
// targets the peer), the panel's Music section, and re-reads nothing else
// — the engine already refreshed its caches before emitting.
func (a *App) onProfileMusicChanged(accountID, peerID string) {
	go func() {
		a.mu.Lock()
		dlg := a.musicDlg
		panelK := a.panelChat
		a.mu.Unlock()
		if dlg != nil && dlg.accountID == accountID && dlg.peerID == peerID {
			a.reloadProfileMusic(dlg)
			return
		}
		if panelK.AccountID == accountID && panelK.ChatID == peerID && peerID != "" {
			if tracks, err := a.eng.GetProfileMusic(accountID, peerID); err == nil {
				a.mu.Lock()
				a.panelMusic = tracks
				a.mu.Unlock()
				a.invalidate()
			}
		}
	}()
}

// centerLoader is the shared centered spinner (loading pane body).
func (a *App) centerLoader(gtx layout.Context) layout.Dimensions {
	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		ld := material.Loader(a.ui.Theme)
		ld.Color = a.ui.p.Accent
		return ld.Layout(gtx)
	})
}

// panelMusicSection renders the profile panel's Music section (tdesktop's
// MusicButton: the first song + a tap-through to the playlist). Hidden
// when the peer has no music (§1.10 — no dead UI).
func (a *App) panelMusicSection(gtx layout.Context, f frame) []layout.FlexChild {
	tracks := f.panelMusic
	if len(tracks) == 0 {
		return nil
	}
	first := tracks[0]
	title := first.Title
	if title == "" {
		title = first.FileName
	}
	if title == "" {
		title = "Untitled track"
	}
	if a.musicMenuBtn.Clicked(gtx) {
		k := f.panelChat
		a.openProfileMusic(k, panelTitleOf(f), selfIDOf(f, k.AccountID))
	}
	count := fmt.Sprintf("%d track", len(tracks))
	if len(tracks) != 1 {
		count += "s"
	}
	sub := first.Performer
	if sub != "" {
		sub += " · "
	}
	sub += count

	var children []layout.FlexChild
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Music")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return material.ButtonLayout(a.ui.Theme, &a.musicMenuBtn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						gtx.Constraints.Min.X = gtx.Dp(unit.Dp(20))
						return iconAVNote.Layout(gtx, a.ui.p.Accent)
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return a.ui.Label(unit.Sp(14), title).Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return a.ui.Dim(unit.Sp(12), sub).Layout(gtx)
								}),
							)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return iconNavChevronRight.Layout(gtx, a.ui.p.TextDim)
					}),
				)
			})
		})
	}))
	return children
}

// panelTitleOf resolves the open panel peer's display name.
func panelTitleOf(f frame) string {
	if chat, ok := panelChatOf(f); ok && chat.Title != "" {
		return chat.Title
	}
	if f.profile != nil && f.profile.DisplayName != "" {
		return f.profile.DisplayName
	}
	return ""
}
