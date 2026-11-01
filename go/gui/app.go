package gui

import (
	"image"
	"image/color"
	"io"
	"strings"
	"sync"
	"time"

	"gioui.org/app"
	"gioui.org/io/clipboard"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
)

var frameMu sync.Mutex

func (a *App) Root(gtx layout.Context) {
	frameMu.Lock()
	defer frameMu.Unlock()

	if sz := gtx.Constraints.Max; sz.X > 0 && sz.Y > 0 {
		a.vpW, a.vpH = sz.X, sz.Y
	}

	a.consumePendingOpen()
	a.consumeCrossWindowHops()
	a.flushClipboard(gtx)

	f := a.snapshot()
	a.ui.paintBackground(gtx)

	if a.isSeparate() {
		if f.lock != nil && f.lock.locked {
			a.layoutLockScreen(gtx, f)
			return
		}
		if len(f.accounts) == 0 && f.auth == nil {
			a.layoutSeparateEmpty(gtx)
			a.layoutToast(gtx, f)
			return
		}
		a.separateChatView(gtx, f)
		if f.viewer != nil {
			a.layoutMediaView(gtx, f)
		}
		if f.iv != nil {
			a.layoutInstantView(gtx, f)
		}
		if f.storyView != nil {
			a.layoutStoryViewer(gtx, f)
		}
		if f.call != nil {
			a.layoutCallOverlay(gtx, f)
		}
		a.layoutPip(gtx, f)
		a.layoutToast(gtx, f)
		a.layoutShortcuts(gtx, f)
		return
	}

	if f.lock != nil {
		if f.lock.locked {
			a.layoutLockScreen(gtx, f)
			return
		}
		a.lockActivityLayer(gtx, f)
		a.lockTick(f)
	}

	if len(f.accounts) == 0 && f.auth == nil {
		a.layoutWelcome(gtx, f)
		a.layoutToast(gtx, f)
		return
	}

	a.layoutMain(gtx, f)
	if f.viewer != nil {
		a.layoutMediaView(gtx, f)
	}
	if f.iv != nil {
		a.layoutInstantView(gtx, f)
	}
	if f.storyView != nil {
		a.layoutStoryViewer(gtx, f)
	}
	if f.call != nil {
		a.layoutCallOverlay(gtx, f)
	}
	if f.rateDlg != nil {
		a.layoutRateCallDialog(gtx, f)
	}
	if f.clearDlg != nil {
		a.layoutClearDialog(gtx, f)
	}
	if f.restrictDlg != nil {
		a.layoutRestrictDialog(gtx, f)
	}
	if f.savedDelDlg != nil {
		a.layoutSavedDeleteDialog(gtx, f)
	}
	if f.drawerOpen {
		a.layoutDrawer(gtx, f)
	}
	a.layoutChatPeek(gtx, f)
	a.layoutPip(gtx, f)
	a.layoutToast(gtx, f)
	a.layoutShortcuts(gtx, f)
}

func (u *UI) paintBackground(gtx layout.Context) {
	paintFill(gtx.Ops, u.p.Background, gtx.Constraints.Max)
}

func paintFill(ops *op.Ops, c color.NRGBA, size image.Point) {
	defer clip.Rect{Min: image.Pt(0, 0), Max: size}.Push(ops).Pop()
	paint.Fill(ops, c)
}

