package gui

import (
	"errors"
	"image"
	"io"
	"os"
	"strings"

	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"gioui.org/x/explorer"

	"uniclient/cores"
)

var photoExts = []string{".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".mp4", ".mov", ".webm", ".mkv"}

var musicExts = []string{".mp3", ".m4a", ".flac", ".ogg", ".oga", ".opus", ".wav", ".aac", ".wma"}

type attachMenuItem struct {
	label string
	icon  *widget.Icon
	run   func()
}

func (a *App) attachMenuItems() []attachMenuItem {
	items := []attachMenuItem{
		{label: "Photo or Video", icon: iconImagePhoto, run: func() { a.pickAndSendExts(photoExts) }},
		{label: "File", icon: iconFileAttach, run: func() { a.pickAndSendExts(nil) }},
		{label: "Poll", icon: iconSocialPoll, run: func() { a.openPollDialog() }},
	}
	if mainOnlySurfaceShown(a) {
		items = append(items,
			attachMenuItem{label: "Music", icon: iconAVNote, run: func() { a.openMusicAttach() }},
			attachMenuItem{label: "Location", icon: iconMapsPlace, run: func() { a.openAttachDialog("location") }},
			attachMenuItem{label: "Contact", icon: iconCommunicationContacts, run: func() { a.openAttachDialog("contact") }},
		)
	}
	return items
}

func (a *App) toggleAttachMenu() {
	a.mu.Lock()
	a.emojiOpen = false
	a.attachMenuOpen = !a.attachMenuOpen
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) closeAttachMenu() {
	a.mu.Lock()
	a.attachMenuOpen = false
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) layoutAttachMenu(gtx layout.Context, f frame) layout.Dimensions {
	items := a.attachMenuItems()
	growClickables(&a.wid.attachMenuBtns, len(items))

	menuW := gtx.Dp(unit.Dp(210))
	rowH := gtx.Dp(unit.Dp(40))
	h := len(items)*rowH + gtx.Dp(unit.Dp(8))

	pos := image.Pt(gtx.Dp(unit.Dp(10)), gtx.Constraints.Max.Y-h-gtx.Dp(unit.Dp(78)))
	a.attachMenuRect = image.Rect(pos.X, pos.Y, pos.X+menuW, pos.Y+h)

	defer op.Offset(pos).Push(gtx.Ops).Pop()
	gtx.Constraints = layout.Constraints{Max: image.Pt(menuW, h), Min: image.Pt(menuW, h)}
	return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
		children := make([]layout.FlexChild, 0, len(items))
		for i := range items {
			i := i
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				btn := &a.wid.attachMenuBtns[i]
				if btn.Clicked(gtx) {
					run := items[i].run
					a.closeAttachMenu()
					run()
				}
				return attachMenuRow(gtx, a, btn, items[i], rowH)
			}))
		}
		layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
		return layout.Dimensions{Size: image.Pt(menuW, h)}
	})
}

func attachMenuRow(gtx layout.Context, a *App, btn *widget.Clickable, item attachMenuItem, rowH int) layout.Dimensions {
	bl := material.ButtonLayout(a.ui.Theme, btn)
	bl.Background = a.ui.p.Surface
	bl.CornerRadius = 8
	gtx.Constraints.Min.Y = rowH
	return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(9), Bottom: unit.Dp(9), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if item.icon == nil {
						return layout.Dimensions{}
					}
					gtx.Constraints.Min.X = gtx.Dp(unit.Dp(20))
					return item.icon.Layout(gtx, a.ui.p.TextDim)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Left: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(14), item.label)
						return lbl.Layout(gtx)
					})
				}),
			)
		})
	})
}

func (a *App) pickAndSendExts(exts []string) {
	a.mu.Lock()
	k := a.selected
	a.sending = true
	a.mu.Unlock()
	caption := strings.TrimSpace(a.wid.composer.Text())
	if caption != "" {
		a.wid.composer.SetText("")
	}
	a.invalidate()

	go func() {
		defer func() {
			a.mu.Lock()
			a.sending = false
			a.mu.Unlock()
			a.invalidate()
		}()
		if k == nil || a.expl == nil {
			return
		}
		rcs, err := a.expl.ChooseFiles(exts...)
		if err != nil {
			if !errors.Is(err, explorer.ErrUserDecline) && !errors.Is(err, explorer.ErrNotAvailable) {
				a.setToast("Attach: " + err.Error())
			}
			return
		}
		paths, temps := resolveUploadPaths(rcs)
		defer func() {
			for _, t := range temps {
				os.Remove(t)
			}
		}()
		if len(paths) == 0 {
			a.setToast("Attach: could not read the selected files")
			return
		}
		var upErr error
		if len(paths) == 1 {
			_, upErr = a.eng.UploadFileEx(k.AccountID, k.ChatID, paths[0], cores.UploadOptions{Caption: caption})
		} else {
			upErr = a.eng.SendMediaAlbumFromPaths(k.AccountID, k.ChatID, paths, caption, false)
		}
		if upErr != nil {
			a.setToast("Upload failed: " + upErr.Error())
		}
	}()
}

func resolveUploadPaths(rcs []io.ReadCloser) (paths, temps []string) {
	paths = make([]string, 0, len(rcs))
	for _, rc := range rcs {
		if rc == nil {
			continue
		}
		if f, ok := rc.(*os.File); ok {
			paths = append(paths, f.Name())
			rc.Close()
			continue
		}
		tmp, err := os.CreateTemp("", "uniclient-upload-*")
		if err != nil {
			rc.Close()
			continue
		}
		if _, err := io.Copy(tmp, rc); err != nil {
			tmp.Close()
			rc.Close()
			continue
		}
		tmp.Close()
		rc.Close()
		paths = append(paths, tmp.Name())
		temps = append(temps, tmp.Name())
	}
	return paths, temps
}
