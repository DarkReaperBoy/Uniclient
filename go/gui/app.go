package gui

import (
	"image"
	"image/color"
	"io"
	"strings"
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

// Root renders the whole app: welcome screen (no accounts + no auth flow),
// or main layout (sidebar + chat view / voice view), plus toast overlay.
func (a *App) Root(gtx layout.Context) {
	// GUI-goroutine hop: a background goroutine scheduled a chat to open
	// (e.g. after group/channel creation). openChat must run on this loop.
	a.consumePendingOpen()
	// Clipboard hop (slice 34): background goroutines queue text to copy.
	a.flushClipboard(gtx)

	f := a.snapshot()
	a.ui.paintBackground(gtx)

	// Local passcode gate (slice 87): locked → ONLY the lock screen
	// renders (no chat content is drawn while locked). Unlocked → the
	// pass-through activity listener feeds the autolock timer.
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
	if f.drawerOpen {
		a.layoutDrawer(gtx, f)
	}
	a.layoutToast(gtx, f)
	// Global keyboard layer (slice 43): registered last so surface-local
	// key handlers consume their events first.
	a.layoutShortcuts(gtx, f)
}

func (u *UI) paintBackground(gtx layout.Context) {
	paintFill(gtx.Ops, u.p.Background, gtx.Constraints.Max)
}

func paintFill(ops *op.Ops, c color.NRGBA, size image.Point) {
	defer clip.Rect{Min: image.Pt(0, 0), Max: size}.Push(ops).Pop()
	paint.Fill(ops, c)
}

// layoutMain: adaptive two-pane on wide windows, single-pane on narrow.
func (a *App) layoutMain(gtx layout.Context, f frame) {
	sidebarMin := gtx.Dp(unit.Dp(300))
	narrow := gtx.Constraints.Max.X < sidebarMin+gtx.Dp(unit.Dp(380))

	showChat := f.selected != nil || f.auth != nil || f.showPicker

	if s := contentDialogSurface(f); s != "" {
		// Phone layout: the full-pane dialog replaces everything below
		// the surface chain (same priority on both layouts).
		a.layoutContentPaneDialog(gtx, f, s)
		return
	}
	if narrow {
		// Phone layout: settings, chat list, or open chat (with back button).
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

	// Desktop: sidebar | content. Login view overlays the content pane.
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
			// Full-pane dialogs (contentDialogSurface — same priority
			// as the narrow chain, including the passcode LOCK, a
			// security gate that must never lose to a surface beneath
			// it). Settings then wins over the login pane: the sidebar
			// gear stays reachable mid-auth (AyuGram keeps Settings
			// reachable); its back button returns to the login form.
			// Regression (2026-09-09): c1fca15c put settings first
			// here, which hid the auto-download editor (opened from
			// settings) and the autolocked PIN screen on desktop
			// whenever settings was open.
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

// contentDialogSurface names the full-pane dialog that replaces the
// content surface, in fixed priority order — shared verbatim by the
// narrow and desktop chains. The passcode LOCK is a security gate: it
// must never lose to a surface beneath it (autolock can fire while
// settings or a chat is open). Dialogs opened from settings beat the
// settings page. Pure — pinned by TestContentPaneDialogSurface after
// the c1fca15c ordering regression (2026-09-09).
func contentDialogSurface(f frame) string {
	switch {
	case f.newDlg != nil:
		return "newChat"
	case f.contactsOpen:
		return "contacts"
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
	case f.autoDlDlg != nil:
		return "autoDownload"
	case f.themeDlg != nil:
		return "chatTheme"
	case f.cloudDlg != nil:
		return "cloudTheme"
	case f.ayuFilterDlg != nil:
		return "ayuFilters"
	}
	return ""
}

// layoutContentPaneDialog renders the surface named by
// contentDialogSurface as the whole content pane.
func (a *App) layoutContentPaneDialog(gtx layout.Context, f frame, surface string) layout.Dimensions {
	switch surface {
	case "newChat":
		return a.layoutNewChatDialog(gtx, f)
	case "contacts":
		return a.layoutContacts(gtx, f)
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
	case "privacy":
		return a.layoutPrivacyScopeDialog(gtx, f)
	case "lock":
		return a.layoutLockDialog(gtx, f)
	case "autoDownload":
		return a.layoutAutoDownloadDialog(gtx, f)
	case "chatTheme":
		return a.layoutChatThemeDialog(gtx, f)
	case "cloudTheme":
		return a.layoutCloudThemeDialog(gtx, f)
	case "ayuFilters":
		return a.layoutAyuFilterDialog(gtx, f)
	}
	return a.layoutEmptyState(gtx)
}

// layoutEmptyState is the "no chat selected" placeholder.
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

// layoutToast shows transient messages bottom-center.
func (a *App) layoutToast(gtx layout.Context, f frame) {
	if f.toast == "" || time.Since(f.toastAt) > 4*time.Second {
		return
	}
	in := layout.Inset{Bottom: unit.Dp(24), Left: unit.Dp(24), Right: unit.Dp(24)}
	// anchor bottom
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

// ── shared widget helpers ────────────────────────────────────────────────

func insetAll(gtx layout.Context, top, right, bottom, left unit.Dp, w layout.Widget) layout.Dimensions {
	return layout.Inset{Top: top, Right: right, Bottom: bottom, Left: left}.Layout(gtx, w)
}

func centerLayout(gtx layout.Context, w layout.Widget) layout.Dimensions {
	return layout.Center.Layout(gtx, w)
}

// surfaceBox paints a rounded rect surface behind w.
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

// DividerV is a vertical divider.
func (u *UI) DividerV(gtx layout.Context) layout.Dimensions {
	w := gtx.Dp(unit.Dp(1))
	h := gtx.Constraints.Max.Y
	defer clip.Rect{Min: image.Pt(0, 0), Max: image.Pt(w, h)}.Push(gtx.Ops).Pop()
	paint.Fill(gtx.Ops, u.p.Divider)
	return layout.Dimensions{Size: image.Pt(w, h)}
}

var _ = widget.Clickable{}
var _ = app.FrameEvent{}

// flushClipboard executes one queued copy (queued by copyTextSoon).
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
