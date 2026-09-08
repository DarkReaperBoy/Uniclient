package gui

import (
	"strings"

	"gioui.org/font"
	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Server-synced folder tabs (AyuGram parity §2 "Folder tabs above list"):
// when a single account is scoped and its core exposes folders, the tab row
// renders All / Unread / the account's real server folders / a "+" create
// tab; otherwise the smart fallback tabs (People/Groups/Channels). Filtering
// follows Telegram dialog-filter rules: explicit includes win, exclusions
// apply to flag matches.

// folderTab kinds.
const (
	folderTabAll = iota
	folderTabUnread
	folderTabServer
	folderTabNew
	folderTabPeople
	folderTabGroups
	folderTabChannels
)

// folderTab is one rendered tab.
type folderTab struct {
	name   string
	kind   int
	folder *engine.FolderInfo
}

// buildFolderTabs derives the tab row for the current scope.
func buildFolderTabs(acctFilter string, folders []engine.FolderInfo, supported bool) []folderTab {
	tabs := []folderTab{
		{name: "All", kind: folderTabAll},
		{name: "Unread", kind: folderTabUnread},
	}
	if acctFilter != "" && supported {
		for i := range folders {
			f := folders[i]
			name := f.Name
			if name == "" {
				name = "Folder"
			}
			if f.Emoticon != "" {
				name = f.Emoticon + " " + name
			}
			tabs = append(tabs, folderTab{name: name, kind: folderTabServer, folder: &f})
		}
		tabs = append(tabs, folderTab{name: "+", kind: folderTabNew})
		return tabs
	}
	return append(tabs,
		folderTab{name: "People", kind: folderTabPeople},
		folderTab{name: "Groups", kind: folderTabGroups},
		folderTab{name: "Channels", kind: folderTabChannels},
	)
}

// tabMatches reports whether a chat shows under one tab.
func tabMatches(t folderTab, c engine.ChatInfo) bool {
	switch t.kind {
	case folderTabAll:
		return true
	case folderTabUnread:
		return c.UnreadCount > 0
	case folderTabPeople:
		return chatKind(c) == "people"
	case folderTabGroups:
		return chatKind(c) == "groups"
	case folderTabChannels:
		return chatKind(c) == "channels"
	case folderTabServer:
		if t.folder == nil {
			return true
		}
		return folderContains(*t.folder, c)
	}
	return true
}

// folderContains applies Telegram dialog-filter rules.
func folderContains(f engine.FolderInfo, c engine.ChatInfo) bool {
	for _, id := range f.ChatIDs {
		if id == c.ChatID {
			return true
		}
	}
	for _, id := range f.ExcludeChatIDs {
		if id == c.ChatID {
			return false
		}
	}
	if f.ExcludeArchived && c.IsArchived {
		return false
	}
	if f.ExcludeMuted && c.IsMuted {
		return false
	}
	if f.ExcludeRead && c.UnreadCount == 0 {
		return false
	}
	kind := chatKind(c)
	if (f.Contacts && c.IsContact) ||
		(f.NonContacts && kind == "people" && !c.IsContact) ||
		(f.Groups && kind == "groups") ||
		(f.Channels && kind == "channels") ||
		(f.Bots && c.IsBot) {
		return true
	}
	return false
}

// ── folder state actions ──────────────────────────────────────────────────

// refreshFolders loads the scoped account's server folders (async).
func (a *App) refreshFolders(accountID string) {
	if accountID == "" {
		return
	}
	go func() {
		folders, err := a.eng.GetFolders(accountID)
		supported := a.eng.FoldersSupported(accountID)
		a.mu.Lock()
		if err == nil && a.acctFilter == accountID {
			a.folders = folders
			a.foldersSupported = supported
			if a.folder >= len(buildFolderTabs(accountID, folders, supported)) {
				a.folder = 0
			}
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// openFolderDlg opens the create-folder dialog for the scoped account.
func (a *App) openFolderDlg() {
	a.mu.Lock()
	acc := a.acctFilter
	a.folderDlg = &folderDlgState{accountID: acc}
	a.mu.Unlock()
	folderNameEditor.SetText("")
	a.invalidate()
}

// closeFolderDlg dismisses the dialog.
func (a *App) closeFolderDlg() {
	a.mu.Lock()
	a.folderDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// submitFolderDlg creates the folder (async) and refreshes the tabs.
func (a *App) submitFolderDlg() {
	name := strings.TrimSpace(folderNameEditor.Text())
	if name == "" {
		return
	}
	a.mu.Lock()
	st := folderDlgState{}
	if a.folderDlg != nil {
		st = *a.folderDlg
	}
	a.folderDlg = nil
	a.mu.Unlock()
	a.invalidate()
	if st.accountID == "" {
		return
	}
	go func() {
		if _, err := a.eng.CreateFolder(st.accountID, name, nil, nil); err != nil {
			a.setToast("Create folder: " + err.Error())
		} else {
			a.setToast("Folder created")
		}
		a.refreshFolders(st.accountID)
	}()
}

// ── folder dialog ─────────────────────────────────────────────────────────

// folderDlgState is the open create-folder dialog.
type folderDlgState struct {
	accountID string
}

var (
	folderDlgCancel  widget.Clickable
	folderDlgCreate  widget.Clickable
	folderNameEditor widget.Editor
)

func init() {
	folderNameEditor.SingleLine = true
}

// layoutFolderDialog renders the centered create-folder card (replaces the
// content pane; the sidebar stays interactive).
func (a *App) layoutFolderDialog(gtx layout.Context, f frame) layout.Dimensions {
	if folderDlgCancel.Clicked(gtx) {
		a.closeFolderDlg()
	}
	if folderDlgCreate.Clicked(gtx) {
		a.submitFolderDlg()
	}
	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(320))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(18)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.H3("New folder")
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(12), "Chats can be added from the folder editor later")
						return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(12)}.Layout(gtx, lbl.Layout)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
							return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								ed := a.ui.Editor(&folderNameEditor, "Folder name")
								return ed.Layout(gtx)
							})
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.TextButton(&folderDlgCancel, "Cancel")
									return btn.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.PrimaryButton(&folderDlgCreate, "Create")
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

// layoutFolderTabRow renders one folder tab (server/smart/new).
func layoutFolderTab(gtx layout.Context, a *App, btn *widget.Clickable, tab folderTab, active bool) layout.Dimensions {
	bg := color00
	txt := a.ui.p.TextDim
	if active {
		bg = a.ui.p.AccentDim
		txt = a.ui.p.Text
	}
	return roundedFill(gtx, bg, 14, func(gtx layout.Context) layout.Dimensions {
		return material.ButtonLayout(a.ui.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(5), Bottom: unit.Dp(5), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Label(unit.Sp(13), tab.name)
				lbl.Color = txt
				if active {
					lbl.Font.Weight = font.SemiBold
				}
				return lbl.Layout(gtx)
			})
		})
	})
}
