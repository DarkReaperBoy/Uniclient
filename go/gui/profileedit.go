package gui

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/x/explorer"

	"uniclient/engine"
)

// Edit profile (AyuGram parity slice 71): per-account profile editor in
// Settings → Main. Surface: avatar upload (UploadProfilePhoto via the OS
// picker), username (UpdateAccountUsername), bio (UpdateBio) and birthday
// (UpdateBirthday). Values the engine cannot change yet (display name,
// phone) are shown read-only — never a dead editor (AGENTS.md §1.10).
//
// Editor state is only touched on the GUI goroutine (captured into the
// apply closures at click time); engine calls run on background goroutines
// and a successful apply re-loads the whole editor from the server.

type profileEditState struct {
	accountID   string
	loaded      bool
	busy        bool
	displayName string
	username    string
	bio         string
	phone       string
	avatarPath  string
	bdayDay     int
	bdayMonth   int
	bdayYear    int
}

var (
	profileUserEd   widget.Editor
	profileBioEd    widget.Editor
	profileBdayD    widget.Editor
	profileBdayM    widget.Editor
	profileBdayY    widget.Editor
	profilePhotoBtn widget.Clickable
	profileUserBtn  widget.Clickable
	profileBioBtn   widget.Clickable
	profileBdayBtn  widget.Clickable
	profileBackBtn  widget.Clickable
	profileEdSynced bool
)

func init() {
	profileUserEd.SingleLine = true
	profileBioEd.SingleLine = true
	profileBioEd.MaxLen = 140
	profileBdayD.SingleLine = true
	profileBdayM.SingleLine = true
	profileBdayY.SingleLine = true
}

// openProfileEdit starts the editor for an account and loads its profile.
func (a *App) openProfileEdit(accountID string) {
	a.mu.Lock()
	a.profileEdit = &profileEditState{accountID: accountID}
	a.mu.Unlock()
	profileEdSynced = false
	go a.loadProfileEdit(accountID)
	a.invalidate()
}

func (a *App) closeProfileEdit() {
	a.mu.Lock()
	a.profileEdit = nil
	a.mu.Unlock()
	profileEdSynced = false
	a.invalidate()
}

// loadProfileEdit fetches the current values (server-first via the engine).
func (a *App) loadProfileEdit(accountID string) {
	st := &profileEditState{accountID: accountID}
	for _, acc := range a.eng.ListAccounts() {
		if acc.ID == accountID {
			st.displayName = acc.DisplayName
			st.username = acc.Username
			st.phone = acc.Phone
			st.avatarPath = acc.AvatarPath
			break
		}
	}
	if acc, ok := accountByIDSnapshot(a, accountID); ok && acc.SelfUserID != "" {
		if p, err := a.eng.GetUserProfile(accountID, acc.SelfUserID); err == nil && p != nil {
			if p.Bio != "" {
				st.bio = p.Bio
			}
			if p.Username != "" {
				st.username = p.Username
			}
			if p.Phone != "" {
				st.phone = p.Phone
			}
			if p.DisplayName != "" {
				st.displayName = p.DisplayName
			}
			if p.BirthdayDay > 0 {
				st.bdayDay = p.BirthdayDay
				st.bdayMonth = p.BirthdayMonth
				st.bdayYear = p.BirthdayYear
			}
		}
	}
	if bio, err := a.eng.GetSelfBio(accountID); err == nil && bio != "" {
		st.bio = bio
	}
	if d, m, y, err := a.eng.GetSelfBirthday(accountID); err == nil && d > 0 {
		st.bdayDay, st.bdayMonth, st.bdayYear = d, m, y
	}
	st.loaded = true
	a.mu.Lock()
	if a.profileEdit != nil && a.profileEdit.accountID == accountID {
		a.profileEdit = st
	}
	a.mu.Unlock()
	profileEdSynced = false
	a.invalidate()
}

// accountByIDSnapshot resolves an account under lock (helper).
func accountByIDSnapshot(a *App, id string) (engine.AccountInfo, bool) {
	a.mu.Lock()
	defer a.mu.Unlock()
	for _, acc := range a.accounts {
		if acc.ID == id {
			return acc, true
		}
	}
	return engine.AccountInfo{}, false
}

// validateUsername: "" (no change) or Telegram's [a-z][a-z0-9_]{4,31}.
func validateUsername(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	if s == "" {
		return ""
	}
	switch {
	case len(s) < 5:
		return "at least 5 characters"
	case len(s) > 32:
		return "at most 32 characters"
	}
	if s[0] < 'a' || s[0] > 'z' {
		return "must start with a letter"
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '_') {
			return "only letters, digits and _"
		}
	}
	return ""
}

