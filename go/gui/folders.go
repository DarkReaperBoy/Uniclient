package gui

import (
	"image"
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
func buildFolderTabs(acctFilter string, folders []engine.FolderInfo, supported, hideAll bool) []folderTab {
	tabs := []folderTab{
		{name: "Unread", kind: folderTabUnread},
	}
	if !hideAll {
		// AyuGram "hide all chats folder": the All tab drops, the first
		// real folder becomes the default view.
		tabs = append([]folderTab{{name: "All", kind: folderTabAll}}, tabs...)
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
			if a.folder >= len(buildFolderTabs(accountID, folders, supported, false)) {
				a.folder = 0
			}
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// openFolderDlg opens the create-folder dialog (full editor: chat picker,
// type flags, exclusions, emoticon) for the scoped account.
func (a *App) openFolderDlg() {
	a.mu.Lock()
	acc := a.acctFilter
	a.mu.Unlock()
	a.openFolderDlgFor(acc)
}

// openFolderDlgFor opens the create dialog for an explicit account
// (the folders manager opens it for its own account — the sidebar's
// acctFilter is not the manager's business).
func (a *App) openFolderDlgFor(acc string) {
	st := &folderDlgState{
		accountID: acc,
		include:   map[string]bool{},
		exclude:   map[string]bool{},
	}
	syncFolderDlgSwitches(st)
	a.mu.Lock()
	a.folderDlg = st
	a.mu.Unlock()
	folderNameEditor.SetText("")
	folderDlgEmoticon = ""
	a.invalidate()
}

// openFolderDlgEdit opens the editor on an existing folder (right-click a
// folder tab, AyuGram edit-filter).
func (a *App) openFolderDlgEdit(folder engine.FolderInfo) {
	a.mu.Lock()
	cur := a.acctFilter
	a.mu.Unlock()
	a.openFolderDlgEditFor(cur, folder)
}

// openFolderDlgEditFor opens the editor on an existing folder for an
// explicit account (the folders manager).
func (a *App) openFolderDlgEditFor(accountID string, folder engine.FolderInfo) {
	st := &folderDlgState{
		accountID:    accountID,
		editing:      folder.ID,
		include:      map[string]bool{},
		exclude:      map[string]bool{},
		contacts:     folder.Contacts,
		nonContacts:  folder.NonContacts,
		groups:       folder.Groups,
		channels:     folder.Channels,
		bots:         folder.Bots,
		exclMuted:    folder.ExcludeMuted,
		exclRead:     folder.ExcludeRead,
		exclArchived: folder.ExcludeArchived,
	}
	for _, id := range folder.ChatIDs {
		st.include[id] = true
	}
	for _, id := range folder.ExcludeChatIDs {
		st.exclude[id] = true
	}
	syncFolderDlgSwitches(st)
	a.mu.Lock()
	a.folderDlg = st
	a.mu.Unlock()
	folderNameEditor.SetText(folder.Name)
	folderDlgEmoticon = folder.Emoticon
	a.invalidate()
}

// closeFolderDlg dismisses the dialog.
func (a *App) closeFolderDlg() {
	a.mu.Lock()
	a.folderDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// cycleFolderDlgChat advances a chat's picker state: none → include →
// exclude → none (AyuGram's include/exclude pickers combined in one row).
func (a *App) cycleFolderDlgChat(chatID string) {
	a.mu.Lock()
	if d := a.folderDlg; d != nil {
		switch {
		case d.include[chatID]:
			delete(d.include, chatID)
			d.exclude[chatID] = true
		case d.exclude[chatID]:
			delete(d.exclude, chatID)
		default:
			d.include[chatID] = true
		}
	}
	a.mu.Unlock()
	a.invalidate()
}

// setFolderDlgFlag flips one dialog flag.
func (a *App) setFolderDlgFlag(flag string, on bool) {
	a.mu.Lock()
	if d := a.folderDlg; d != nil {
		switch flag {
		case "contacts":
			d.contacts = on
		case "nonContacts":
			d.nonContacts = on
		case "groups":
			d.groups = on
		case "channels":
			d.channels = on
		case "bots":
			d.bots = on
		case "exclMuted":
			d.exclMuted = on
		case "exclRead":
			d.exclRead = on
		case "exclArchived":
			d.exclArchived = on
		}
	}
	a.mu.Unlock()
	a.invalidate()
}

// setFolderDlgEmoticon picks the tab emoticon.
func (a *App) setFolderDlgEmoticon(e string) {
	folderDlgEmoticon = e
	a.invalidate()
}

// deleteFolderDlg removes the edited folder (async).
func (a *App) deleteFolderDlg() {
	a.mu.Lock()
	st := folderDlgState{}
	if a.folderDlg != nil {
		st = *a.folderDlg
	}
	a.folderDlg = nil
	a.mu.Unlock()
	a.invalidate()
	if st.accountID == "" || st.editing == "" {
		return
	}
	go func() {
		if err := a.eng.DeleteFolder(st.accountID, st.editing); err != nil {
			a.setToast("Delete folder: " + err.Error())
		} else {
			a.setToast("Folder deleted")
		}
		a.refreshFolders(st.accountID)
	}()
}

// submitFolderDlg creates or saves the folder (async) and refreshes tabs.
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
	// Ordered by the sidebar's chat order.
	var chatIDs, exclIDs []string
	for _, c := range a.chatListSnapshot() {
		if c.AccountID != st.accountID {
			continue
		}
		if st.include[c.ChatID] {
			chatIDs = append(chatIDs, c.ChatID)
		}
		if st.exclude[c.ChatID] {
			exclIDs = append(exclIDs, c.ChatID)
		}
	}
	opts := &engine.CreateFolderOpts{
		Contacts:        st.contacts,
		NonContacts:     st.nonContacts,
		Groups:          st.groups,
		Channels:        st.channels,
		Bots:            st.bots,
		ExcludeMuted:    st.exclMuted,
		ExcludeRead:     st.exclRead,
		ExcludeArchived: st.exclArchived,
		ExcludeChatIDs:  exclIDs,
		Emoticon:        folderDlgEmoticon,
	}
	go func() {
		if st.editing != "" {
			if _, err := a.eng.EditFolder(st.accountID, st.editing, name, chatIDs, opts); err != nil {
				a.setToast("Save folder: " + err.Error())
			} else {
				a.setToast("Folder saved")
			}
		} else {
			if _, err := a.eng.CreateFolder(st.accountID, name, chatIDs, opts); err != nil {
				a.setToast("Create folder: " + err.Error())
			} else {
				a.setToast("Folder created")
			}
		}
		a.refreshFolders(st.accountID)
	}()
}

// ── folder dialog ─────────────────────────────────────────────────────────

// folderDlgState is the open folder editor (create or edit).
type folderDlgState struct {
	accountID                                     string
	editing                                       string // folder ID when editing ("" = create)
	include                                       map[string]bool
	exclude                                       map[string]bool
	contacts, nonContacts, groups, channels, bots bool
	exclMuted, exclRead, exclArchived             bool
}

var (
	folderDlgCancel   widget.Clickable
	folderDlgCreate   widget.Clickable
	folderDlgDelete   widget.Clickable
	folderNameEditor  widget.Editor
	folderDlgChatBtns []widget.Clickable
	folderDlgEmoBtns  []widget.Clickable
	folderDlgEmoticon string // frame-thread selected emoticon
	folderDlgSwitches = map[string]*widget.Bool{}
)

func init() {
	folderNameEditor.SingleLine = true
}

// folderDlgEmoticons mirrors Telegram's filter emoticon set (first pass).
var folderDlgEmoticons = []string{"", "🌟", "💬", "✈️", "📂", "❤️", "🎮", "📌"}

// folderDlgFlags: switch key + label (type + exclusion rules).
var folderDlgFlags = []struct{ key, label string }{
	{"contacts", "Contacts"},
	{"nonContacts", "Non-contacts"},
	{"groups", "Groups"},
	{"channels", "Channels"},
	{"bots", "Bots"},
	{"exclMuted", "Exclude muted"},
	{"exclRead", "Exclude read"},
	{"exclArchived", "Exclude archived"},
}

func folderDlgSwitch(key string) *widget.Bool {
	if s, ok := folderDlgSwitches[key]; ok {
		return s
	}
	if len(folderDlgSwitches) > 16 {
		folderDlgSwitches = make(map[string]*widget.Bool)
	}
	s := new(widget.Bool)
	folderDlgSwitches[key] = s
	return s
}

// syncFolderDlgSwitches pushes the dialog state into the switch widgets
// (called at open; the switches drive state afterwards).
func syncFolderDlgSwitches(st *folderDlgState) {
	vals := map[string]bool{
		"contacts": st.contacts, "nonContacts": st.nonContacts,
		"groups": st.groups, "channels": st.channels, "bots": st.bots,
		"exclMuted": st.exclMuted, "exclRead": st.exclRead, "exclArchived": st.exclArchived,
	}
	for k, v := range vals {
		folderDlgSwitch(k).Value = v
	}
}

// chatListSnapshot copies the chat list for the submit ordering.
func (a *App) chatListSnapshot() []engine.ChatInfo {
	a.mu.Lock()
	defer a.mu.Unlock()
	out := make([]engine.ChatInfo, len(a.chats))
	copy(out, a.chats)
	return out
}

// layoutFolderDialog renders the centered folder-editor card (create or
// edit): name, emoticon row, type/exclusion switches, the account's chat
// picker (include ✓ / exclude ✕ / blank), and create/save/delete actions.
// Replaces the content pane; the sidebar stays interactive.
func (a *App) layoutFolderDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.folderDlg
	if folderDlgCancel.Clicked(gtx) {
		a.closeFolderDlg()
	}
	if folderDlgCreate.Clicked(gtx) {
		a.submitFolderDlg()
	}
	if folderDlgDelete.Clicked(gtx) {
		a.deleteFolderDlg()
	}

	// Account chats for the picker.
	var chats []engine.ChatInfo
	for _, c := range f.chats {
		if c.AccountID == d.accountID {
			chats = append(chats, c)
		}
	}
	growClickables(&folderDlgChatBtns, len(chats))
	growClickables(&folderDlgEmoBtns, len(folderDlgEmoticons))

	title, saveLabel := "New folder", "Create"
	if d.editing != "" {
		title, saveLabel = "Edit folder", "Save"
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(360))
		if gtx.Constraints.Max.Y > gtx.Dp(unit.Dp(560)) {
			gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(560))
		}
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.H3(title)
						return lbl.Layout(gtx)
					}),
					// Name.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
								return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									ed := a.ui.Editor(&folderNameEditor, "Folder name")
									return ed.Layout(gtx)
								})
							})
						})
					}),
					// Emoticon pick row.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, a.folderDlgEmoRow(gtx)...)
						})
					}),
					// Flags + chat picker (scrollable).
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return a.folderDlgBody(gtx, f, d, chats)
					}),
					// Footer.
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									if d.editing == "" {
										return layout.Dimensions{}
									}
									btn := a.ui.TextButton(&folderDlgDelete, "Delete")
									btn.Color = a.ui.p.Error
									return btn.Layout(gtx)
								}),
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.TextButton(&folderDlgCancel, "Cancel")
									return btn.Layout(gtx)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.PrimaryButton(&folderDlgCreate, saveLabel)
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

