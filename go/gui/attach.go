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

// Attach flow (AyuGram parity §4 "Attach menu"): the 📎 button opens a small
// menu (Photo or Video / File); picks go through the OS dialog
// (gioui.org/x/explorer); uploads run through the engine media pipeline —
// single file → UploadFileEx, multiple → SendMediaAlbumFromPaths (album).
// The composer text at attach time becomes the caption (AyuGram behavior).

var (
	attachBtn      widget.Clickable
	attachMenuBtns []widget.Clickable
)

// photoExts are the image/video extensions the "Photo or Video" picker accepts.
var photoExts = []string{".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".mp4", ".mov", ".webm", ".mkv"}

// attachMenuItem describes one attach-menu entry.
type attachMenuItem struct {
	label string
	icon  *widget.Icon
	run   func()
}

func (a *App) attachMenuItems() []attachMenuItem {
	return []attachMenuItem{
		{label: "Photo or Video", icon: iconImagePhoto, run: func() { a.pickAndSend(true) }},
		{label: "File", icon: iconFileAttach, run: func() { a.pickAndSend(false) }},
		{label: "Poll", icon: iconSocialPoll, run: func() { a.openPollDialog() }},
		{label: "Location", icon: iconMapsPlace, run: func() { a.openAttachDialog("location") }},
		{label: "Contact", icon: iconCommunicationContacts, run: func() { a.openAttachDialog("contact") }},
	}
}

// toggleAttachMenu shows or hides the attach popup (closing the emoji
// panel — one helper surface at a time).
func (a *App) toggleAttachMenu() {
	a.mu.Lock()
	a.emojiOpen = false
	a.attachMenuOpen = !a.attachMenuOpen
	a.mu.Unlock()
	a.invalidate()
}

// closeAttachMenu hides the attach popup.
func (a *App) closeAttachMenu() {
	a.mu.Lock()
	a.attachMenuOpen = false
	a.mu.Unlock()
	a.invalidate()
}

// layoutAttachMenu renders the popup anchored bottom-left of the chat column
// (above the composer). Records its rect for outside-press dismissal.
func (a *App) layoutAttachMenu(gtx layout.Context, f frame) layout.Dimensions {
	items := a.attachMenuItems()
	growClickables(&attachMenuBtns, len(items))

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
				btn := &attachMenuBtns[i]
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

// attachMenuRow renders one attach-menu row (icon + label, ripple on press).
func attachMenuRow(gtx layout.Context, a *App, btn *widget.Clickable, item attachMenuItem, rowH int) layout.Dimensions {
	bl := material.ButtonLayout(a.ui.Theme, btn)
	bl.Background = a.ui.p.Surface // invisible against the menu card
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

// pickAndSend opens the OS file picker and uploads the selection (async).
// The composer text at attach time becomes the caption.
func (a *App) pickAndSend(photo bool) {
	a.mu.Lock()
	k := a.selected
	a.sending = true
	a.mu.Unlock()
	caption := strings.TrimSpace(composer.Text())
	if caption != "" {
		composer.SetText("") // frame thread
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
		var exts []string
		if photo {
			exts = photoExts
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

// resolveUploadPaths maps picked readers to local paths: desktop pickers
// return *os.File (use the path directly); streamed content (Android SAF)
// spools to a temp file, returned separately for cleanup.
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