func (a *App) layoutMain(gtx layout.Context, f frame) {
	sidebarMin := gtx.Dp(unit.Dp(300))
	narrow := gtx.Constraints.Max.X < sidebarMin+gtx.Dp(unit.Dp(380))

	showChat := f.selected != nil || f.auth != nil || f.showPicker

	if s := contentDialogSurface(f); s != "" {
		a.layoutContentPaneDialog(gtx, f, s)
		return
	}
	if narrow {
		if f.settingsOpen {
			a.layoutSettings(gtx, f, narrow)
			return
		}
		if showChat && f.mode == 0 {
			if f.auth != nil || f.showPicker {
				a.layoutLogin(gtx, f)
			} else {
				a.layoutChatView(gtx, f, narrow)
			}
		} else if f.mode == 1 {
			a.layoutVoice(gtx, f)
		} else {
			a.layoutSidebar(gtx, f, narrow)
		}
		return
	}

	layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			gtx.Constraints.Max.X = gtx.Dp(unit.Dp(340))
			gtx.Constraints.Min.X = gtx.Dp(unit.Dp(340))
			return a.layoutSidebar(gtx, f, narrow)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.ui.DividerV(gtx)
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			if s := contentDialogSurface(f); s != "" {
				return a.layoutContentPaneDialog(gtx, f, s)
			}
			if f.settingsOpen {
				return a.layoutSettings(gtx, f, narrow)
			}
			if f.auth != nil || f.showPicker {
				return a.layoutLogin(gtx, f)
			}
			if f.mode == 1 {
				return a.layoutVoice(gtx, f)
			}
			if f.selected == nil {
				return a.layoutEmptyState(gtx)
			}
			return a.layoutChatView(gtx, f, narrow)
		}),
	)
}

func contentDialogSurface(f frame) string {
	switch {
	case f.newDlg != nil:
		return "newChat"
	case f.contactsOpen:
		return "contacts"
	case f.callsBoxOpen:
		return "callsBox"
	case f.folderDlg != nil:
		return "folder"
	case f.folderInvites != nil:
		return "folderInvites"
	case f.attachDlg != nil:
		return "attach"
	case f.addMemDlg != nil:
		return "addMember"
	case f.ttlDlg != nil:
		return "ttl"
	case f.privacyDlg != nil:
		return "privacy"
	case f.lockDlg != nil:
		return "lock"
	case f.muteDlg != nil:
		return "mute"
	case f.musicDlg != nil:
		return "profileMusic"
	case f.musicAttachDlg != nil:
		return "musicAttach"
	case f.giftDlg != nil:
		return "giftPicker"
	case f.giveawayDlg != nil:
		return "giveaway"
	case f.twofaDlg != nil:
		return "twofa"
	case f.soundPicker != nil:
		return "sound"
	case f.autoDlDlg != nil:
		return "autoDownload"
	case f.themeDlg != nil:
		return "chatTheme"
	case f.wallpaperDlg != nil:
		return "wallpaper"
	case f.cloudDlg != nil:
		return "cloudTheme"
	case f.ayuFilterDlg != nil:
		return "ayuFilters"
	case f.folderImportDlg != nil:
		return "folderImport"
	case f.exportDlg != nil:
		return "export"
	}
	return ""
}

func (a *App) layoutContentPaneDialog(gtx layout.Context, f frame, surface string) layout.Dimensions {
	switch surface {
	case "newChat":
		return a.layoutNewChatDialog(gtx, f)
	case "contacts":
		return a.layoutContacts(gtx, f)
	case "callsBox":
		return a.layoutCallsBox(gtx, f)
	case "folder":
		return a.layoutFolderDialog(gtx, f)
	case "folderInvites":
		return a.layoutFolderInvites(gtx, f)
	case "attach":
		return a.layoutAttachDialog(gtx, f)
	case "addMember":
		return a.layoutAddMemberDialog(gtx, f)
	case "ttl":
		return a.layoutTtlDialog(gtx, f)
	case "mute":
		return a.layoutMuteDialog(gtx, f)
	case "profileMusic":
		return a.layoutProfileMusic(gtx, f)
	case "musicAttach":
		return a.layoutMusicAttach(gtx, f)
	case "giftPicker":
		return a.layoutGiftPicker(gtx, f)
	case "giveaway":
		return a.layoutGiveaway(gtx, f)
	case "privacy":
		return a.layoutPrivacyScopeDialog(gtx, f)
	case "twofa":
		return a.layoutTwoFADialog(gtx, f)
	case "sound":
		return a.layoutSoundPicker(gtx, f)
	case "lock":
		return a.layoutLockDialog(gtx, f)
	case "autoDownload":
		return a.layoutAutoDownloadDialog(gtx, f)
	case "chatTheme":
		return a.layoutChatThemeDialog(gtx, f)
	case "wallpaper":
		return a.layoutWallpaperDialog(gtx, f)
	case "cloudTheme":
		return a.layoutCloudThemeDialog(gtx, f)
	case "ayuFilters":
		return a.layoutAyuFilterDialog(gtx, f)
	case "folderImport":
		return a.layoutFolderImportDialog(gtx, f)
	case "export":
		return a.layoutExportDialog(gtx, f)
	}
	return a.layoutEmptyState(gtx)
}