// folderDlgEmoRow renders the emoticon choices ("" = none).
func (a *App) folderDlgEmoRow(gtx layout.Context) []layout.FlexChild {
	kids := make([]layout.FlexChild, 0, len(folderDlgEmoticons))
	for i, e := range folderDlgEmoticons {
		e, i := e, i
		kids = append(kids, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			btn := &folderDlgEmoBtns[i]
			if btn.Clicked(gtx) {
				a.setFolderDlgEmoticon(e)
			}
			cur := folderDlgEmoticon == e
			return layout.Inset{Right: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				bg := a.ui.p.SurfaceHi
				if cur {
					bg = a.ui.p.AccentDim
				}
				return roundedFill(gtx, bg, 8, func(gtx layout.Context) layout.Dimensions {
					return material.ButtonLayout(a.ui.Theme, btn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						cell := gtx.Dp(unit.Dp(30))
						gtx.Constraints.Min = image.Pt(cell, cell)
						gtx.Constraints.Max = gtx.Constraints.Min
						return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
							txt := e
							if txt == "" {
								txt = "—"
							}
							lbl := a.ui.Label(unit.Sp(14), txt)
							lbl.Color = a.ui.p.Text
							return lbl.Layout(gtx)
						})
					})
				})
			})
		}))
	}
	return kids
}

