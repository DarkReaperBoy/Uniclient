package gui

import (
	"errors"
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/cores"
	"uniclient/engine"
)

const musicAttachPreviewRows = 6

var (
	musicAttachBackBtn    widget.Clickable
	musicAttachFilesBtn   widget.Clickable
	musicAttachShowAllBtn widget.Clickable
	musicAttachSendBtn    widget.Clickable
	musicAttachList       widget.List
	musicAttachRows       []widget.Clickable
	musicAttachQueryEd    widget.Editor
)

func init() {
	musicAttachList.Axis = layout.Vertical
	musicAttachQueryEd.SingleLine = true
}

type musicAttachDlgState struct {
	accountID string
	chatID    string
	supported bool
	tracks    []engine.MusicTrack
	loaded    bool
	err       string
	showAll   bool
	sel       map[string]bool
}

func musicAttachFilter(tracks []engine.MusicTrack, query string) []engine.MusicTrack {
	query = strings.ToLower(strings.TrimSpace(query))
	if query == "" || tracks == nil {
		return tracks
	}
	var out []engine.MusicTrack
	for _, tr := range tracks {
		if strings.Contains(strings.ToLower(tr.Title), query) ||
			strings.Contains(strings.ToLower(tr.Performer), query) ||
			strings.Contains(strings.ToLower(tr.FileName), query) {
			out = append(out, tr)
		}
	}
	return out
}

func musicAttachVisible(tracks []engine.MusicTrack, showAll bool) []engine.MusicTrack {
	if showAll || len(tracks) <= musicAttachPreviewRows {
		return tracks
	}
	return tracks[:musicAttachPreviewRows]
}

func musicAttachSendLabel(n int) string {
	if n <= 0 {
		return "Send"
	}
	return "Send " + itoa(n)
}

func musicAttachSendOrder(tracks []engine.MusicTrack, sel map[string]bool) []engine.MusicTrack {
	if len(sel) == 0 {
		return nil
	}
	var out []engine.MusicTrack
	for _, tr := range tracks {
		if sel[tr.DocID] {
			out = append(out, tr)
		}
	}
	return out
}

func (a *App) openMusicAttach() {
	a.mu.Lock()
	k := a.selected
	a.attachMenuOpen = false
	var st *musicAttachDlgState
	if k != nil {
		st = &musicAttachDlgState{
			accountID: k.AccountID,
			chatID:    k.ChatID,
			supported: true,
			sel:       map[string]bool{},
		}
	}
	a.musicAttachDlg = st
	a.mu.Unlock()
	a.invalidate()
	if st == nil {
		return
	}
	account, chat := st.accountID, st.chatID
	go func() {
		tracks, err := a.eng.SavedMusicTracks(account)
		a.mu.Lock()
		if a.musicAttachDlg == nil || a.musicAttachDlg.accountID != account || a.musicAttachDlg.chatID != chat {
			a.mu.Unlock()
			return
		}
		if errors.Is(err, cores.ErrNotSupported) {
			a.musicAttachDlg.supported = false
			a.musicAttachDlg.loaded = true
		} else if err != nil {
			a.musicAttachDlg.err = err.Error()
			a.musicAttachDlg.loaded = true
		} else {
			a.musicAttachDlg.tracks = tracks
			a.musicAttachDlg.loaded = true
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

func (a *App) closeMusicAttach() {
	a.mu.Lock()
	a.musicAttachDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) sendMusicAttachSelection(f frame) {
	st := f.musicAttachDlg
	if st == nil {
		return
	}
	order := musicAttachSendOrder(musicAttachFilter(st.tracks, musicAttachQueryEd.Text()), st.sel)
	if len(order) == 0 {
		return
	}
	caption := strings.TrimSpace(a.wid.composer.Text())
	if caption != "" {
		a.wid.composer.SetText("")
	}
	account, chat := st.accountID, st.chatID
	a.closeMusicAttach()
	a.mu.Lock()
	a.sending = true
	a.mu.Unlock()
	a.invalidate()
	go func() {
		defer func() {
			a.mu.Lock()
			a.sending = false
			a.mu.Unlock()
			a.invalidate()
		}()
		for i, tr := range order {
			cap := ""
			if i == 0 {
				cap = caption
			}
			if err := a.eng.SendSavedMusicTrack(account, chat, tr.DocID, cap); err != nil {
				a.setToast("Send failed: " + err.Error())
				return
			}
		}
	}()
}

func (a *App) layoutMusicAttach(gtx layout.Context, f frame) layout.Dimensions {
	st := f.musicAttachDlg
	if st == nil {
		return layout.Dimensions{}
	}
	if musicAttachBackBtn.Clicked(gtx) {
		a.closeMusicAttach()
	}
	if musicAttachFilesBtn.Clicked(gtx) {
		a.closeMusicAttach()
		a.pickAndSendExts(musicExts)
	}
	if musicAttachShowAllBtn.Clicked(gtx) {
		a.mu.Lock()
		if a.musicAttachDlg != nil {
			a.musicAttachDlg.showAll = !a.musicAttachDlg.showAll
		}
		a.mu.Unlock()
		a.invalidate()
	}
	if musicAttachSendBtn.Clicked(gtx) {
		a.sendMusicAttachSelection(f)
	}

	filtered := musicAttachFilter(st.tracks, musicAttachQueryEd.Text())
	visible := musicAttachVisible(filtered, st.showAll)
	growClickables(&musicAttachRows, len(visible))
	for i, tr := range visible {
		if musicAttachRows[i].Clicked(gtx) {
			a.mu.Lock()
			if a.musicAttachDlg != nil && a.musicAttachDlg.accountID == st.accountID &&
				a.musicAttachDlg.chatID == st.chatID {
				if a.musicAttachDlg.sel[tr.DocID] {
					delete(a.musicAttachDlg.sel, tr.DocID)
				} else {
					a.musicAttachDlg.sel[tr.DocID] = true
				}
			}
			a.mu.Unlock()
			a.invalidate()
		}
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(8), Right: unit.Dp(12)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.IconButton(&musicAttachBackBtn, iconNavigationBack, "Back")
							btn.Color = a.ui.p.TextDim
							return btn.Layout(gtx)
						}),
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return a.ui.H2("Music").Layout(gtx)
							})
						}),
					)
				})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions { return a.ui.Divider(gtx) }),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.musicAttachFileRow(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions { return a.ui.Divider(gtx) }),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			if !st.supported {
				return layout.Dimensions{}
			}
			if st.err != "" {
				return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(24), Bottom: unit.Dp(24)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return a.ui.Dim(unit.Sp(13), "Saved music unavailable: "+st.err).Layout(gtx)
					})
				})
			}
			return a.musicAttachSavedSection(gtx, st, filtered, visible)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.musicAttachSendBar(gtx, st, filtered)
		}),
	)
}

