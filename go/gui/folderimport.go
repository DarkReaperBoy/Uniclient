package gui

// Folder import dialog (AyuGram "import filters", slice 94): a paste
// field for a previously exported folders blob + Import. Rendered as a
// content-pane replacement (the folder menu lives in the sidebar; the
// dialog takes the content pane like the new-chat dialog).

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
)

// folderImportState is the open import dialog (nil when closed).
type folderImportState struct {
	accountID string
	err       string // last import error, shown inline
	busy      bool
}

var (
	folderImportTag      = new(struct{})
	folderImportEd       widget.Editor
	folderImportGoBtn    widget.Clickable
	folderImportCloseBtn widget.Clickable
)

// openFolderImportDialog opens the paste-import dialog for an account.
func (a *App) openFolderImportDialog(accountID string) {
	a.mu.Lock()
	a.folderImportDlg = &folderImportState{accountID: accountID}
	a.mu.Unlock()
	a.invalidate()
}

// closeFolderImportDialog dismisses the import dialog.
func (a *App) closeFolderImportDialog() {
	a.mu.Lock()
	a.folderImportDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// submitFolderImport runs the import from the editor's contents.
func (a *App) submitFolderImport() {
	a.mu.Lock()
	d := a.folderImportDlg
	data := strings.TrimSpace(folderImportEd.Text())
	if d != nil {
		d.busy = true
		d.err = ""
	}
	accountID := ""
	if d != nil {
		accountID = d.accountID
	}
	a.mu.Unlock()
	if data == "" {
		a.mu.Lock()
		if a.folderImportDlg != nil {
			a.folderImportDlg.err = "Paste the exported folder JSON first"
			a.folderImportDlg.busy = false
		}
		a.mu.Unlock()
		a.invalidate()
		return
	}
	go func() {
		n, err := a.eng.ImportFoldersJSON(accountID, data)
		a.mu.Lock()
		if a.folderImportDlg != nil {
			a.folderImportDlg.busy = false
			if err != nil {
				a.folderImportDlg.err = err.Error()
			}
		}
		a.mu.Unlock()
		if err != nil {
			a.setToast("Import failed: " + err.Error())
			return
		}
		if n == 0 {
			a.setToast("No new folders (all already exist)")
		} else {
			a.setToast("Imported " + itoa(n) + " folder" + pluralS(n))
		}
		a.closeFolderImportDialog()
		a.refreshFolders(accountID)
	}()
}

// layoutFolderImportDialog renders the paste-import dialog.
func (a *App) layoutFolderImportDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.folderImportDlg
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, folderImportTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeFolderImportDialog()
		}
	}
	// The paste field is multi-line (JSON): Enter inserts newlines, so
	// import runs from the button — no submit drain here.
	if folderImportCloseBtn.Clicked(gtx) {
		a.closeFolderImportDialog()
	}
	if folderImportGoBtn.Clicked(gtx) && !d.busy {
		a.submitFolderImport()
	}

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(400))
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(380))
		return roundedFill(gtx, a.ui.p.Surface, 16, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(18)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return a.ui.H3("Import folders").Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(12), "Paste a folders export — existing names are skipped, never duplicated.")
							lbl.Color = a.ui.p.TextFaint
							return lbl.Layout(gtx)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
							return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								folderImportEd.SingleLine = false
								ed := a.ui.Editor(&folderImportEd, "folder JSON")
								return ed.Layout(gtx)
							})
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if d.err == "" {
							return layout.Dimensions{}
						}
						return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(11), d.err)
							lbl.Color = a.ui.p.Error
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								label := "Import"
								if d.busy {
									label = "Importing…"
								}
								bl := material.Button(a.ui.Theme, &folderImportGoBtn, label)
								bl.Background = a.ui.p.Accent
								bl.CornerRadius = 10
								return bl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Left: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									bl := a.ui.TextButton(&folderImportCloseBtn, "Close")
									bl.Color = a.ui.p.TextDim
									return bl.Layout(gtx)
								})
							}),
						)
					}),
				)
			})
		})
	})
}
