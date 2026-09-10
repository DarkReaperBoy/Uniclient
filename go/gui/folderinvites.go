package gui

import (
	"image"
	"strings"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/cores"
	"uniclient/engine"
)

// Folder invite links (AyuGram parity, matrix "Folder tabs above list":
// invite links row): the chatlist-share dialog for a server folder —
// lists the folder's exported invite links (engine
// GetFolderInviteLinks), tapping a link copies it (clipboard hop, like
// copy-message-link), and "Create link" exports a fresh one for the
// folder's current chats (engine CreateFolderInviteLink).

// folderInvitesState is the open invite-links dialog.
type folderInvitesState struct {
	accountID string
	folder    engine.FolderInfo
	links     []cores.ChatlistInviteLink
	loaded    bool
	err       string
}

var (
	folderInvitesCloseBtn  widget.Clickable
	folderInvitesCreateBtn widget.Clickable
	folderInvitesRowBtns   []widget.Clickable
)

// folderInvitesKeyTag receives key events across the dialog.
var folderInvitesKeyTag = new(struct{})

// openFolderInvites opens the dialog and loads the links (async).
func (a *App) openFolderInvites(folder engine.FolderInfo, accountID string) {
	st := &folderInvitesState{accountID: accountID, folder: folder}
	a.mu.Lock()
	a.folderInvites = st
	a.mu.Unlock()
	a.invalidate()
	go func() {
		links, err := a.eng.GetFolderInviteLinks(accountID, folderIDInt(folder.ID))
		a.mu.Lock()
		if a.folderInvites != st {
			a.mu.Unlock()
			return // dialog was closed meanwhile
		}
		if err != nil {
			st.err = err.Error()
		} else {
			st.links, st.loaded = links, true
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// closeFolderInvites dismisses the dialog.
func (a *App) closeFolderInvites() {
	a.mu.Lock()
	a.folderInvites = nil
	a.mu.Unlock()
	a.invalidate()
}

// createFolderInvite exports a new link for the folder's current chats.
func (a *App) createFolderInvite(st *folderInvitesState) {
	accountID, folder := st.accountID, st.folder
	go func() {
		_, err := a.eng.CreateFolderInviteLink(accountID, folderIDInt(folder.ID), folder.Name, folder.ChatIDs)
		if err != nil {
			a.setToast("Create link failed: " + err.Error())
			return
		}
		a.setToast("Link created")
		// Reload so the new link shows up in the list.
		links, err := a.eng.GetFolderInviteLinks(accountID, folderIDInt(folder.ID))
		a.mu.Lock()
		if a.folderInvites == st && err == nil {
			st.links, st.loaded, st.err = links, true, ""
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// folderIDInt parses a FolderInfo.ID ("1", "2", …) — 0 when malformed.
func folderIDInt(id string) int {
	n := 0
	for _, c := range strings.TrimSpace(id) {
		if c < '0' || c > '9' {
			return 0
		}
		n = n*10 + int(c-'0')
		if n > 1<<30 {
			return 0
		}
	}
	return n
}

// layoutFolderInvites renders the dialog (content-pane replacement, same
// placement as the folder dialog): centered card with the link list,
// create button, and close.
func (a *App) layoutFolderInvites(gtx layout.Context, f frame) layout.Dimensions {
	st := f.folderInvites
	growClickables(&folderInvitesRowBtns, len(st.links))

	// Esc closes the dialog (self-handled, mirrors the folder dialog).
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, folderInvitesKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeFolderInvites()
		}
	}

	if folderInvitesCloseBtn.Clicked(gtx) {
		a.closeFolderInvites()
	}
	if folderInvitesCreateBtn.Clicked(gtx) {
		a.createFolderInvite(st)
	}
	for i := range st.links {
		if folderInvitesRowBtns[i].Clicked(gtx) {
			a.copyTextSoon(st.links[i].URL)
		}
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(360))
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(420))
		gtx.Constraints.Min = image.Point{}
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					// Title
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						title := "Invite links"
						if st.folder.Name != "" {
							title = "Invite links · " + st.folder.Name
						}
						lbl := a.ui.H3(title)
						return lbl.Layout(gtx)
					}),
					// Subtitle
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(12), "Share this folder's chats with one link")
						lbl.Color = a.ui.p.TextFaint
						return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(10)}.Layout(gtx, lbl.Layout)
					}),
					// Link list
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return a.folderInvitesList(gtx, st)
					}),
					// Create + Close row
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									bl := material.Button(a.ui.Theme, &folderInvitesCreateBtn, "Create link")
									bl.Background = a.ui.p.Accent
									bl.CornerRadius = 10
									return bl.Layout(gtx)
								}),
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									return layout.Dimensions{}
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									bl := material.Button(a.ui.Theme, &folderInvitesCloseBtn, "Close")
									bl.Background = a.ui.p.SurfaceHi
									bl.Color = a.ui.p.Text
									bl.CornerRadius = 10
									return bl.Layout(gtx)
								}),
							)
						})
					}),
				)
			})
		})
	})
}

// folderInvitesList renders the link rows (or loading/empty/error states).
func (a *App) folderInvitesList(gtx layout.Context, st *folderInvitesState) layout.Dimensions {
	if st.err != "" && !st.loaded {
		return a.centeredStateLabel(gtx, "Failed to load links")
	}
	if !st.loaded {
		return a.centeredStateLabel(gtx, "Loading…")
	}
	if len(st.links) == 0 {
		return a.centeredStateLabel(gtx, "No invite links yet")
	}
	children := make([]layout.FlexChild, 0, len(st.links))
	for i := range st.links {
		i := i
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				btn := &folderInvitesRowBtns[i]
				bl := material.ButtonLayout(a.ui.Theme, btn)
				bl.Background = a.ui.p.SurfaceHi
				bl.CornerRadius = 10
				return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						title := st.links[i].Title
						if title == "" {
							title = "Folder link"
						}
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), title)
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								url := st.links[i].URL
								if len(url) > 42 {
									url = url[:42] + "…"
								}
								lbl := a.ui.Dim(unit.Sp(12), url)
								lbl.Color = a.ui.p.Accent
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								meta := "shared chats: " + itoa(st.links[i].PeerCount)
								lbl := a.ui.Dim(unit.Sp(11), meta)
								lbl.Color = a.ui.p.TextFaint
								return lbl.Layout(gtx)
							}),
						)
					})
				})
			})
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// centeredStateLabel is a centered one-line state text for list areas.
func (a *App) centeredStateLabel(gtx layout.Context, text string) layout.Dimensions {
	lbl := a.ui.Dim(unit.Sp(13), text)
	lbl.Color = a.ui.p.TextFaint
	return layout.Center.Layout(gtx, lbl.Layout)
}