func (a *App) musicAttachFileRow(gtx layout.Context) layout.Dimensions {
	return layout.Inset{Left: unit.Dp(8), Right: unit.Dp(8), Top: unit.Dp(6), Bottom: unit.Dp(6)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return material.ButtonLayout(a.ui.Theme, &musicAttachFilesBtn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(10), Bottom: unit.Dp(10), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx,
					func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								gtx.Constraints.Min.X = gtx.Dp(unit.Dp(28))
								return iconAVNote.Layout(gtx, a.ui.p.TextDim)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return a.ui.H3("Choose from files").Layout(gtx)
								})
							}),
						)
					})
			})
		})
}

func (a *App) musicAttachSavedSection(gtx layout.Context, st *musicAttachDlgState, filtered, visible []engine.MusicTrack) layout.Dimensions {
	header := layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Left: unit.Dp(14), Top: unit.Dp(8), Bottom: unit.Dp(2)}.Layout(gtx,
			func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return a.ui.Dim(unit.Sp(12), "Saved Music").Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if len(filtered) <= musicAttachPreviewRows {
							return layout.Dimensions{}
						}
						lbl := material.Button(a.ui.Theme, &musicAttachShowAllBtn, "Show all")
						lbl.Inset = layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(8), Right: unit.Dp(8)}
						return lbl.Layout(gtx)
					}),
				)
			})
	})

	query := layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12), Top: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx,
			func(gtx layout.Context) layout.Dimensions {
				ed := material.Editor(a.ui.Theme, &musicAttachQueryEd, "Search music")
				ed.TextSize = unit.Sp(14)
				return ed.Layout(gtx)
			})
	})

	body := material.List(a.ui.Theme, &musicAttachList).Layout(gtx, len(visible), func(gtx layout.Context, idx int) layout.Dimensions {
		return a.musicAttachRow(gtx, visible[idx], idx, st)
	})

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		header,
		query,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions { return a.ui.Divider(gtx) }),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			if !st.loaded {
				return a.centerLoader(gtx)
			}
			if len(filtered) == 0 {
				msg := "No saved music"
				if musicAttachQueryEd.Text() != "" {
					msg = "Nothing found"
				}
				return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(24), Bottom: unit.Dp(24)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return a.ui.Dim(unit.Sp(13), msg).Layout(gtx)
					})
				})
			}
			return body
		}),
	)
}

func (a *App) musicAttachRow(gtx layout.Context, tr engine.MusicTrack, idx int, st *musicAttachDlgState) layout.Dimensions {
	title := tr.Title
	if title == "" {
		title = tr.FileName
	}
	if title == "" {
		title = "Untitled track"
	}
	return layout.Inset{Left: unit.Dp(8), Right: unit.Dp(8), Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return material.ButtonLayout(a.ui.Theme, &musicAttachRows[idx]).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx,
					func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								gtx.Constraints.Min.X = gtx.Dp(unit.Dp(24))
								if st.sel[tr.DocID] {
									return iconToggleCheckBox.Layout(gtx, a.ui.p.Accent)
								}
								return iconToggleCheckBoxBlank.Layout(gtx, a.ui.p.TextDim)
							}),
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											return a.ui.H3(title).Layout(gtx)
										}),
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											sub := tr.Performer
											if sub == "" {
												sub = "Unknown artist"
											}
											return a.ui.Dim(unit.Sp(12), sub).Layout(gtx)
										}),
									)
								})
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								if d := musicDurationLabel(tr.Duration); d != "" {
									return a.ui.Dim(unit.Sp(12), d).Layout(gtx)
								}
								return layout.Dimensions{}
							}),
						)
					})
			})
		})
}

func (a *App) musicAttachSendBar(gtx layout.Context, st *musicAttachDlgState, filtered []engine.MusicTrack) layout.Dimensions {
	n := len(musicAttachSendOrder(filtered, st.sel))
	return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		btn := material.Button(a.ui.Theme, &musicAttachSendBtn, musicAttachSendLabel(n))
		if n == 0 || !st.supported {
			btn.Background = a.ui.p.TextDim
		}
		return btn.Layout(gtx)
	})
}
