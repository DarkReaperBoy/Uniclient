package gui

// foldermgr.go — slice 142: the Chat Folders manager (tdesktop's
// Settings → Chat settings → "Filter chats" box). Lists the account's
// folders with edit / reorder / delete, a create row, and the server's
// suggested folders (messages.getSuggestedFilters surfaced through
// engine.GetSuggestedFolders) — tapping a suggestion seeds the standard
// folder editor with its rules, exactly tdesktop's suggested-filter
// flow. Everything rides the existing engine folder CRUD; cores without
// folders render the honest empty state.

import (
	"strconv"

	"gioui.org/font"
	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// ── pure helpers (unit-tested) ─────────────────────────────────────────────

// folderMgrChatsLabel: the folder row's chat-count subtitle. Pure.
func folderMgrChatsLabel(n int) string {
	if n == 1 {
		return "1 chat"
	}
	return itoa(n) + " chats"
}

// folderSuggestsVisible hides suggestions whose name already exists as
// a folder (tdesktop hides created suggestions). Pure.
func folderSuggestsVisible(sug []engine.SuggestedFolderInfo, folders []engine.FolderInfo) []engine.SuggestedFolderInfo {
	have := make(map[string]bool, len(folders))
	for _, f := range folders {
		have[f.Name] = true
	}
	var out []engine.SuggestedFolderInfo
	for _, s := range sug {
		if !have[s.Name] {
			out = append(out, s)
		}
	}
	return out
}

// swapFolderIDs swaps row idx with its neighbour in the delta direction,
// clamped at the ends; the input slice is never mutated. Pure.
func swapFolderIDs(ids []string, idx, delta int) []string {
	out := make([]string, len(ids))
	copy(out, ids)
	j := idx + delta
	if idx < 0 || j < 0 || idx >= len(out) || j >= len(out) {
		return out
	}
	out[idx], out[j] = out[j], out[idx]
	return out
}

// ── state ──────────────────────────────────────────────────────────────────

// folderMgrState is the open Folders manager sub-page.
type folderMgrState struct {
	accountID string
	loading   bool
	loaded    bool
	err       string

	folders   []engine.FolderInfo
	suggested []engine.SuggestedFolderInfo
}

var (
	folderMgrOpenBtn   widget.Clickable // Settings → Main entry card
	folderMgrBackBtn   widget.Clickable
	folderMgrReloadBtn widget.Clickable
	folderMgrNewBtn    widget.Clickable

	folderMgrEditBtns []widget.Clickable
	folderMgrUpBtns   []widget.Clickable
	folderMgrDownBtns []widget.Clickable
	folderMgrDelBtns  []widget.Clickable
	folderMgrSugBtns  []widget.Clickable // suggested rows
	folderMgrAcctBtns []widget.Clickable
)

// openFolderMgr starts the manager for an account and loads its data.
func (a *App) openFolderMgr(accountID string) {
	a.mu.Lock()
	a.folderMgr = &folderMgrState{accountID: accountID, loading: true}
	a.profileEdit = nil // one sub-page at a time (settings shell)
	a.stickerMgr = nil
	a.businessPage = nil
	a.mu.Unlock()
	go a.loadFolderMgr(accountID)
	a.invalidate()
}

// closeFolderMgr dismisses the page.
func (a *App) closeFolderMgr() {
	a.mu.Lock()
	a.folderMgr = nil
	a.mu.Unlock()
	a.invalidate()
}

// loadFolderMgr fetches the account's folders + server suggestions.
func (a *App) loadFolderMgr(accountID string) {
	folders, errF := a.eng.GetFolders(accountID)
	suggested, errS := a.eng.GetSuggestedFolders(accountID)
	a.mu.Lock()
	st := a.folderMgr
	if st == nil || st.accountID != accountID {
		a.mu.Unlock()
		return
	}
	st.loading = false
	if errF != nil {
		st.err = errF.Error()
	} else {
		st.err = ""
		st.loaded = true
		st.folders = folders
	}
	if errS == nil {
		st.suggested = suggested
	}
	a.mu.Unlock()
	a.invalidate()
}

// applyFolderMgrMove reorders server-side then reloads (async + toast).
func (a *App) applyFolderMgrMove(st *folderMgrState, idx, delta int) {
	ids := make([]string, len(st.folders))
	for i := range st.folders {
		ids[i] = st.folders[i].ID
	}
	order := swapFolderIDs(ids, idx, delta)
	nums := make([]int, 0, len(order))
	for _, id := range order {
		n, err := strconv.Atoi(id)
		if err != nil {
			return // non-numeric folder IDs (non-telegram cores) — no reorder
		}
		nums = append(nums, n)
	}
	acc := st.accountID
	go func() {
		if err := a.eng.ReorderDialogFilters(acc, nums); err != nil {
			a.setToast("Reorder failed: " + err.Error())
			return
		}
		a.setToast("Folder moved")
		a.reloadFolderMgr()
	}()
}

// applyFolderMgrDelete removes a folder (async + toast + reload).
func (a *App) applyFolderMgrDelete(st *folderMgrState, folder engine.FolderInfo) {
	acc := st.accountID
	go func() {
		if err := a.eng.DeleteFolder(acc, folder.ID); err != nil {
			a.setToast("Delete folder: " + err.Error())
			return
		}
		a.setToast("Folder deleted")
		a.reloadFolderMgr()
	}()
}

// reloadFolderMgr re-pulls after a mutation.
func (a *App) reloadFolderMgr() {
	a.mu.Lock()
	acc := ""
	if st := a.folderMgr; st != nil {
		acc = st.accountID
		st.loading = true
	}
	a.mu.Unlock()
	if acc != "" {
		go a.loadFolderMgr(acc)
	}
}

// openFolderDlgSuggested seeds the create dialog from a server
// suggestion: rules + name prefilled, the user tweaks then saves —
// tdesktop's suggested-filter flow.
func (a *App) openFolderDlgSuggested(accountID string, s engine.SuggestedFolderInfo) {
	st := &folderDlgState{
		accountID:   accountID,
		include:     map[string]bool{},
		exclude:     map[string]bool{},
		contacts:    s.Contacts,
		nonContacts: s.NonContacts,
		groups:      s.Groups,
		channels:    s.Channels,
		bots:        s.Bots,
	}
	syncFolderDlgSwitches(st)
	a.mu.Lock()
	a.folderDlg = st
	a.mu.Unlock()
	folderNameEditor.SetText(s.Name)
	folderDlgEmoticon = ""
	a.invalidate()
}

// ── layout ─────────────────────────────────────────────────────────────────

// layoutFolderMgr renders the manager sub-page inside the settings shell.
func (a *App) layoutFolderMgr(gtx layout.Context, f frame) layout.Dimensions {
	st := f.folderMgr
	if st == nil {
		return layout.Dimensions{}
	}
	if folderMgrBackBtn.Clicked(gtx) {
		a.closeFolderMgr()
	}
	if folderMgrReloadBtn.Clicked(gtx) {
		a.reloadFolderMgr()
	}
	if folderMgrNewBtn.Clicked(gtx) {
		a.openFolderDlgFor(st.accountID)
	}

	var children []layout.FlexChild

	// header: back + title + reload
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.IconButton(&folderMgrBackBtn, iconNavigationBack, "Back")
					return btn.Layout(gtx)
				}),
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(17), "Chat Folders")
					lbl.Font.Weight = font.SemiBold
					return lbl.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.IconButton(&folderMgrReloadBtn, iconActionSchedule, "Reload")
					return btn.Layout(gtx)
				}),
			)
		})
	}))

	// account switcher chips (multiple accounts only)
	if len(f.accounts) > 1 {
		growClickables(&folderMgrAcctBtns, len(f.accounts))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, a.folderMgrAcctChips(gtx, f, st)...)
			})
		}))
	}

	// body
	if st.loading && !st.loaded {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.loadingNote(gtx)
		}))
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
	}
	if st.err != "" {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(13), st.err)
			return lbl.Layout(gtx)
		}))
	}

	n := len(st.folders)
	growClickables(&folderMgrUpBtns, n)
	growClickables(&folderMgrDownBtns, n)
	growClickables(&folderMgrEditBtns, n)
	growClickables(&folderMgrDelBtns, n)
	sug := folderSuggestsVisible(st.suggested, st.folders)
	growClickables(&folderMgrSugBtns, len(sug))

	for i, folder := range st.folders {
		i, folder := i, folder
		if folderMgrEditBtns[i].Clicked(gtx) {
			a.openFolderDlgEditFor(st.accountID, folder)
		}
		if folderMgrUpBtns[i].Clicked(gtx) && i > 0 {
			a.applyFolderMgrMove(st, i, -1)
		}
		if folderMgrDownBtns[i].Clicked(gtx) && i < n-1 {
			a.applyFolderMgrMove(st, i, +1)
		}
		if folderMgrDelBtns[i].Clicked(gtx) {
			a.applyFolderMgrDelete(st, folder)
		}
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.folderMgrRow(gtx, folder, i, n,
				&folderMgrEditBtns[i], &folderMgrUpBtns[i], &folderMgrDownBtns[i], &folderMgrDelBtns[i])
		}))
	}

	if n == 0 && st.err == "" {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(13), "No folders yet")
			return lbl.Layout(gtx)
		}))
	}

	// create row
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			btn := a.ui.SurfaceButton(&folderMgrNewBtn, "Create new folder")
			return btn.Layout(gtx)
		})
	}))

	// suggested folders (server recommendations, minus already-created)
	if len(sug) > 0 {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.subHeader(gtx, "Suggested")
		}))
		for i, s := range sug {
			i, s := i, s
			if folderMgrSugBtns[i].Clicked(gtx) {
				a.openFolderDlgSuggested(st.accountID, s)
			}
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return a.folderMgrSugRow(gtx, s, &folderMgrSugBtns[i])
			}))
		}
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// folderMgrRow: one folder — emoticon chip, name + chat count, edit,
// ▲▼ reorder, delete.
func (a *App) folderMgrRow(gtx layout.Context, folder engine.FolderInfo, i, n int, edit, up, down, del *widget.Clickable) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.folderMgrEmoChip(gtx, folder.Emoticon)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), folder.Name)
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								sub := folderMgrChatsLabel(len(folder.ChatIDs))
								if folder.IsChatList {
									sub = "invite-link folder"
								}
								lbl := a.ui.Dim(unit.Sp(11), sub)
								return lbl.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if i == 0 {
							return layout.Dimensions{}
						}
						btn := a.ui.IconButton(up, iconMgrUp, "Move up")
						return btn.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if i == n-1 {
							return layout.Dimensions{}
						}
						btn := a.ui.IconButton(down, iconMgrDown, "Move down")
						return btn.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.IconButton(edit, iconContentCreate, "Edit")
						return btn.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.IconButton(del, iconActionDelete, "Delete")
						return btn.Layout(gtx)
					}),
				)
			})
		})
	})
}