// folderDlgBody: switches + chat picker, scrollable.
func (a *App) folderDlgBody(gtx layout.Context, f frame, d *folderDlgState, chats []engine.ChatInfo) layout.Dimensions {
	list := &folderDlgList
	list.Axis = layout.Vertical
	ml := material.List(a.ui.Theme, list)
	return ml.Layout(gtx, 1, func(gtx layout.Context, _ int) layout.Dimensions {
		var kids []layout.FlexChild
		for _, fl := range folderDlgFlags {
			fl := fl
			kids = append(kids, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.folderDlgSwitchRow(gtx, fl.key, fl.label)
			}))
		}
		kids = append(kids, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Label(unit.Sp(12), "Chats — tap: include → exclude → none")
				lbl.Color = a.ui.p.TextDim
				return lbl.Layout(gtx)
			})
		}))
		for i, c := range chats {
			c, i := c, i
			kids = append(kids, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := &folderDlgChatBtns[i]
				if btn.Clicked(gtx) {
					a.cycleFolderDlgChat(c.ChatID)
				}
				state := " "
				if d.include[c.ChatID] {
					state = "\u2713"
				} else if d.exclude[c.ChatID] {
					state = "\u2715"
				}
				bl := material.ButtonLayout(a.ui.Theme, btn)
				bl.Background = a.ui.p.Surface
				bl.CornerRadius = 0
				return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(5), Bottom: unit.Dp(5), Left: unit.Dp(6), Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								gtx.Constraints.Min.X = gtx.Dp(unit.Dp(18))
								lbl := a.ui.Label(unit.Sp(14), state)
								switch state {
								case "\u2713":
									lbl.Color = a.ui.p.Accent
								case "\u2715":
									lbl.Color = a.ui.p.Error
								default:
									lbl.Color = a.ui.p.TextFaint
								}
								return lbl.Layout(gtx)
							}),
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), c.Title)
								lbl.MaxLines = 1
								return lbl.Layout(gtx)
							}),
						)
					})
				})
			}))
		}
		if len(chats) == 0 {
			kids = append(kids, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(13), "No chats on this account yet")
				lbl.Color = a.ui.p.TextDim
				return lbl.Layout(gtx)
			}))
		}
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, kids...)
	})
}

var folderDlgList widget.List

// folderDlgSwitchRow: label + switch, flipping dialog state.
func (a *App) folderDlgSwitchRow(gtx layout.Context, key, label string) layout.Dimensions {
	sw := folderDlgSwitch(key)
	prev := sw.Value
	dims := layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Label(unit.Sp(13), label)
				return lbl.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				tg := material.Switch(a.ui.Theme, sw, "")
				tg.Color.Enabled = a.ui.p.Accent
				tg.Color.Disabled = a.ui.p.SurfaceHi
				tg.Color.Track = a.ui.p.SurfaceHi
				return tg.Layout(gtx)
			}),
		)
	})
	if sw.Value != prev {
		a.setFolderDlgFlag(key, sw.Value)
	}
	return dims
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