// validateBio: at most 70 characters (server limit).
func validateBio(s string) string {
	if len([]rune(s)) > 70 {
		return "at most 70 characters"
	}
	return ""
}

// parseBirthday parses D/M/Y fields; all empty = clear (0/0/0). Year may be
// empty (hidden year). Returns a user-facing message on error.
func parseBirthday(ds, ms, ys string) (int, int, int, string) {
	ds, ms, ys = strings.TrimSpace(ds), strings.TrimSpace(ms), strings.TrimSpace(ys)
	if ds == "" && ms == "" && ys == "" {
		return 0, 0, 0, ""
	}
	if ds == "" || ms == "" {
		return 0, 0, 0, "day and month are required"
	}
	d, err := strconv.Atoi(ds)
	if err != nil {
		return 0, 0, 0, "day must be a number"
	}
	m, err := strconv.Atoi(ms)
	if err != nil {
		return 0, 0, 0, "month must be a number"
	}
	y := 0
	if ys != "" {
		y, err = strconv.Atoi(ys)
		if err != nil {
			return 0, 0, 0, "year must be a number"
		}
	}
	if d < 1 || d > 31 {
		return 0, 0, 0, "day must be 1-31"
	}
	if m < 1 || m > 12 {
		return 0, 0, 0, "month must be 1-12"
	}
	if y != 0 && (y < 1800 || y > time.Now().Year()) {
		return 0, 0, 0, "year looks wrong"
	}
	// Day-in-month sanity (Feb and 30-day months).
	dim := 31
	switch m {
	case 2:
		dim = 29
	case 4, 6, 9, 11:
		dim = 30
	}
	if d > dim {
		return 0, 0, 0, "that month has fewer days"
	}
	return d, m, y, ""
}

var monthNames = [13]string{"", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

// birthdayLabel renders the stored birthday for display.
func birthdayLabel(d, m, y int) string {
	if d == 0 || m == 0 || m < 1 || m > 12 {
		return "not set"
	}
	if y > 0 {
		return fmt.Sprintf("%s %d, %d", monthNames[m], d, y)
	}
	return fmt.Sprintf("%s %d", monthNames[m], d)
}

// layoutProfileEdit renders the editor page inside the settings surface.
func (a *App) layoutProfileEdit(gtx layout.Context, f frame, st *profileEditState) layout.Dimensions {
	if profileBackBtn.Clicked(gtx) {
		a.closeProfileEdit()
		return layout.Dimensions{}
	}
	if !st.loaded {
		return a.loadingNote(gtx)
	}
	if !profileEdSynced {
		profileUserEd.SetText(st.username)
		profileBioEd.SetText(st.bio)
		profileBdayD.SetText("")
		profileBdayM.SetText("")
		profileBdayY.SetText("")
		if st.bdayDay > 0 {
			profileBdayD.SetText(strconv.Itoa(st.bdayDay))
			profileBdayM.SetText(strconv.Itoa(st.bdayMonth))
			if st.bdayYear > 0 {
				profileBdayY.SetText(strconv.Itoa(st.bdayYear))
			}
		}
		profileEdSynced = true
	}
	acc, _ := accountByIDSnapshot(a, st.accountID)

	var children []layout.FlexChild
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Bottom: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.IconButton(&profileBackBtn, iconNavigationBack, "Back")
					btn.Color = a.ui.p.TextDim
					return btn.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.H3("Edit profile · " + platformTitle(acc.Platform))
					return lbl.Layout(gtx)
				}),
			)
		})
	}))

	// Avatar + change-photo.
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.profileAvatar(gtx, st, acc, unit.Dp(64))
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if profilePhotoBtn.Clicked(gtx) {
						a.pickProfilePhoto(st.accountID)
					}
					return layout.Inset{Left: unit.Dp(16)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.SurfaceButton(&profilePhotoBtn, "Change photo")
						return btn.Layout(gtx)
					})
				}),
			)
		})
	}))

	// Read-only rows: display name and phone (no engine setter yet).
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Name", st.displayName)
	}))
	if st.phone != "" {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.settingRow(gtx, "Phone", st.phone)
		}))
	}

	// Username editor: the editor text is captured on the GUI thread at
	// click time; the engine call + reload run in the background.
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Username", "5-32 characters: letters, digits, underscore")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.markEditorRow(gtx, &profileUserEd, "Username")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		if profileUserBtn.Clicked(gtx) {
			u := strings.ToLower(strings.TrimSpace(profileUserEd.Text()))
			go func() {
				if msg := validateUsername(u); msg != "" {
					a.setToast("Username: " + msg)
					return
				}
				if u == "" || u == st.username {
					return
				}
				if err := a.eng.UpdateAccountUsername(st.accountID, u); err != nil {
					a.setToast("Username: " + err.Error())
					return
				}
				a.setToast("Username updated")
				a.loadProfileEdit(st.accountID)
				go a.refreshAccounts()
			}()
		}
		return a.profileApplyRow(gtx, &profileUserBtn, "Apply username")
	}))

	// Bio editor.
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Bio", "Shown on your profile (70 characters max)")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.markEditorRow(gtx, &profileBioEd, "Bio")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		if profileBioBtn.Clicked(gtx) {
			bio := strings.TrimSpace(profileBioEd.Text())
			go func() {
				if msg := validateBio(bio); msg != "" {
					a.setToast("Bio: " + msg)
					return
				}
				if bio == st.bio {
					return
				}
				if err := a.eng.UpdateBio(st.accountID, bio); err != nil {
					a.setToast("Bio: " + err.Error())
					return
				}
				a.setToast("Bio updated")
				a.loadProfileEdit(st.accountID)
			}()
		}
		return a.profileApplyRow(gtx, &profileBioBtn, "Apply bio")
	}))

	// Birthday editor.
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Birthday", "Current: "+birthdayLabel(st.bdayDay, st.bdayMonth, st.bdayYear))
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.markEditorRow(gtx, &profileBdayD, "Day")
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.markEditorRow(gtx, &profileBdayM, "Month")
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.markEditorRow(gtx, &profileBdayY, "Year")
				}),
			)
		})
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		if profileBdayBtn.Clicked(gtx) {
			d, m, y, msg := parseBirthday(profileBdayD.Text(), profileBdayM.Text(), profileBdayY.Text())
			go func() {
				if msg != "" {
					a.setToast("Birthday: " + msg)
					return
				}
				if d == st.bdayDay && m == st.bdayMonth && y == st.bdayYear {
					return
				}
				if err := a.eng.UpdateBirthday(st.accountID, d, m, y); err != nil {
					a.setToast("Birthday: " + err.Error())
					return
				}
				a.setToast("Birthday updated")
				a.loadProfileEdit(st.accountID)
			}()
		}
		return a.profileApplyRow(gtx, &profileBdayBtn, "Apply birthday")
	}))

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// profileApplyRow renders one Apply button (the click handler lives in the
// caller so it can capture editor text on the GUI thread).
func (a *App) profileApplyRow(gtx layout.Context, btn *widget.Clickable, label string) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(12), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		b := a.ui.TextButton(btn, label)
		b.Color = a.ui.p.Accent
		return b.Layout(gtx)
	})
}

