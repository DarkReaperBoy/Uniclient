package gui

import (
	"image"
	"strconv"

	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Folder-tab context menu (AyuGram parity, matrix "Folder tabs above
// list"): right-click a server folder tab for Edit / Move left / Move
// right / Invite links / Delete — the same actions Telegram Desktop's
// folder tab menu exposes. Editing opens the folder dialog prefilled
// (folders.go); moving reorders server filters (engine
// ReorderDialogFilters); invite links open the chatlist-share dialog
// (folderinvites.go); deleting calls the engine directly with a toast.

// folderMenuTarget is an open folder-tab context menu.
type folderMenuTarget struct {
	folder    engine.FolderInfo
	accountID string
	pos       image.Point
}

var folderMenuBtns []widget.Clickable

// folderMenuItems derives the menu rows (pure — boundary flags drop the
// unavailable move rows).
func folderMenuItems(canLeft, canRight bool) []chatMenuAction {
	items := []chatMenuAction{{"Edit folder", "edit"}}
	if canLeft {
		items = append(items, chatMenuAction{"Move left", "moveleft"})
	}
	if canRight {
		items = append(items, chatMenuAction{"Move right", "moveright"})
	}
	items = append(items,
		chatMenuAction{"Invite links", "invites"},
		chatMenuAction{"Export folders", "exportf"},
		chatMenuAction{"Import folders…", "importf"},
		chatMenuAction{"Delete folder", "delete"},
	)
	return items
}

// openFolderMenu opens the tab menu at pos.
func (a *App) openFolderMenu(folder engine.FolderInfo, accountID string, pos image.Point) {
	a.mu.Lock()
	a.folderMenu = &folderMenuTarget{folder: folder, accountID: accountID, pos: pos}
	a.mu.Unlock()
	a.invalidate()
}

// closeFolderMenu dismisses it.
func (a *App) closeFolderMenu() {
	a.mu.Lock()
	a.folderMenu = nil
	a.mu.Unlock()
	a.invalidate()
}

// moveServerFolder swaps the folder with its neighbour and persists the
// new order through the engine (async, then refresh + toast).
func (a *App) moveServerFolder(f frame, folder engine.FolderInfo, dir int) {
	accountID := f.foldersFor
	folders := foldersForAccount(f, accountID)
	ids := make([]int, 0, len(folders))
	idx := -1
	for i := range folders {
		id, _ := strconv.Atoi(folders[i].ID)
		ids = append(ids, id)
		if folders[i].ID == folder.ID {
			idx = i
		}
	}
	if idx < 0 || idx+dir < 0 || idx+dir >= len(ids) {
		return
	}
	ids[idx], ids[idx+dir] = ids[idx+dir], ids[idx]
	go func() {
		if err := a.eng.ReorderDialogFilters(accountID, ids); err != nil {
			a.setToast("Reorder failed: " + err.Error())
			return
		}
		a.setToast("Folder moved")
		a.refreshFolders(accountID)
	}()
}

// dispatchFolderMenuAction runs one menu row (all close the menu first).
func (a *App) dispatchFolderMenuAction(f frame, m *folderMenuTarget, action string) {
	switch action {
	case "edit":
		a.openFolderDlgEdit(m.folder)
	case "moveleft":
		a.moveServerFolder(f, m.folder, -1)
	case "moveright":
		a.moveServerFolder(f, m.folder, 1)
	case "invites":
		a.openFolderInvites(m.folder, m.accountID)
	case "exportf":
		accountID := m.accountID
		go func() {
			blob, err := a.eng.ExportFoldersJSON(accountID)
			if err != nil {
				a.setToast("Export: " + err.Error())
				return
			}
			a.copyTextSoon(blob)
			a.setToast("Folders exported to clipboard")
		}()
	case "importf":
		a.openFolderImportDialog(m.accountID)
	case "delete":
		accountID, folder := m.accountID, m.folder
		go func() {
			if err := a.eng.DeleteFolder(accountID, folder.ID); err != nil {
				a.setToast("Delete folder failed: " + err.Error())
				return
			}
			a.setToast("Folder deleted")
			a.refreshFolders(accountID)
		}()
	}
}

// layoutFolderMenu draws the open tab menu, clamped to the sidebar pane.
func (a *App) layoutFolderMenu(gtx layout.Context, f frame) layout.Dimensions {
	m := f.folderMenu
	items := folderMenuItems(a.folderCanMove(f, m.folder, -1), a.folderCanMove(f, m.folder, 1))
	growClickables(&folderMenuBtns, len(items))

	menuW := gtx.Dp(unit.Dp(210))
	rowH := gtx.Dp(unit.Dp(36))
	h := gtx.Dp(unit.Dp(8)) + len(items)*rowH + gtx.Dp(unit.Dp(8))

	pos := m.pos
	paneW, paneH := gtx.Constraints.Max.X, gtx.Constraints.Max.Y
	if pos.X+menuW > paneW {
		pos.X = paneW - menuW
	}
	if pos.X < 0 {
		pos.X = 0
	}
	if pos.Y+h > paneH {
		pos.Y = paneH - h
	}
	if pos.Y < 0 {
		pos.Y = 0
	}
	a.folderMenuRect = image.Rect(pos.X, pos.Y, pos.X+menuW, pos.Y+h)

	defer op.Offset(pos).Push(gtx.Ops).Pop()
	gtx.Constraints = layout.Constraints{Max: image.Pt(menuW, h), Min: image.Pt(menuW, h)}
	return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
		children := make([]layout.FlexChild, 0, len(items))
		for i := range items {
			i := i
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := &folderMenuBtns[i]
				if btn.Clicked(gtx) {
					action := items[i].id
					a.closeFolderMenu()
					a.dispatchFolderMenuAction(f, m, action)
				}
				bl := material.ButtonLayout(a.ui.Theme, btn)
				bl.Background = a.ui.p.Surface
				bl.CornerRadius = 8
				gtx.Constraints.Min.Y = rowH
				return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(9)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(14), items[i].label)
						return lbl.Layout(gtx)
					})
				})
			}))
		}
		layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
		return layout.Dimensions{Size: image.Pt(menuW, h)}
	})
}

// folderCanMove reports whether the folder can move by dir within the
// account's server folder order.
func (a *App) folderCanMove(f frame, folder engine.FolderInfo, dir int) bool {
	folders := foldersForAccount(f, f.foldersFor)
	idx := -1
	for i := range folders {
		if folders[i].ID == folder.ID {
			idx = i
			break
		}
	}
	return idx >= 0 && idx+dir >= 0 && idx+dir < len(folders)
}