func (a *App) layoutEmptyState(gtx layout.Context) layout.Dimensions {
	return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return insetAll(gtx, unit.Dp(0), unit.Dp(0), unit.Dp(12), unit.Dp(0), func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.H2("Select a chat")
					lbl.Color = a.ui.p.TextFaint
					return lbl.Layout(gtx)
				})
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(14), "Pick a conversation on the left, or press + to add an account.")
				lbl.Color = a.ui.p.TextFaint
				return lbl.Layout(gtx)
			}),
		)
	})
}

func (a *App) layoutToast(gtx layout.Context, f frame) {
	if f.toast == "" || time.Since(f.toastAt) > 4*time.Second {
		return
	}
	in := layout.Inset{Bottom: unit.Dp(24), Left: unit.Dp(24), Right: unit.Dp(24)}
	gtx.Constraints.Min.Y = 0
	layout.Stack{Alignment: layout.S}.Layout(gtx,
		layout.Stacked(func(gtx layout.Context) layout.Dimensions {
			return in.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Label(unit.Sp(14), f.toast)
				lbl.Color = a.ui.p.Text
				return surfaceBox(gtx, a.ui, a.ui.p.SurfaceHi, 8, func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{
						Top: unit.Dp(10), Bottom: unit.Dp(10),
						Left: unit.Dp(16), Right: unit.Dp(16),
					}.Layout(gtx, lbl.Layout)
				})
			})
		}),
	)
}

func insetAll(gtx layout.Context, top, right, bottom, left unit.Dp, w layout.Widget) layout.Dimensions {
	return layout.Inset{Top: top, Right: right, Bottom: bottom, Left: left}.Layout(gtx, w)
}

func centerLayout(gtx layout.Context, w layout.Widget) layout.Dimensions {
	return layout.Center.Layout(gtx, w)
}

func surfaceBox(gtx layout.Context, u *UI, c color.NRGBA, radius unit.Dp, w layout.Widget) layout.Dimensions {
	return layout.Stack{}.Layout(gtx,
		layout.Expanded(func(gtx layout.Context) layout.Dimensions {
			r := gtx.Dp(radius)
			size := gtx.Constraints.Min
			defer clip.Rect{Min: image.Pt(0, 0), Max: size}.Push(gtx.Ops).Pop()
			_ = r
			paint.Fill(gtx.Ops, c)
			return layout.Dimensions{Size: size}
		}),
		layout.Stacked(w),
	)
}

func (u *UI) DividerV(gtx layout.Context) layout.Dimensions {
	w := gtx.Dp(unit.Dp(1))
	h := gtx.Constraints.Max.Y
	defer clip.Rect{Min: image.Pt(0, 0), Max: image.Pt(w, h)}.Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, u.p.Divider)
	return layout.Dimensions{Size: image.Pt(w, h)}
}

var _ = widget.Clickable{}
var _ = app.FrameEvent{}

func (a *App) flushClipboard(gtx layout.Context) {
	a.mu.Lock()
	txt := a.pendingCopy
	a.pendingCopy = ""
	a.mu.Unlock()
	if txt == "" {
		return
	}
	gtx.Execute(clipboard.WriteCmd{
		Type: "text/plain",
		Data: io.NopCloser(strings.NewReader(txt)),
	})
}
