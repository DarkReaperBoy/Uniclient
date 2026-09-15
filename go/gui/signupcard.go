package gui

import (
	"encoding/base64"
	"errors"
	"image"
	"os"
	"strings"

	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"gioui.org/x/explorer"
	"uniclient/engine"
)

// Signup card (slice 193, parity row "Signup (name/photo)" — tdesktop's
// signup form): separate First/Last name fields (the old single-line
// editor could never split "First Last" — the engine expects
// "first\nlast", so last names silently merged into the first) plus an
// optional photo picked from the OS that uploads as the profile picture
// right after account creation (UploadProfilePhoto on the Ready hop).

var (
	signupFirstEd     widget.Editor
	signupLastEd      widget.Editor
	signupPhotoBtn    widget.Clickable
	signupCreateBtn   widget.Clickable
	signupLastEdFocus bool // request the focus hop after first name submits
)

func init() {
	signupFirstEd.SingleLine = true
	signupLastEd.SingleLine = true
}

// signupNameInput composes the engine's "first\nlast" input. Pure.
func signupNameInput(first, last string) string {
	first = strings.TrimSpace(first)
	last = strings.TrimSpace(last)
	if last == "" {
		return first
	}
	return first + "\n" + last
}

// signupNameValid: the first name is required. Pure.
func signupNameValid(first string) bool {
	return strings.TrimSpace(first) != ""
}

// signupPhotoHint: the photo circle's caption. Pure.
func signupPhotoHint(path string) string {
	if path == "" {
		return "Add photo"
	}
	return "Change photo"
}

// signupPickPhoto opens the OS picker and stages the photo (base64 for
// the circle preview via the shared avatar machinery; the temp path
// rides App state until the Ready hop uploads it).
func (a *App) signupPickPhoto() {
	if a.expl == nil {
		a.setToast("Photo: file picker unavailable on this platform")
		return
	}
	go func() {
		rcs, err := a.expl.ChooseFiles(".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif")
		if err != nil {
			if !isUserDecline(err) {
				a.setToast("Photo: " + err.Error())
			}
			return
		}
		paths, temps := resolveUploadPaths(rcs)
		if len(paths) == 0 {
			a.setToast("Photo: could not read the selected file")
			return
		}
		a.mu.Lock()
		a.signupPhotoPath = paths[0]
		a.signupPhotoTemp = temps
		a.signupPhotoB64 = readFileB64(paths[0])
		a.mu.Unlock()
		a.invalidate()
	}()
}

// isUserDecline: picker cancels are silent.
func isUserDecline(err error) bool {
	return errors.Is(err, explorer.ErrUserDecline) || errors.Is(err, explorer.ErrNotAvailable)
}

// readFileB64: whole file as base64 ("" on any error).
func readFileB64(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return base64.StdEncoding.EncodeToString(data)
}

// signupSubmit validates + fires the name submit; the staged photo is
// consumed by submitAuth's Ready hop.
func (a *App) signupSubmit() {
	if !signupNameValid(signupFirstEd.Text()) {
		a.setToast("Enter your first name")
		return
	}
	a.submitAuth(signupNameInput(signupFirstEd.Text(), signupLastEd.Text()))
}

// signupConsumePhoto uploads the staged signup photo right after the
// account reaches Ready (called from submitAuth). Cleans the temp file.
func (a *App) signupConsumePhoto(accountID string) {
	a.mu.Lock()
	path := a.signupPhotoPath
	temps := a.signupPhotoTemp
	a.signupPhotoPath = ""
	a.signupPhotoTemp = nil
	a.signupPhotoB64 = ""
	a.mu.Unlock()
	if accountID == "" || path == "" {
		return
	}
	go func() {
		defer func() {
			for _, t := range temps {
				os.Remove(t)
			}
		}()
		if err := a.eng.UploadProfilePhoto(accountID, path); err != nil {
			a.setToast("Signup photo: " + err.Error())
			return
		}
		a.setToast("Profile photo updated")
		go a.refreshAccounts()
	}()
}

// signupResetPhoto clears staged state (flow cancel / leaving signup).
func (a *App) signupResetPhoto() {
	a.mu.Lock()
	temps := a.signupPhotoTemp
	a.signupPhotoPath = ""
	a.signupPhotoTemp = nil
	a.signupPhotoB64 = ""
	a.mu.Unlock()
	for _, t := range temps {
		os.Remove(t)
	}
}

// layoutSignupCard: the dedicated signup form (replaces the generic
// single-input card for the signup state).
func (a *App) layoutSignupCard(gtx layout.Context, f frame, st *engine.AuthState) layout.Dimensions {
	for {
		ev, ok := signupFirstEd.Update(gtx)
		if !ok {
			break
		}
		if se, isSubmit := ev.(widget.SubmitEvent); isSubmit && se.Text != "" {
			signupLastEdFocus = true
		}
	}
	if signupLastEdFocus {
		gtx.Execute(key.FocusCmd{Tag: &signupLastEd})
		signupLastEdFocus = false
	}
	for {
		ev, ok := signupLastEd.Update(gtx)
		if !ok {
			break
		}
		if _, isSubmit := ev.(widget.SubmitEvent); isSubmit {
			a.signupSubmit()
		}
	}
	if signupCreateBtn.Clicked(gtx) {
		a.signupSubmit()
	}
	if signupPhotoBtn.Clicked(gtx) {
		a.signupPickPhoto()
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Label(unit.Sp(14), "You can change this later.")
			return lbl.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return a.signupPhotoCircle(gtx, f)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(12), signupPhotoHint(f.signupPhotoPath))
								return lbl.Layout(gtx)
							})
						}),
					)
				})
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(16)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return a.labeledEditor(gtx, "First name (required)", &signupFirstEd)
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return a.labeledEditor(gtx, "Last name (optional)", &signupLastEd)
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(16)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				btn := a.ui.PrimaryButton(&signupCreateBtn, "Create account")
				return btn.Layout(gtx)
			})
		}),
	)
}

// signupPhotoCircle: the photo button — staged image preview (shared
// avatar machinery: async decode, circle cover fit) or the initials
// placeholder.
func (a *App) signupPhotoCircle(gtx layout.Context, f frame) layout.Dimensions {
	sizeDp := unit.Dp(84)
	if f.signupPhotoB64 != "" {
		if img := a.avatarImage("", f.signupPhotoB64); img != nil {
			return material.ButtonLayout(a.ui.Theme, &signupPhotoBtn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				gtx.Constraints = layout.Exact(image.Pt(gtx.Dp(sizeDp), gtx.Dp(sizeDp)))
				return avatarFromImage(gtx, a, img, sizeDp, dotNone, a.ui.avatarRadiusPx(gtx.Dp(sizeDp)))
			})
		}
	}
	name := signupFirstEd.Text()
	if name == "" {
		name = "?"
	}
	return material.ButtonLayout(a.ui.Theme, &signupPhotoBtn).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return a.ui.Avatar(gtx, name, sizeDp, dotNone)
	})
}

// labeledEditor: label + editor row.
func (a *App) labeledEditor(gtx layout.Context, label string, ed *widget.Editor) layout.Dimensions {
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(12), label)
			return lbl.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				de := material.Editor(a.ui.Theme, ed, "")
				de.TextSize = unit.Sp(15)
				return de.Layout(gtx)
			})
		}),
	)
}