// folderMgrSugRow: one suggested folder — name + description, tap seeds
// the editor.
func (a *App) folderMgrSugRow(gtx layout.Context, s engine.SuggestedFolderInfo, btn *widget.Clickable) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		bl := material.ButtonLayout(a.ui.Theme, btn)
		bl.Background = a.ui.p.Surface
		bl.CornerRadius = 10
		return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(14), s.Name)
						lbl.Color = a.ui.p.Accent
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Dim(unit.Sp(11), s.Description)
						return lbl.Layout(gtx)
					}),
				)
			})
		})
	})
}

// folderMgrEmoChip renders the folder's emoticon (folder glyph fallback).
func (a *App) folderMgrEmoChip(gtx layout.Context, emoticon string) layout.Dimensions {
	txt := emoticon
	if txt == "" {
		txt = "🗂"
	}
	return roundedFill(gtx, a.ui.p.SurfaceHi, 8, func(gtx layout.Context) layout.Dimensions {
		return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			gtx.Constraints.Min = gtx.Constraints.Max
			lbl := a.ui.Label(unit.Sp(15), txt)
			return lbl.Layout(gtx)
		})
	})
}

// folderMgrAcctChips builds the account chip row for the manager.
func (a *App) folderMgrAcctChips(gtx layout.Context, f frame, st *folderMgrState) []layout.FlexChild {
	var children []layout.FlexChild
	for i, acc := range f.accounts {
		i, acc := i, acc
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if folderMgrAcctBtns[i].Clicked(gtx) && acc.ID != st.accountID {
				a.openFolderMgr(acc.ID)
			}
			active := acc.ID == st.accountID
			bg := a.ui.p.SurfaceHi
			txtCol := a.ui.p.TextDim
			if active {
				bg = a.ui.p.AccentDim
				txtCol = a.ui.p.Accent
			}
			return layout.Inset{Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				bl := material.ButtonLayout(a.ui.Theme, &folderMgrAcctBtns[i])
				bl.Background = bg
				bl.CornerRadius = 14
				return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(12), accountName(acc))
						lbl.Color = txtCol
						return lbl.Layout(gtx)
					})
				})
			})
		}))
	}
	return children
}

// folderMgrEntryRow renders the Settings → Main entry card.
func (a *App) folderMgrEntryRow(gtx layout.Context, f frame) layout.Dimensions {
	if folderMgrOpenBtn.Clicked(gtx) {
		a.openFolderMgr(mgrAccountID(f))
	}
	return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return iconFileFolder.Layout(gtx, a.ui.p.Accent)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), "Chat Folders")
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(11), "Manage folders, reorder, suggested folders")
								return lbl.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return iconNavChevronRight.Layout(gtx, a.ui.p.TextDim)
					}),
				)
			})
		})
	})
}