// profileAvatar renders the file-backed avatar (async decode; the letter
// avatar shows until the image lands) at the requested size.
func (a *App) profileAvatar(gtx layout.Context, st *profileEditState, acc engine.AccountInfo, size unit.Dp) layout.Dimensions {
	sz := gtx.Dp(size)
	if st.avatarPath != "" {
		if img := a.avatarImage(st.avatarPath, ""); img != nil {
			return drawImageRRectCover(gtx, img, sz)
		}
	}
	name := st.displayName
	if name == "" {
		name = accountName(acc)
	}
	return a.ui.Avatar(gtx, name, size, dotNone)
}

// pickProfilePhoto opens the OS picker and uploads the chosen image.
func (a *App) pickProfilePhoto(accountID string) {
	if a.expl == nil {
		a.setToast("Photo: file picker unavailable on this platform")
		return
	}
	a.mu.Lock()
	if a.profileEdit != nil {
		a.profileEdit.busy = true
	}
	a.mu.Unlock()
	a.invalidate()
	go func() {
		rcs, err := a.expl.ChooseFiles(photoExts...)
		if err != nil {
			if !errors.Is(err, explorer.ErrUserDecline) && !errors.Is(err, explorer.ErrNotAvailable) {
				a.setToast("Photo: " + err.Error())
			}
			a.mu.Lock()
			if a.profileEdit != nil {
				a.profileEdit.busy = false
			}
			a.mu.Unlock()
			a.invalidate()
			return
		}
		paths, temps := resolveUploadPaths(rcs)
		defer func() {
			for _, t := range temps {
				os.Remove(t)
			}
		}()
		if len(paths) == 0 {
			a.setToast("Photo: could not read the selected file")
			return
		}
		if err := a.eng.UploadProfilePhoto(accountID, paths[0]); err != nil {
			a.setToast("Photo: " + err.Error())
			return
		}
		a.setToast("Profile photo updated")
		go a.refreshAccounts()
		a.loadProfileEdit(accountID)
	}()
}
